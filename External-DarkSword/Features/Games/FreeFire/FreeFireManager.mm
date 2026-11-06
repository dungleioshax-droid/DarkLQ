//
//  FreeFireManager.mm
//  External-DarkSword
//

#import "FreeFireManager.h"
#import "../../../App/Configuration/Macros.h"
#import "../../../App/Notifications/AppNotifications.h"
#import "../../../App/Support/helper.h"
#import "../../Overlay/RemoteWebViewOverlay.h"
#import "../../Unity/Vector3.h"
#import "FreeFireOffset.h"
#import "FreeFireUtils.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <dlfcn.h>
#include <mach/mach.h>

NS_ASSUME_NONNULL_BEGIN

@interface FreeFireEntitySnapshot : NSObject

@property(nonatomic, assign) uint64_t actorAddress;
@property(nonatomic, assign) Vector3 position;
@property(nonatomic, assign) NSInteger health;
@property(nonatomic, assign) NSInteger maxHealth;
@property(nonatomic, copy) NSString *name;

@property(nonatomic, assign) CGFloat screenX;
@property(nonatomic, assign) CGFloat screenY;
@property(nonatomic, assign) CGFloat headX;
@property(nonatomic, assign) CGFloat headY;
@property(nonatomic, assign) CGFloat footX;
@property(nonatomic, assign) CGFloat footY;
@property(nonatomic, assign) CGFloat distance;

@property(nonatomic, assign) BOOL visible;
@property(nonatomic, assign) BOOL onScreen;

@property(nonatomic, assign) CGFloat boxX;
@property(nonatomic, assign) CGFloat boxY;
@property(nonatomic, assign) CGFloat boxW;
@property(nonatomic, assign) CGFloat boxH;

@end

@implementation FreeFireEntitySnapshot
@end

@interface FreeFireManager ()

@property(nonatomic, assign) BOOL isRunning;
@property(nonatomic, copy) NSData *viewProjectionData;
@property(nonatomic, copy) NSArray<FreeFireEntitySnapshot *> *entitySnapshots;
@property(nonatomic, readwrite) BOOL hasValidFrame;
@property(nonatomic, assign) uintptr_t staticFieldsAddress;
@property(nonatomic, assign) uintptr_t baseGameStaticFieldsAddress;
@property(nonatomic, assign) NSTimeInterval lastStaticResolveAttempt;
@property(nonatomic, copy) NSString *binaryBaseSource;
@property(nonatomic, strong) RemoteWebViewOverlay *remoteWebViewOverlay;
@property(nonatomic, assign) NSTimeInterval lastDiscoveryAttempt;
@property(nonatomic, assign) uintptr_t cachedCamera;
@property(nonatomic, assign) uintptr_t cachedCamMgr;
@property(nonatomic, assign) uintptr_t cachedContainerAddress;
@property(nonatomic, assign) uintptr_t lastMatchGame;
@property(nonatomic, assign) uintptr_t lastCtxMatchGame;

- (uint64_t)getFreeFireBaseAddress;
- (void)updateSnapshot:(RemoteCall *)remoteCall;
- (void)showOverlay:(RemoteCall *)remoteCall;
- (BOOL)resolveCamera:(RemoteCall *)remoteCall
            matchGame:(uintptr_t)currentMatchGame
         ctxMatchGame:(uintptr_t)ctxMatchGame
               camera:(uintptr_t *)outCamera
               camMgr:(uintptr_t *)outCamMgr;
- (FreeFireEntityContainer)resolveEntityContainer:(RemoteCall *)remoteCall
                                        matchGame:(uintptr_t)currentMatchGame
                                     ctxMatchGame:(uintptr_t)ctxMatchGame;
- (BOOL)discoveryDue;
- (BOOL)diagnosticsDue;
- (void)reportDiagnostics:(NSString *)message;
- (void)reportStage:(NSString *)stage;
- (void)reportStatus:(NSString *)status;

@end

@implementation FreeFireManager

- (instancetype)initWithRemoteCall:(RemoteCall *)remoteCall {
    return [self initWithRemoteCall:remoteCall overlayRemoteCall:nil];
}

- (instancetype)initWithRemoteCall:(RemoteCall *)remoteCall
                 overlayRemoteCall:(nullable RemoteCall *)overlayRemoteCall {
    self = [super init];
    if (self) {
        _remoteCall = remoteCall;
        _overlayRemoteCall = overlayRemoteCall;
        _useSpringBoardOverlay = (overlayRemoteCall != nil);
        _isESPEnabled = YES;
        _showsLine = YES;
        _showsBox = YES;
        _showsHealth = YES;
        _showsName = YES;
        _showsDistance = YES;
        _isRunning = NO;
        _entitySnapshots = @[];
        _viewProjectionData = [NSData data];
        _binaryBase = 0;
        _staticFieldsAddress = 0;
        _hasValidFrame = NO;
        _cachedCamera = 0;
        _cachedCamMgr = 0;
        _cachedContainerAddress = 0;
        _lastMatchGame = 0;
        _lastCtxMatchGame = 0;
    }
    return self;
}

- (uint64_t)getRealOffset:(uint64_t)offset {
    return self.binaryBase + offset;
}

- (void)runLoop {
    if (!self.remoteCall || self.isRunning)
        return;

    self.isRunning = YES;
    LOG(@"[FreeFire] Starting external snapshot loop...");
    [self reportDiagnostics:
              [NSString stringWithFormat:@"loop started (ESP=%@)",
                                         self.isESPEnabled ? @"on" : @"off"]];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
      uint32_t overlayCooldown = 0;
      uint32_t baseCooldown = 0;
      while (self.isRunning && self.remoteCall) {
          @autoreleasepool {
              if (self.binaryBase == 0) {
                  if (baseCooldown == 0) {
                      self.binaryBase = [self getFreeFireBaseAddress];
                      if (self.binaryBase != 0) {
                          LOG(@"[FreeFire] Binary base: 0x%lx",
                              (unsigned long)self.binaryBase);
                          [self
                              reportDiagnostics:
                                  [NSString
                                      stringWithFormat:@"base=0x%lx (%@)",
                                                       (unsigned long)self
                                                           .binaryBase,
                                                       self.binaryBaseSource ?:
                                                           @"unknown"]];
                      } else {
                          baseCooldown = 50; // Throttle retry to ~0.5s instead of 100 FPS
                          [self reportStatus:@"stage 0/6: binary base not resolved (retrying)"];
                      }
                  } else {
                      baseCooldown--;
                  }
              }

              if (self.binaryBase != 0) {
                  if (!self.remoteWebViewOverlay.isOverlayReady) {
                      if (overlayCooldown == 0) {
                          if (!self.remoteWebViewOverlay) {
                              RemoteCall *callForOverlay =
                                  self.overlayRemoteCall ?: self.remoteCall;
                              BOOL isSpringBoard =
                                  (self.overlayRemoteCall != nil) ||
                                  self.useSpringBoardOverlay;
                              self.remoteWebViewOverlay =
                                  [[RemoteWebViewOverlay alloc]
                                      initWithRemoteCall:callForOverlay
                                           isSpringBoard:isSpringBoard];
                          }
                          if ([self.remoteWebViewOverlay setupBaseOverlay]) {
                              LOG(@"[FreeFire] Overlay setup done (%s).",
                                  self.remoteWebViewOverlay.isSpringBoard ? "SpringBoard" : "Internal");
                          } else {
                              overlayCooldown = 50; // Throttle retry to ~0.5s
                          }
                      } else {
                          overlayCooldown--;
                      }
                  }

                  CFAbsoluteTime frameStart = CFAbsoluteTimeGetCurrent();
                  if (self.isESPEnabled) {
                      [self updateSnapshot:self.remoteCall];
                  }

                  // Never go silent: say why nothing is being drawn.
                  if (!self.remoteWebViewOverlay.isOverlayReady) {
                      [self reportStatus:@"overlay not ready: ESP menu and drawing unavailable"];
                  } else if (!self.isESPEnabled) {
                      [self reportStatus:@"ESP is off: enable Player ESP in the overlay menu"];
                  }

                  CFAbsoluteTime frameEnd = CFAbsoluteTimeGetCurrent();
                  double elapsed = frameEnd - frameStart;
                  double targetInterval = 1.0 / 60.0;
                  if (elapsed < targetInterval) {
                      usleep((useconds_t)((targetInterval - elapsed) * 1000000.0));
                  }
              }
          }
      }
      LOG(@"[FreeFire] Snapshot loop stopped.");
    });
}

- (void)stopLoop {
    self.isRunning = NO;
    @synchronized(self) {
        self.entitySnapshots = @[];
        self.viewProjectionData = [NSData data];
        self.hasValidFrame = NO;
        self.staticFieldsAddress = 0;
        self.lastStaticResolveAttempt = 0;
    }
}

- (void)clearOverlayTargets {
    [self.remoteWebViewOverlay clearTargets];
}

- (void)setOverlayMenuVisible:(BOOL)visible {
    [self.remoteWebViewOverlay setOverlayMenuVisible:visible];
}

- (void)toggleOverlayMenu {
    [self.remoteWebViewOverlay toggleOverlayMenu];
}

- (void)setOverlayFloatButtonPositionX:(CGFloat)xRatio y:(CGFloat)yRatio {
    [self.remoteWebViewOverlay setOverlayFloatButtonPositionX:xRatio y:yRatio];
}

- (void)refreshOverlayLayout {
    [self.remoteWebViewOverlay refreshOverlayLayout];
}

- (BOOL)discoveryDue {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now - self.lastDiscoveryAttempt < 1.0)
        return NO;

    self.lastDiscoveryAttempt = now;
    return YES;
}

- (BOOL)diagnosticsDue {
    static NSTimeInterval lastReport = 0.0;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now - lastReport < 1.0)
        return NO;

    lastReport = now;
    return YES;
}

- (void)reportDiagnostics:(NSString *)message {
    if (message.length == 0 || !self.diagnosticsHandler)
        return;

    LOG(@"[FreeFire] %@", message);
    self.diagnosticsHandler(message);
}

// Stage reports are de-duplicated so the log shows where the chain breaks
// without flooding during the 100 Hz snapshot loop.
- (void)reportStage:(NSString *)stage {
    static NSString *lastStage = nil;

    if (stage.length == 0) {
        lastStage = nil;
        return;
    }

    if (lastStage != nil && [lastStage isEqualToString:stage])
        return;

    lastStage = [stage copy];
    [self reportDiagnostics:stage];
}

// Status lines (base / overlay / ESP toggle) keep their own de-duplication
// slot so they never alternate with stage lines and flood the log.
- (void)reportStatus:(NSString *)status {
    static NSString *lastStatus = nil;
    static NSTimeInterval lastAt = 0;

    if (status.length == 0) {
        lastStatus = nil;
        return;
    }

    if (lastStatus != nil && [lastStatus isEqualToString:status])
        return;

    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (lastStatus != nil && now - lastAt < 0.5)
        return;

    lastStatus = [status copy];
    lastAt = now;
    [self reportDiagnostics:status];
}

- (uint64_t)getFreeFireBaseAddress {
    uint64_t task_info_addr = (uint64_t)dlsym(RTLD_DEFAULT, "task_info");
    uint64_t mach_task_self_addr =
        (uint64_t)dlsym(RTLD_DEFAULT, "mach_task_self_");

    if (!task_info_addr || !mach_task_self_addr) {
        return 0;
    }

    uint32_t target_mach_task_self = 0;
    if (![self.remoteCall remoteRead:mach_task_self_addr
                                  to:&target_mach_task_self
                                size:sizeof(target_mach_task_self)] ||
        target_mach_task_self == MACH_PORT_NULL) {
        return 0;
    }

    uint64_t scratch_addr = [self.remoteCall trojanMem] + 0x100;
    uint32_t count = TASK_DYLD_INFO_COUNT;
    if (![self.remoteCall remote_write:scratch_addr
                                  from:&count
                                  size:sizeof(count)]) {
        return 0;
    }

    uint64_t args[4] = {
        target_mach_task_self, // x0
        TASK_DYLD_INFO,        // x1 = 17
        scratch_addr + 8,      // x2 = task_info_out
        scratch_addr           // x3 = task_info_outCnt
    };

    uint64_t ret =
        [self.remoteCall doRemoteCallStableWithTimeout:5
                                          functionName:(char *)"task_info"
                                       functionPointer:(void *)task_info_addr
                                                  args:args
                                              argCount:4];

    if (ret != KERN_SUCCESS) {
        return 0;
    }

    uint64_t all_image_info_addr = 0;
    if (![self.remoteCall remoteRead:(scratch_addr + 8)
                                  to:&all_image_info_addr
                                size:sizeof(all_image_info_addr)] ||
        !validOffsetPtr(all_image_info_addr)) {
        return 0;
    }

    uint32_t infoArrayCount = 0;
    uint64_t infoArray = 0;
    BOOL readCount = [self.remoteCall remoteRead:(all_image_info_addr + 4)
                                              to:&infoArrayCount
                                            size:sizeof(infoArrayCount)];
    BOOL readArray = [self.remoteCall remoteRead:(all_image_info_addr + 8)
                                              to:&infoArray
                                            size:sizeof(infoArray)];

    static const uint32_t kMaxDyldImageCount = 3000;
    if (!readCount || !readArray || infoArrayCount == 0 ||
        infoArrayCount > kMaxDyldImageCount || !validOffsetPtr(infoArray)) {
        return 0;
    }

    static const uint64_t kDyldImageInfoSize = 0x18;
    uint64_t freeFireMainBinary = 0;

    for (uint32_t remaining = infoArrayCount; remaining > 0; --remaining) {
        uint32_t i = remaining - 1;
        if ((uint64_t)i > (UINT64_MAX - infoArray) / kDyldImageInfoSize) {
            break;
        }

        uint64_t entry = infoArray + (uint64_t)i * kDyldImageInfoSize;
        if (!validOffsetPtr(entry) || !validOffsetPtr(entry + 8))
            continue;

        uint64_t imageFilePathAddr = 0;
        uint64_t imageLoadAddress = 0;
        BOOL readLoadAddress =
            [self.remoteCall remoteRead:entry
                                     to:&imageLoadAddress
                                   size:sizeof(imageLoadAddress)];
        BOOL readPathAddress =
            [self.remoteCall remoteRead:(entry + 8)
                                     to:&imageFilePathAddr
                                   size:sizeof(imageFilePathAddr)];
        if (!readLoadAddress || !readPathAddress ||
            !validOffsetPtr(imageFilePathAddr))
            continue;

        char pathBuf[512] = {0};
        if (![self.remoteCall remoteRead:imageFilePathAddr
                                      to:pathBuf
                                    size:sizeof(pathBuf) - 1])
            continue;

        if (strstr(pathBuf, "UnityFramework")) {
            self.binaryBaseSource = @"UnityFramework";
            return imageLoadAddress;
        }

        if ((strcasestr(pathBuf, "freefire") || strstr(pathBuf, "FreeFire")) &&
            freeFireMainBinary == 0) {
            freeFireMainBinary = imageLoadAddress;
            self.binaryBaseSource = [NSString stringWithUTF8String:pathBuf];
        }
    }

    if (freeFireMainBinary != 0) {
        return freeFireMainBinary;
    }

    // Fallback: Image 0
    uint64_t firstImage = 0;
    if ([self.remoteCall remoteRead:infoArray
                                 to:&firstImage
                               size:sizeof(firstImage)] &&
        validOffsetPtr(firstImage)) {
        return firstImage;
    }

    return 0;
}

- (uintptr_t)resolveGameFacadeStaticFields:(RemoteCall *)remoteCall {
    if (self.staticFieldsAddress != 0) {
        return self.staticFieldsAddress;
    }

    // Failed attempts retry at most once per second; reportStage de-dups the
    // stage line so the log stays quiet between retries.
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (self.lastStaticResolveAttempt != 0 &&
        now - self.lastStaticResolveAttempt < 1.0) {
        return 0;
    }
    self.lastStaticResolveAttempt = now;

    uintptr_t candidates[kMaxStaticCandidates];
    int candidateCount = 0;

    // Strategy 1: Il2Cpp MethodInfo RVAs from the dump.
    const uint64_t methodInfoOffsets[] = {
        kMethodInfo_GameFacade_CCtor,
        kMethodInfo_GameFacade_CurrentLocalPlayer,
        kMethodInfo_GameFacade_SetCurrentGame
    };

    for (int i = 0; i < 3; ++i) {
        uintptr_t methodInfo = self.binaryBase + methodInfoOffsets[i];
        uintptr_t klass = ReadMemorySafe<uintptr_t>(
            remoteCall, methodInfo + kMethodInfo_Klass);
        if (validOffsetPtr(klass))
            PushCandidate(candidates, &candidateCount, kMaxStaticCandidates,
                          klass);
    }

    // Strategy 2: Collect ADRP/LDR/ADD static candidates across GameFacade methods & getters
    const uint64_t accessorRVAs[] = {
        kGameFacade_GetGameServerPort,
        kGameFacade_GetGameServerAddr,
        kGameFacade_GetIsCameraMode,
        kGameFacade_CCtor,
        kGameFacade_CurrentLocalPlayer,
        kGameFacade_SetCurrentGame,
        kGameFacade_CurrentLocalPlayerID,
        kGameFacade_GetLocalPlayerOrObServer,
        kGameFacade_IsLocalTeammate
    };
    const int accessorCount = (int)(sizeof(accessorRVAs) / sizeof(accessorRVAs[0]));

    for (int i = 0; i < accessorCount; ++i) {
        uintptr_t found[16] = {0};
        int foundCount = CollectArm64StaticCandidates(
            remoteCall, self.binaryBase + accessorRVAs[i], found, 16);
        for (int j = 0; j < foundCount; ++j) {
            PushCandidate(candidates, &candidateCount, kMaxStaticCandidates,
                          found[j]);
        }
    }

    if (candidateCount == 0) {
        [self reportStatus:@"static fields unverified: no candidates decoded"];
        return 0;
    }

    uintptr_t staticFields = 0;
    uint64_t matchGameOffset = 0;
    uintptr_t matchGame = 0;

    for (int i = 0; i < candidateCount && staticFields == 0; ++i) {
        uintptr_t candidate = candidates[i];

        // 1. Is candidate the Il2CppClass* for GameFacade?
        staticFields = TryResolveGameFacadeFromKlass(remoteCall, candidate);
        if (staticFields != 0) break;

        // 2. Is *candidate the Il2CppClass* for GameFacade?
        uintptr_t deref1 = ReadMemorySafe<uintptr_t>(remoteCall, candidate);
        if (validOffsetPtr(deref1)) {
            staticFields = TryResolveGameFacadeFromKlass(remoteCall, deref1);
            if (staticFields != 0) break;

            // 3. Is **candidate the Il2CppClass* for GameFacade?
            uintptr_t deref2 = ReadMemorySafe<uintptr_t>(remoteCall, deref1);
            if (validOffsetPtr(deref2)) {
                staticFields = TryResolveGameFacadeFromKlass(remoteCall, deref2);
                if (staticFields != 0) break;
            }
        }

        // 4. Is candidate directly the static_fields block?
        if (LooksLikeGameFacadeStaticBlock(remoteCall, candidate) &&
            FreeFireStaticBlockHasGameSlot(remoteCall, candidate)) {
            staticFields = candidate;
            break;
        }

        // 5. Is *candidate the static_fields block?
        if (validOffsetPtr(deref1) &&
            LooksLikeGameFacadeStaticBlock(remoteCall, deref1) &&
            FreeFireStaticBlockHasGameSlot(remoteCall, deref1)) {
            staticFields = deref1;
            break;
        }
    }

    if (staticFields == 0) {
        NSMutableString *diag = [NSMutableString stringWithFormat:@"cands=%d: ", candidateCount];
        for (int i = 0; i < std::min(candidateCount, 8); ++i) {
            uintptr_t c = candidates[i];
            uintptr_t d = ReadMemorySafe<uintptr_t>(remoteCall, c);
            [diag appendFormat:@"c%d=0x%lx(val=0x%lx) ", i, (unsigned long)c, (unsigned long)d];
        }
        [self reportStatus:[NSString stringWithFormat:@"static fields unverified: %@", diag]];
        return 0;
    }

    // MatchGame lives in one of the dump slots (0x08 / 0x00); fall back to
    // scanning the whole block, which starts at 0x00 (no object header).
    matchGameOffset = gFreeFireMatchGameFieldOffset != 0
                          ? gFreeFireMatchGameFieldOffset
                          : kGameFacadeStatic_CurrentGame;
    const uint64_t dumpSlots[] = {
        kGameFacadeStatic_CurrentGame,       // 0x00 (Fl0rk reference path)
        kGameFacadeStatic_CurrentMatchGame   // 0x08
    };
    for (int s = 0; s < 2 && matchGame == 0; ++s) {
        uintptr_t value =
            ReadMemorySafe<uintptr_t>(remoteCall, staticFields + dumpSlots[s]);
        if (!FieldHoldsMatchGame(remoteCall, value))
            continue;
        matchGameOffset = dumpSlots[s];
        matchGame = value;
    }

    if (matchGame == 0) {
        uint64_t discovered = FindIl2CppFieldMatchingFrom(
            remoteCall, staticFields, 0x0, 0x100, FieldHoldsMatchGame);
        if (discovered != 0) {
            matchGameOffset = discovered;
            matchGame =
                ReadMemorySafe<uintptr_t>(remoteCall, staticFields + discovered);
        }
    }

    if (matchGame == 0) {
        uintptr_t cg = ReadMemorySafe<uintptr_t>(remoteCall, staticFields + kGameFacadeStatic_CurrentGame);
        if (validOffsetPtr(cg)) {
            matchGame = cg;
            matchGameOffset = kGameFacadeStatic_CurrentGame;
        } else {
            matchGame = ReadMemorySafe<uintptr_t>(remoteCall, staticFields + matchGameOffset);
        }
    }

    gFreeFireMatchGameFieldOffset = matchGameOffset;
    self.staticFieldsAddress = staticFields;

    LOG(@"[FreeFire] GameFacade static fields: 0x%lx "
        @"matchGameField=0x%llx matchGame=0x%lx",
        (unsigned long)staticFields,
        (unsigned long long)matchGameOffset, (unsigned long)matchGame);

    [self
        reportDiagnostics:
            [NSString
                stringWithFormat:@"GameFacade staticFields=0x%lx "
                                 @"matchGameField=0x%llx matchGame=0x%lx%@",
                                 (unsigned long)staticFields,
                                 (unsigned long long)matchGameOffset,
                                 (unsigned long)matchGame,
                                 @" (verified)"]];

    return staticFields;
}

- (void)showOverlay:(RemoteCall *)remoteCall {
    if (!self.remoteWebViewOverlay.isOverlayReady ||
        !self.remoteWebViewOverlay) {
        return;
    }

    NSMutableArray<NSDictionary *> *overlayTargets = [NSMutableArray array];

    for (FreeFireEntitySnapshot *entity in self.entitySnapshots) {
        BOOL hasBox = self.showsBox && entity.boxW > 0.0 && entity.boxH > 0.0;

        NSMutableDictionary *target = [NSMutableDictionary dictionary];
        target[@"id"] = @(entity.actorAddress);
        target[@"name"] = entity.name ?: @"";
        target[@"sx"] = @(entity.screenX);
        target[@"sy"] = @(entity.screenY);
        target[@"headX"] = @(entity.headX);
        target[@"headY"] = @(entity.headY);
        target[@"footX"] = @(entity.footX);
        target[@"footY"] = @(entity.footY);
        target[@"distance"] = @(entity.distance);
        target[@"visible"] = @(entity.visible);
        target[@"onScreen"] = @(entity.onScreen);
        target[@"drawLine"] = @(self.showsLine);
        target[@"drawHealth"] = @(self.showsHealth);
        target[@"drawName"] = @(self.showsName);
        target[@"drawDistance"] = @(self.showsDistance);
        target[@"hasBox"] = @(hasBox);
        target[@"boxX"] = @(entity.boxX);
        target[@"boxY"] = @(entity.boxY);
        target[@"boxW"] = @(entity.boxW);
        target[@"boxH"] = @(entity.boxH);
        target[@"hp"] = @(entity.health);
        target[@"maxHp"] = @(entity.maxHealth);

        [overlayTargets addObject:target];
    }

    [self.remoteWebViewOverlay updateOverlayTargets:overlayTargets];
}

// Resolves the camera controller manager and its main camera (100% PURE MEMORY READS).
- (BOOL)resolveCamera:(RemoteCall *)remoteCall
            matchGame:(uintptr_t)currentMatchGame
         ctxMatchGame:(uintptr_t)ctxMatchGame
               camera:(uintptr_t *)outCamera
               camMgr:(uintptr_t *)outCamMgr {
    if (!remoteCall || (!validOffsetPtr(currentMatchGame) && !validOffsetPtr(ctxMatchGame)))
        return NO;

    currentMatchGame = CleanPointer(currentMatchGame);
    ctxMatchGame = CleanPointer(ctxMatchGame);

    // Strategy 0: Test cached camera if still valid and confirmed to hold Camera
    if (validOffsetPtr(self.cachedCamera) && checkPointer64bits(self.cachedCamera)) {
        float testVP[16] = {}, testView[16] = {};
        if (ReadCameraVPAndWorldMatrix(remoteCall, self.cachedCamera, testVP, testView)) {
            if (outCamera) *outCamera = self.cachedCamera;
            if (outCamMgr) *outCamMgr = self.cachedCamMgr;
            return YES;
        } else {
            self.cachedCamera = 0;
            self.cachedCamMgr = 0;
        }
    } else {
        self.cachedCamera = 0;
        self.cachedCamMgr = 0;
    }

    uintptr_t camera = 0;
    uintptr_t camMgr = 0;

    auto testCandidateCamera = [&](uintptr_t candCam, uintptr_t mgr) -> bool {
        candCam = CleanPointer(candCam);
        if (!validOffsetPtr(candCam) || !checkPointer64bits(candCam)) return false;
        float testVP[16] = {}, testView[16] = {};
        if (!ReadCameraVPAndWorldMatrix(remoteCall, candCam, testVP, testView)) return false;
        camera = candCam;
        camMgr = mgr;
        return true;
    };

    auto checkManager = [&](uintptr_t mgr) -> bool {
        mgr = CleanPointer(mgr);
        if (!validOffsetPtr(mgr) || !checkPointer64bits(mgr)) return false;

        // 1. Try Fl0rk cameraMain at 0x18 first
        uintptr_t c0 = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, mgr + kCameraControllerManager_CameraMain));
        if (testCandidateCamera(c0, mgr)) return true;

        // 2. Try primary camera at 0x20 (EKIPKGNKILM)
        uintptr_t c1 = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, mgr + kCameraControllerManager_MainCamera));
        if (testCandidateCamera(c1, mgr)) return true;

        // 3. Try secondary camera at 0x28 (LBHAFMEPGCO)
        uintptr_t c2 = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, mgr + kCameraControllerManager_SubCamera));
        if (testCandidateCamera(c2, mgr)) return true;

        // Scan other candidate offsets in mgr (throttled)
        for (uint64_t off = 0x10; off <= 0x50; off += sizeof(uintptr_t)) {
            if (off == kCameraControllerManager_CameraMain ||
                off == kCameraControllerManager_MainCamera ||
                off == kCameraControllerManager_SubCamera) continue;
            uintptr_t c = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, mgr + off));
            if (validOffsetPtr(c) && testCandidateCamera(c, mgr)) return true;
        }
        return false;
    };

    // Strategy 1: Check CameraControllerManager at 0xD8 (Fl0rk reference path)
    // Prioritize ctxMatchGame (the active match/training game), then currentMatchGame
    for (uintptr_t g : { ctxMatchGame, currentMatchGame }) {
        if (!validOffsetPtr(g) || !checkPointer64bits(g)) continue;
        uintptr_t mgr = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, g + kMatchGame_CameraControllerManager));
        if (validOffsetPtr(mgr)) {
            if (checkManager(mgr)) goto found;
            if (testCandidateCamera(mgr, g)) goto found;
        }
    }

    // Strategy 2: Check BaseGameContext inside currentMatchGame for subGame -> CameraControllerManager (0xD8)
    if (validOffsetPtr(currentMatchGame) && checkPointer64bits(currentMatchGame)) {
        uintptr_t gameContext = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, currentMatchGame + kBaseGame_GameContext));
        if (validOffsetPtr(gameContext) && checkPointer64bits(gameContext)) {
            const uint64_t ctxOffsets[] = { 0x30, 0x20, 0x28, 0x18, 0x38 };
            for (uint64_t off : ctxOffsets) {
                uintptr_t subGame = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, gameContext + off));
                if (validOffsetPtr(subGame) && checkPointer64bits(subGame)) {
                    uintptr_t mgr = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, subGame + kMatchGame_CameraControllerManager));
                    if (validOffsetPtr(mgr) && checkManager(mgr)) goto found;
                }
            }
        }
    }

    // Strategy 3: Fast scan around 0xD8 (0x80 to 0x140) ONLY if 0xD8 was not found
    for (uintptr_t g : { ctxMatchGame, currentMatchGame }) {
        if (!validOffsetPtr(g) || !checkPointer64bits(g)) continue;
        for (uint64_t off = 0x80; off <= 0x140; off += sizeof(uintptr_t)) {
            if (off == kMatchGame_CameraControllerManager) continue;
            uintptr_t candMgr = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, g + off));
            if (validOffsetPtr(candMgr) && LooksLikeCameraManager(remoteCall, candMgr)) {
                if (checkManager(candMgr)) goto found;
                if (testCandidateCamera(candMgr, g)) goto found;
            }
        }
    }

    // Strategy 4: FrontEndGame.postEffect (Social Island / Lobby / Training Ground)
    if (validOffsetPtr(currentMatchGame)) {
        uintptr_t postEffect = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, currentMatchGame + kFrontEndGame_PostEffect));
        if (validOffsetPtr(postEffect) && checkPointer64bits(postEffect)) {
            uintptr_t ownerCam = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, postEffect + kPostEffectManager_OwnerCamera));
            if (testCandidateCamera(ownerCam, 0)) goto found;

            uintptr_t extraCams = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, postEffect + kPostEffectManager_ExtraCameras));
            if (validOffsetPtr(extraCams) && checkPointer64bits(extraCams)) {
                uintptr_t items = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, extraCams + 0x10));
                int32_t count = ReadMemorySafe<int32_t>(remoteCall, extraCams + 0x18);
                if (validOffsetPtr(items) && count > 0 && count < 20) {
                    for (int i = 0; i < count; ++i) {
                        uintptr_t ec = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, items + 0x20 + (uint64_t)i * sizeof(uintptr_t)));
                        if (testCandidateCamera(ec, 0)) goto found;
                    }
                }
            }
        }
    }

    // Strategy 5: UIScene cameras
    if (validOffsetPtr(currentMatchGame)) {
        uintptr_t uiScene = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, currentMatchGame + kBaseGame_UIScene));
        if (validOffsetPtr(uiScene) && checkPointer64bits(uiScene)) {
            const uint64_t sceneCamOffsets[] = {
                kUIFrontEndScene_UI3DCamera, // 0x170
                kUIFrontEndScene_BgCamera,   // 0x178
                0x450,                       // m_CameraEntryCtrl
                0x458,                       // m_CameraInGameCtrl
                0x1080                       // CameraHeightCtrl
            };
            for (uint64_t off : sceneCamOffsets) {
                uintptr_t cand = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, uiScene + off));
                if (testCandidateCamera(cand, 0)) goto found;
            }

            uintptr_t gyro = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, uiScene + kUIFrontEndScene_LobbyCamGyro));
            if (validOffsetPtr(gyro) && checkPointer64bits(gyro)) {
                uintptr_t c1 = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, gyro + 0x20));
                uintptr_t c2 = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, gyro + 0x28));
                if (testCandidateCamera(c1, 0)) goto found;
                if (testCandidateCamera(c2, 0)) goto found;
            }
        }
    }

    // Strategy 6: Dynamic scan for any Camera object in currentMatchGame / ctxMatchGame
    for (uintptr_t g : { currentMatchGame, ctxMatchGame }) {
        if (!validOffsetPtr(g) || !checkPointer64bits(g)) continue;
        for (uint64_t off = 0x10; off <= 0x200; off += sizeof(uintptr_t)) {
            uintptr_t ptr = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, g + off));
            if (validOffsetPtr(ptr) && checkPointer64bits(ptr)) {
                if (testCandidateCamera(ptr, 0)) goto found;
                if (LooksLikeCameraManager(remoteCall, ptr)) {
                    if (checkManager(ptr)) goto found;
                }
            }
        }
    }

    // Strategy 7: UICamera static fields via MethodInfo
    if ([self discoveryDue]) {
        uintptr_t methodInfo = self.binaryBase + kMethodInfo_UICamera_CCtor;
        uintptr_t klass = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, methodInfo + kMethodInfo_Klass));
        if (validOffsetPtr(klass) && checkPointer64bits(klass)) {
            uintptr_t sf = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, klass + kIl2CppClass_StaticFields));
            if (validOffsetPtr(sf) && checkPointer64bits(sf)) {
                uintptr_t curCam = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, sf + kUICameraStatic_CurrentCamera));
                if (testCandidateCamera(curCam, 0)) goto found;
                uintptr_t uic = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, sf + kUICameraStatic_Current));
                if (validOffsetPtr(uic) && checkPointer64bits(uic)) {
                    uintptr_t mCam = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, uic + kUICamera_mCam));
                    if (testCandidateCamera(mCam, 0)) goto found;
                }
            }
        }
    }

found:
    if (!validOffsetPtr(camera))
        return NO;

    self.cachedCamera = camera;
    self.cachedCamMgr = camMgr;

    LOG(@"[FreeFire] Discovered camera: 0x%lx (camMgr=0x%lx)",
        (unsigned long)camera, (unsigned long)camMgr);

    if (outCamera)
        *outCamera = camera;
    if (outCamMgr)
        *outCamMgr = camMgr;
    return YES;
}
- (FreeFireEntityContainer)resolveEntityContainer:(RemoteCall *)remoteCall
                                        matchGame:(uintptr_t)currentMatchGame
                                     ctxMatchGame:(uintptr_t)ctxMatchGame {
    FreeFireEntityContainer emptyContainer{};
    if (!remoteCall || (!validOffsetPtr(currentMatchGame) && !validOffsetPtr(ctxMatchGame)))
        return emptyContainer;

    currentMatchGame = CleanPointer(currentMatchGame);
    ctxMatchGame = CleanPointer(ctxMatchGame);

    // 0. Test cached container if still valid and holds confirmed entities
    if (validOffsetPtr(self.cachedContainerAddress)) {
        FreeFireEntityContainer cachedInfo{};
        if (InspectEntityContainer(remoteCall, self.cachedContainerAddress, &cachedInfo)) {
            if (cachedInfo.count > 0 && cachedInfo.count <= 10000) {
                int checkLimit = (cachedInfo.containerType == kContainerType_Dictionary)
                                     ? std::min(cachedInfo.capacity, 4)
                                     : std::min(cachedInfo.count, 4);
                bool confirmed = false;
                for (int i = 0; i < checkLimit; ++i) {
                    uintptr_t testEnt = GetEntityFromContainer(remoteCall, cachedInfo, i);
                    if (validOffsetPtr(testEnt) && IsLikelyPlayerOrTarget(remoteCall, testEnt, nullptr, 0, true)) {
                        confirmed = true;
                        break;
                    }
                }
                if (confirmed) {
                    return cachedInfo;
                }
            }
        }
        self.cachedContainerAddress = 0;
    }

    if (!validOffsetPtr(ctxMatchGame) && validOffsetPtr(currentMatchGame)) {
        uintptr_t gameCtx = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, currentMatchGame + kBaseGame_GameContext));
        if (validOffsetPtr(gameCtx)) {
            ctxMatchGame = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, gameCtx + kBaseGameContext_MatchGame));
            if (!validOffsetPtr(ctxMatchGame)) {
                uintptr_t cand20 = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, gameCtx + 0x20));
                if (validOffsetPtr(cand20)) ctxMatchGame = cand20;
            }
        }
    }

    FreeFireEntityContainer firstValidContainer{};
    FreeFireEntityContainer largestContainer{};
    int largestCount = -1;

    auto testCandidate = [&](uintptr_t cand, bool isDedicated) -> FreeFireEntityContainer {
        cand = CleanPointer(cand);
        if (!validOffsetPtr(cand)) return emptyContainer;

        FreeFireEntityContainer info{};
        if (!InspectEntityContainer(remoteCall, cand, &info))
            return emptyContainer;

        if (info.count > 0 && firstValidContainer.container == 0)
            firstValidContainer = info;
        if (info.count > 0 && info.count <= 10000 && info.count > largestCount) {
            largestCount = info.count;
            largestContainer = info;
        }

        if (info.count <= 0 || info.count > 10000)
            return emptyContainer;

        int checkLimit = (info.containerType == kContainerType_Dictionary)
                             ? std::min(info.capacity, 12)
                             : std::min(info.count, 6);
        for (int i = 0; i < checkLimit; ++i) {
            uintptr_t entity = GetEntityFromContainer(remoteCall, info, i);
            if (!validOffsetPtr(entity)) continue;
            if (IsLikelyPlayerOrTarget(remoteCall, entity, nullptr, 0, isDedicated)) {
                self.cachedContainerAddress = cand;
                return info;
            }
        }
        return emptyContainer;
    };

    // Priority 1: Direct Fl0rk container match (0x90) -> 0xC8 -> 0x28 (and 0xC8)
    for (uintptr_t g : { ctxMatchGame, currentMatchGame }) {
        if (!validOffsetPtr(g)) continue;
        uintptr_t matchObj = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, g + kMatchGame_Match));
        if (validOffsetPtr(matchObj)) {
            uintptr_t florkC8 = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, matchObj + kMatch_C8));
            if (validOffsetPtr(florkC8)) {
                uintptr_t florkArr = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, florkC8 + kMatch_C8_Array));
                FreeFireEntityContainer res = testCandidate(florkArr, true);
                if (res.container != 0) return res;

                res = testCandidate(florkC8, true);
                if (res.container != 0) return res;
            }
        }
    }

    // Priority 2: Training target list 0x478
    for (uintptr_t g : { ctxMatchGame, currentMatchGame }) {
        if (!validOffsetPtr(g)) continue;
        uintptr_t t478 = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, g + kTraining_HumanTargetList));
        if (validOffsetPtr(t478)) {
            FreeFireEntityContainer res = testCandidate(t478, true);
            if (res.container != 0) return res;
        }
    }

    // Priority 3: sAllEntities (0x08 on BaseGame static fields)
    if (!validOffsetPtr(self.baseGameStaticFieldsAddress)) {
        for (uintptr_t g : { ctxMatchGame, currentMatchGame }) {
            if (!validOffsetPtr(g)) continue;
            uintptr_t sf = ResolveBaseGameStaticFields(remoteCall, g);
            if (validOffsetPtr(sf)) {
                self.baseGameStaticFieldsAddress = sf;
                break;
            }
        }
    }
    if (validOffsetPtr(self.baseGameStaticFieldsAddress)) {
        uintptr_t allEnt = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, self.baseGameStaticFieldsAddress + kBaseGameStatic_sAllEntities));
        FreeFireEntityContainer res = testCandidate(allEnt, false);
        if (res.container != 0) return res;

        uintptr_t tickedEnt = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, self.baseGameStaticFieldsAddress + kBaseGameStatic_sTickedEntities));
        res = testCandidate(tickedEnt, false);
        if (res.container != 0) return res;

        uintptr_t allLEnt = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, self.baseGameStaticFieldsAddress + kBaseGameStatic_sAllLEntities));
        res = testCandidate(allLEnt, false);
        if (res.container != 0) return res;
    }

    // Priority 4: Other training target queues / lists
    for (uintptr_t g : { ctxMatchGame, currentMatchGame }) {
        if (!validOffsetPtr(g)) continue;
        const uint64_t trainingOffsets[] = {
            kTraining_HumanTargetQueue1,          // 0x468
            kTraining_HumanTargetQueue2,          // 0x470
            kTraining_MovableShootingTargetList,  // 0x4B8
            kTraining_AltHumanTargetList,         // 0x288
            0x448, 0x450, 0x490, 0x4C8, 0x4D0, 0x4F0
        };
        for (uint64_t off : trainingOffsets) {
            uintptr_t cand = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, g + off));
            FreeFireEntityContainer res = testCandidate(cand, true);
            if (res.container != 0) return res;
        }
    }

    // Priority 5: MatchGame replication entities & match player containers
    for (uintptr_t g : { ctxMatchGame, currentMatchGame }) {
        if (!validOffsetPtr(g)) continue;
        uintptr_t rep = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, g + kMatchGame_ReplicationEntities));
        FreeFireEntityContainer res = testCandidate(rep, false);
        if (res.container != 0) return res;

        uintptr_t lrep = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, g + kMatchGame_LReplicationEntities));
        res = testCandidate(lrep, false);
        if (res.container != 0) return res;

        uintptr_t matchObj = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, g + kMatchGame_Match));
        if (validOffsetPtr(matchObj)) {
            const uint64_t matchOffsets[] = {
                kMatch_Players1, kMatch_Players2, kMatch_Players3, kMatch_Players4, kMatch_Players5,
                kMatch_PlayerList1, kMatch_PlayerList2, kMatch_AIPawns, kMatch_Teams, kMatch_Vehicles, kMatch_Containers,
                0x570, 0x5D8, 0x5E0
            };
            for (uint64_t off : matchOffsets) {
                uintptr_t cand = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, matchObj + off));
                res = testCandidate(cand, false);
                if (res.container != 0) return res;
            }
        }
    }

    // MethodInfo BaseGame CCtor fallback
    if (!validOffsetPtr(self.baseGameStaticFieldsAddress)) {
        uintptr_t bgMethodAddr = self.binaryBase + kMethodInfo_BaseGame_CCtor;
        uintptr_t bgMethodDeref = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, bgMethodAddr));
        const uintptr_t methodCandidates[2] = { bgMethodDeref, bgMethodAddr };
        for (int m = 0; m < 2; ++m) {
            uintptr_t mPtr = methodCandidates[m];
            if (!validOffsetPtr(mPtr)) continue;
            uintptr_t bgKlass = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, mPtr + kMethodInfo_Klass)) & ~7ULL;
            if (validOffsetPtr(bgKlass)) {
                uintptr_t bgStatics = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, bgKlass + kIl2CppClass_StaticFields));
                if (validOffsetPtr(bgStatics)) {
                    self.baseGameStaticFieldsAddress = bgStatics;
                    FreeFireEntityContainer res = testCandidate(CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, bgStatics + kBaseGameStatic_sAllEntities)), false);
                    if (res.container != 0) return res;
                    break;
                }
            }
        }
    }

    // ARM64 instruction analysis fallback (throttled to discoveryDue to avoid choking loop)
    if (!validOffsetPtr(self.baseGameStaticFieldsAddress) && [self discoveryDue]) {
        self.baseGameStaticFieldsAddress = ResolveBaseGameStaticFieldsFromARM64(remoteCall, self.binaryBase);
        if (validOffsetPtr(self.baseGameStaticFieldsAddress)) {
            LOG(@"[FreeFire] Discovered BaseGame static fields via ARM64: 0x%lx",
                (unsigned long)self.baseGameStaticFieldsAddress);
            FreeFireEntityContainer res = testCandidate(CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, self.baseGameStaticFieldsAddress + kBaseGameStatic_sAllEntities)), false);
            if (res.container != 0) return res;
        }
    }

    // Dynamic scan fallback: ONLY when discoveryDue
    if ([self discoveryDue]) {
        for (uintptr_t g : { ctxMatchGame, currentMatchGame }) {
            if (!validOffsetPtr(g)) continue;
            for (uint64_t off = 0x10; off <= 0x600; off += sizeof(uintptr_t)) {
                uintptr_t cand = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, g + off));
                FreeFireEntityContainer res = testCandidate(cand, false);
                if (res.container != 0) return res;
            }
            uintptr_t matchObj = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, g + kMatchGame_Match));
            if (validOffsetPtr(matchObj)) {
                for (uint64_t off = 0x10; off <= 0x300; off += sizeof(uintptr_t)) {
                    uintptr_t cand = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, matchObj + off));
                    FreeFireEntityContainer res = testCandidate(cand, false);
                    if (res.container != 0) return res;
                }
            }
        }
    }

    if (largestContainer.container != 0 && largestCount > 0) {
        self.cachedContainerAddress = largestContainer.container;
        return largestContainer;
    }

    if (firstValidContainer.container != 0 && firstValidContainer.count > 0) {
        self.cachedContainerAddress = firstValidContainer.container;
        return firstValidContainer;
    }

    return emptyContainer;
}

- (void)updateSnapshot:(RemoteCall *)remoteCall {
    if (!remoteCall || self.binaryBase == 0) {
        @synchronized(self) {
            self.hasValidFrame = NO;
        }
        return;
    }

    // 1. Resolve GameFacade static fields
    uintptr_t staticFields = [self resolveGameFacadeStaticFields:remoteCall];
    if (!validOffsetPtr(staticFields)) {
        [self reportStage:@"stage 1/6: GameFacade static fields not resolved"];
        @synchronized(self) {
            self.hasValidFrame = NO;
        }
        return;
    }

    // 2. Read MatchGame Context
    // In match (BR / CS), CurrentMatchGame sits at static field 0x8.
    // In Training Mode or custom rooms, the game instance sits at CurrentGame (0x0).
    uint64_t matchGameOffset = 0;
    uintptr_t currentMatchGame = 0;

    uintptr_t mg = ReadMemorySafe<uintptr_t>(
        remoteCall, staticFields + kGameFacadeStatic_CurrentMatchGame);
    uintptr_t cg = ReadMemorySafe<uintptr_t>(
        remoteCall, staticFields + kGameFacadeStatic_CurrentGame);

    if (validOffsetPtr(mg)) {
        // In Free Fire, CurrentMatchGame (+0x08) is ONLY non-zero when inside a match (BR/CS).
        // It must always take top priority over CurrentGame (Lobby/FrontEndGame).
        currentMatchGame = mg;
        matchGameOffset = kGameFacadeStatic_CurrentMatchGame;
    } else if (validOffsetPtr(cg)) {
        // Training Mode / Social Area / Custom Mode / Lobby
        currentMatchGame = cg;
        matchGameOffset = kGameFacadeStatic_CurrentGame;
    }

    // Check previously discovered offset
    if (!validOffsetPtr(currentMatchGame) &&
        gFreeFireMatchGameFieldOffset != 0 &&
        gFreeFireMatchGameFieldOffset != kGameFacadeStatic_CurrentMatchGame &&
        gFreeFireMatchGameFieldOffset != kGameFacadeStatic_CurrentGame) {
        uintptr_t discVal = ReadMemorySafe<uintptr_t>(
            remoteCall, staticFields + gFreeFireMatchGameFieldOffset);
        if (FieldHoldsMatchGame(remoteCall, discVal) || FieldHoldsAnyGame(remoteCall, discVal)) {
            currentMatchGame = discVal;
            matchGameOffset = gFreeFireMatchGameFieldOffset;
        }
    }

    // Dynamic scan across staticFields if still not found
    if (!validOffsetPtr(currentMatchGame) && [self discoveryDue]) {
        uint64_t discovered = FindIl2CppFieldMatchingFrom(
            remoteCall, staticFields, 0x0, 0x300, FieldHoldsMatchGame);
        if (discovered == 0) {
            discovered = FindIl2CppFieldMatchingFrom(
                remoteCall, staticFields, 0x0, 0x300, FieldHoldsAnyGame);
        }
        if (discovered != 0) {
            matchGameOffset = discovered;
            gFreeFireMatchGameFieldOffset = discovered;
            currentMatchGame = ReadMemorySafe<uintptr_t>(
                remoteCall, staticFields + discovered);
        }
    }

    // Fallback: If CurrentGame holds an entity dictionary even if class name is unrecognized
    if (!validOffsetPtr(currentMatchGame)) {
        uintptr_t currentGame = ReadMemorySafe<uintptr_t>(
            remoteCall, staticFields + kGameFacadeStatic_CurrentGame);
        if (validOffsetPtr(currentGame)) {
            uintptr_t repDict = ReadMemorySafe<uintptr_t>(
                remoteCall, currentGame + kMatchGame_ReplicationEntities);
            if (validOffsetPtr(repDict) && IsDictionaryObject(remoteCall, repDict)) {
                currentMatchGame = currentGame;
                matchGameOffset = kGameFacadeStatic_CurrentGame;
            } else {
                uintptr_t baseStatics = ResolveBaseGameStaticFields(remoteCall, currentGame);
                if (validOffsetPtr(baseStatics)) {
                    currentMatchGame = currentGame;
                    matchGameOffset = kGameFacadeStatic_CurrentGame;
                }
            }
        }
    }

    char matchGameClass[64] = {0};
    if (validOffsetPtr(currentMatchGame) && [self diagnosticsDue]) {
        ReadIl2CppClassName(remoteCall, currentMatchGame, matchGameClass,
                            sizeof(matchGameClass));
        if (matchGameClass[0] == '\0') {
            uintptr_t rawKlass = ReadMemorySafe<uintptr_t>(remoteCall, currentMatchGame);
            uintptr_t cleanKlass = CleanPointer(rawKlass) & ~7ULL;
            uintptr_t nameAtKlass = 0;
            if (validOffsetPtr(cleanKlass)) {
                nameAtKlass = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, cleanKlass + 0x10));
            }
            char debugName[32] = {0};
            if (validOffsetPtr(nameAtKlass)) {
                [remoteCall remoteRead:nameAtKlass to:debugName size:sizeof(debugName) - 1];
            }
            snprintf(matchGameClass, sizeof(matchGameClass),
                     "?k=0x%lx,n='%s'",
                     (unsigned long)cleanKlass,
                     debugName);
        }
    }

    if (!validOffsetPtr(currentMatchGame)) {
        if (self.lastMatchGame != 0 || self.lastCtxMatchGame != 0) {
            LOG(@"[FreeFire] MatchGame became null; invalidating camera & container cache");
            self.cachedCamera = 0;
            self.cachedCamMgr = 0;
            self.cachedContainerAddress = 0;
            self.baseGameStaticFieldsAddress = 0;
            self.lastMatchGame = 0;
            self.lastCtxMatchGame = 0;
        }
        if ([self diagnosticsDue]) {
            [self reportStage:[NSString stringWithFormat:@"stage 2/6: no game (cg=0x%lx, mg=0x%lx)",
                                                         (unsigned long)cg, (unsigned long)mg]];
        }
        @synchronized(self) {
            self.hasValidFrame = NO;
            [self clearOverlayTargets];
        }
        return;
    }

    // Invalidate cached camera and container whenever currentMatchGame changes (e.g. Lobby -> Training Ground)
    if (currentMatchGame != self.lastMatchGame) {
        LOG(@"[FreeFire] MatchGame changed from 0x%lx to 0x%lx; invalidating camera & container cache",
            (unsigned long)self.lastMatchGame, (unsigned long)currentMatchGame);
        self.cachedCamera = 0;
        self.cachedCamMgr = 0;
        self.cachedContainerAddress = 0;
        self.baseGameStaticFieldsAddress = 0;
        self.lastMatchGame = currentMatchGame;
    }

    // 3. Resolve ctxMatchGame from BaseGameContext (e.g. Training Ground MatchGame)
    uintptr_t gameContext = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, currentMatchGame + kBaseGame_GameContext));
    uintptr_t ctxMatchGame = 0;
    if (validOffsetPtr(gameContext) && checkPointer64bits(gameContext)) {
        // BaseGameContext (IFFGGKDPHBG): offset 0x30 is KMLICIEHMHC (subclass of MatchGame)
        uintptr_t cand30 = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, gameContext + 0x30));
        if (validOffsetPtr(cand30) && checkPointer64bits(cand30)) {
            ctxMatchGame = cand30;
        } else {
            uintptr_t cand20 = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, gameContext + 0x20));
            if (validOffsetPtr(cand20) && checkPointer64bits(cand20)) {
                ctxMatchGame = cand20;
            } else {
                uintptr_t cand18 = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, gameContext + 0x18));
                if (validOffsetPtr(cand18) && checkPointer64bits(cand18)) {
                    ctxMatchGame = cand18;
                }
            }
        }
    }

    if (ctxMatchGame != self.lastCtxMatchGame) {
        if (self.lastCtxMatchGame != 0 || ctxMatchGame != 0) {
            LOG(@"[FreeFire] ctxMatchGame changed from 0x%lx to 0x%lx; invalidating camera & container cache",
                (unsigned long)self.lastCtxMatchGame, (unsigned long)ctxMatchGame);
            self.cachedCamera = 0;
            self.cachedCamMgr = 0;
            self.cachedContainerAddress = 0;
            self.baseGameStaticFieldsAddress = 0;
        }
        self.lastCtxMatchGame = ctxMatchGame;
    }

    // 4. Resolve Camera and ViewProjection Matrix (100% PURE MEMORY READ)
    uintptr_t camMgr = 0;
    uintptr_t camera = 0;
    if (![self resolveCamera:remoteCall
                   matchGame:currentMatchGame
                ctxMatchGame:ctxMatchGame
                      camera:&camera
                      camMgr:&camMgr]) {
        uintptr_t pe = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, currentMatchGame + kFrontEndGame_PostEffect));
        uintptr_t ownCam = validOffsetPtr(pe) ? CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, pe + kPostEffectManager_OwnerCamera)) : 0;
        uintptr_t uiScene = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, currentMatchGame + kBaseGame_UIScene));
        uintptr_t mgrD8 = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, currentMatchGame + kMatchGame_CameraControllerManager));
        [self reportStage:[NSString stringWithFormat:@"stage 3/6: camera not found (cg=0x%lx'%s', pe=0x%lx, ownCam=0x%lx, ui=0x%lx, mgr=0x%lx)",
                                                      (unsigned long)currentMatchGame, matchGameClass,
                                                      (unsigned long)pe, (unsigned long)ownCam,
                                                      (unsigned long)uiScene, (unsigned long)mgrD8]];
        @synchronized(self) {
            self.hasValidFrame = NO;
            [self clearOverlayTargets];
        }
        return;
    }

    float viewProjection[16] = {};
    float viewMatrix[16] = {};
    if (!ReadCameraVPAndWorldMatrix(remoteCall, camera, viewProjection, viewMatrix)) {
        [self reportStage:
                  [NSString stringWithFormat:@"stage 4/6: camera matrices "
                                             @"unreadable (cam=0x%lx)",
                                             (unsigned long)camera]];
        @synchronized(self) {
            self.hasValidFrame = NO;
            [self clearOverlayTargets];
        }
        return;
    }

    // Camera world position (origin of camera in 3D)
    Vector3 cameraPos = GetCameraPositionFromViewMatrix(viewMatrix);

    // Local player identification (by user ID and Fl0rk getLocalPlayer)
    uint64_t localUserID = ReadMemorySafe<uint64_t>(
        remoteCall, staticFields + kGameFacadeStatic_LocalPlayerUserID);
    uint32_t hostTeamID = 0;
    uint8_t hostPlayerStructTeam = 0;

    // Fl0rk getLocalPlayer from match + 0x58
    uintptr_t localPlayerPawn = 0;
    uintptr_t curMatchObj = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, currentMatchGame + kMatchGame_Match));
    if (!validOffsetPtr(curMatchObj) && validOffsetPtr(ctxMatchGame)) {
        curMatchObj = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, ctxMatchGame + kMatchGame_Match));
    }
    if (validOffsetPtr(curMatchObj)) {
        localPlayerPawn = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, curMatchObj + kMatch_LocalPlayer));
        if (validOffsetPtr(localPlayerPawn)) {
            hostPlayerStructTeam = ReadMemorySafe<uint8_t>(remoteCall, localPlayerPawn + kPlayer_PlayerIDStruct + 0x8);
            if (hostTeamID == 0) {
                hostTeamID = ReadMemorySafe<uint32_t>(remoteCall, localPlayerPawn + kPlayer_TeamModeID);
            }
        }
    }

    // Resolve local player 3D position and camera position fallback
    Vector3 localPlayerPos = Vector3::zero();
    if (validOffsetPtr(localPlayerPawn)) {
        ReadEntityPosition(remoteCall, localPlayerPawn, &localPlayerPos);
        if (cameraPos.x == 0.0f && cameraPos.y == 0.0f && cameraPos.z == 0.0f) {
            uintptr_t camTrans = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, localPlayerPawn + kPlayer_MainCameraTransform));
            if (validOffsetPtr(camTrans)) {
                cameraPos = GetPositionExt(remoteCall, camTrans);
            }
        }
    }

    // 5. Read Entities from MatchGame or BaseGame or UIScene
    FreeFireEntityContainer containerInfo = [self resolveEntityContainer:remoteCall
                                                               matchGame:currentMatchGame
                                                            ctxMatchGame:ctxMatchGame];

    if (!validOffsetPtr(containerInfo.container)) {
        if ([self diagnosticsDue]) {
            [self reportStage:
                      [NSString stringWithFormat:@"stage 5/6: entity container missing (game='%s', ctxMg=0x%lx)",
                                                 matchGameClass, (unsigned long)ctxMatchGame]];
        }
        @synchronized(self) {
            self.hasValidFrame = NO;
        }
        return;
    }

    if (containerInfo.count <= 0 || containerInfo.count > 10000) {
        if ([self diagnosticsDue]) {
            const char *modeHint = "";
            if (!validOffsetPtr(mg) || mg == 0) {
                modeHint = " [In Training Ground - enter Shooting Range / Combat Zone to spawn targets]";
            }
            [self reportStage:
                      [NSString stringWithFormat:@"stage 5/6: entities=%d%s (dict=0x%lx, type=%d, game='%s', ctxMg=0x%lx)",
                                                 (int)containerInfo.count,
                                                 modeHint,
                                                 (unsigned long)containerInfo.container,
                                                 containerInfo.containerType,
                                                 matchGameClass,
                                                 (unsigned long)ctxMatchGame]];
        }
        @synchronized(self) {
            self.hasValidFrame = NO;
        }
        return;
    }

    int32_t loopLimit = containerInfo.count;
    if (containerInfo.containerType == kContainerType_Dictionary && validOffsetPtr(containerInfo.arrayPtr)) {
        int32_t arrLen = ReadMemorySafe<int32_t>(remoteCall, containerInfo.arrayPtr + kArray_Length);
        if (arrLen > 0)
            loopLimit = std::min(arrLen, 2048);
    }

    CGFloat sw = self.remoteWebViewOverlay.cachedScreenWidth;
    CGFloat sh = self.remoteWebViewOverlay.cachedScreenHeight;
    if (sw <= 0 || sh <= 0) {
        sw = MAX(kWidth, kHeight);
        sh = MIN(kWidth, kHeight);
    }

    // Pass 1: find hostTeamID if localUserID is known
    if (localUserID != 0) {
        for (int32_t i = 0; i < loopLimit; ++i) {
            uintptr_t entity = GetEntityFromContainer(remoteCall, containerInfo, i);
            if (!validOffsetPtr(entity))
                continue;

            uint64_t uid = ReadMemorySafe<uint64_t>(
                remoteCall, entity + kPlayer_UserID);
            if (uid == localUserID) {
                hostTeamID = ReadMemorySafe<uint32_t>(
                    remoteCall, entity + kPlayer_TeamModeID);
                break;
            }
        }
    }

    NSMutableArray<FreeFireEntitySnapshot *> *entities =
        [NSMutableArray array];

    NSUInteger scannedCount = 0;
    NSUInteger nonPlayerCount = 0;
    NSUInteger deadSkipped = 0;
    NSUInteger teamSkipped = 0;
    NSUInteger positionFailures = 0;
    NSUInteger projectionFailures = 0;
    NSUInteger projectedCount = 0;
    std::string sampleClasses;

    for (int32_t i = 0; i < loopLimit; ++i) {
        uintptr_t entity = GetEntityFromContainer(remoteCall, containerInfo, i);
        if (!validOffsetPtr(entity))
            continue;

        ++scannedCount;

        // Skip local player
        if (localPlayerPawn != 0 && entity == localPlayerPawn)
            continue;
        if (localUserID != 0) {
            uint64_t uid = ReadMemorySafe<uint64_t>(
                remoteCall, entity + kPlayer_UserID);
            if (uid == localUserID)
                continue;
        }

        // Check if Entity is Player or Target
        char className[64] = {0};
        BOOL isTargetOrPlayer = IsLikelyPlayerOrTarget(remoteCall, entity, className, sizeof(className), true);
        if (!isTargetOrPlayer) {
            Vector3 testPos = Vector3::zero();
            if (ReadEntityPosition(remoteCall, entity, &testPos)) {
                isTargetOrPlayer = YES;
                if (className[0] == '\0') {
                    snprintf(className, sizeof(className), "Target_%u",
                             (unsigned int)(entity & 0xFFFF));
                }
            }
        }

        if (className[0] != '\0' && sampleClasses.size() < 96 &&
            sampleClasses.find(className) == std::string::npos) {
            if (!sampleClasses.empty())
                sampleClasses += ",";
            sampleClasses += className;
        }

        if (!isTargetOrPlayer) {
            ++nonPlayerCount;
            continue;
        }

        // Read HP via Fl0rk IPRIDataPool
        int curHP = 200, maxHP = 200;
        bool hasValidHP = false;
        uintptr_t ipriPool = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, entity + kPlayer_IPRIDataPool)); // 0x68
        if (validOffsetPtr(ipriPool)) {
            uintptr_t v2 = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, ipriPool + 0x10));
            if (validOffsetPtr(v2)) {
                uintptr_t v4_0 = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, v2 + 0x20)); // varID 0 = CurHP
                uintptr_t v4_1 = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, v2 + 0x28)); // varID 1 = MaxHP
                if (validOffsetPtr(v4_0)) {
                    int hp = ReadMemorySafe<int>(remoteCall, v4_0 + 0x18);
                    if (hp >= 0 && hp <= 1000) {
                        curHP = hp;
                        hasValidHP = true;
                    }
                }
                if (validOffsetPtr(v4_1)) {
                    int maxH = ReadMemorySafe<int>(remoteCall, v4_1 + 0x18);
                    if (maxH > 0 && maxH <= 1000) maxHP = maxH;
                }
            }
        }

        // Check Dead State: only skip if confirmed dead (CurHP == 0)
        if (hasValidHP && curHP <= 0) {
            ++deadSkipped;
            continue;
        }

        // Check Team (skip teammates)
        uint32_t teamID =
            ReadMemorySafe<uint32_t>(remoteCall, entity + kPlayer_TeamModeID);
        if (hostTeamID != 0 && teamID == hostTeamID) {
            ++teamSkipped;
            continue;
        }
        uint8_t playerStructTeam = ReadMemorySafe<uint8_t>(remoteCall, entity + kPlayer_PlayerIDStruct + 0x8);
        if (hostPlayerStructTeam != 0 && playerStructTeam == hostPlayerStructTeam) {
            ++teamSkipped;
            continue;
        }

        // Read Position using Fl0rk getPositionExt and bones
        Vector3 headPos = Vector3::zero();
        Vector3 footPos = Vector3::zero();
        uintptr_t headBodyPart = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, entity + kPlayer_HeadBodyPart)); // 0x550
        if (validOffsetPtr(headBodyPart)) {
            uintptr_t headTrans = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, headBodyPart + 0x10));
            headPos = GetPositionExt(remoteCall, headTrans);
        }

        uintptr_t toeBodyPart = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, entity + kPlayer_RightToeBodyPart)); // 0x5A0
        if (validOffsetPtr(toeBodyPart)) {
            uintptr_t toeTrans = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, toeBodyPart + 0x10));
            footPos = GetPositionExt(remoteCall, toeTrans);
        }

        BOOL hasBones = (headPos.x != 0.0f || headPos.y != 0.0f || headPos.z != 0.0f) &&
                        (footPos.x != 0.0f || footPos.y != 0.0f || footPos.z != 0.0f);

        Vector3 pos = Vector3::zero();
        Vector3 headWorld = Vector3::zero();
        Vector3 footWorld = Vector3::zero();

        if (hasBones) {
            headPos.y += 0.2f; // Fl0rk head offset
            pos = footPos;
            headWorld = headPos;
            footWorld = footPos;
        } else {
            if (!ReadEntityPosition(remoteCall, entity, &pos)) {
                ++positionFailures;
                continue;
            }
            headWorld = Vector3(pos.x, pos.y + 1.8f, pos.z);
            footWorld = Vector3(pos.x, pos.y + 0.1f, pos.z);
        }

        // Read Name
        uintptr_t nameStr = CleanPointer(ReadMemorySafe<uintptr_t>(
            remoteCall, entity + kPlayer_OriginalNickName));
        NSString *playerName = ReadIl2CppString(remoteCall, nameStr);
        if (playerName.length == 0) {
            uintptr_t nameStr358 = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, entity + kPlayer_NickName358));
            playerName = ReadIl2CppString(remoteCall, nameStr358);
        }
        if (playerName.length == 0) {
            playerName = [NSString stringWithUTF8String:className];
        }

        // Distance from camera or local player to enemy
        float distance = 0.0f;
        if (cameraPos.x != 0.0f || cameraPos.y != 0.0f || cameraPos.z != 0.0f) {
            distance = Vector3::Distance(cameraPos, pos);
        } else if (localPlayerPos.x != 0.0f || localPlayerPos.y != 0.0f || localPlayerPos.z != 0.0f) {
            distance = Vector3::Distance(localPlayerPos, pos);
        }

        CGFloat screenX = 0.0, screenY = 0.0;
        CGFloat headSX = 0.0, headSY = 0.0;
        CGFloat footSX = 0.0, footSY = 0.0;

        BOOL visible = ProjectToOverlayPoint(pos, viewProjection, sw, sh,
                                             &screenX, &screenY);
        BOOL headVisible = ProjectToOverlayPoint(headWorld, viewProjection,
                                                sw, sh, &headSX, &headSY);
        BOOL footVisible = ProjectToOverlayPoint(footWorld, viewProjection,
                                                sw, sh, &footSX, &footSY);

        if (!visible && !headVisible && !footVisible) {
            ++projectionFailures;
            continue;
        }

        // If distance was not available from 3D positions, use the camera eye depth from projection
        if (distance <= 0.001f) {
            Vector3 vp = WorldToViewportPoint(pos, viewProjection);
            if (vp.z > 0.001f) {
                distance = vp.z;
            }
        }

        // Drop targets that are unrealistically far (beyond 450m)
        if (distance > 450.0f)
            continue;

        ++projectedCount;

        // Ensure valid base screen anchor
        if (headVisible && footVisible) {
            screenX = (headSX + footSX) * 0.5;
            screenY = footSY;
            visible = YES;
        } else if (!visible && headVisible) {
            screenX = headSX;
            screenY = headSY;
            visible = YES;
        } else if (!visible && footVisible) {
            screenX = footSX;
            screenY = footSY;
            visible = YES;
        }

        FreeFireEntitySnapshot *snapshot = [FreeFireEntitySnapshot new];
        snapshot.actorAddress = entity;
        snapshot.position = pos;
        snapshot.health = curHP;
        snapshot.maxHealth = maxHP;
        snapshot.name = playerName;
        snapshot.screenX = screenX;
        snapshot.screenY = screenY;
        snapshot.visible = YES;
        BOOL onScreen = (visible && IsScreenPointInside(screenX, screenY, sw, sh)) ||
                        (headVisible && IsScreenPointInside(headSX, headSY, sw, sh)) ||
                        (footVisible && IsScreenPointInside(footSX, footSY, sw, sh));
        snapshot.onScreen = onScreen;
        snapshot.distance = distance;

        if (headVisible && footVisible) {
            snapshot.headX = headSX;
            snapshot.headY = headSY;
            snapshot.footX = footSX;
            snapshot.footY = footSY;

            CGFloat boxHeight = fabs(footSY - headSY);
            CGFloat boxWidth = boxHeight * 0.5f;
            CGFloat centerX = (headSX + footSX) * 0.5;
            snapshot.boxX = centerX - boxWidth * 0.5;
            snapshot.boxY = MIN(headSY, footSY);
            snapshot.boxW = boxWidth;
            snapshot.boxH = boxHeight;
        } else if (visible) {
            CGFloat estimatedH = (sh / std::max(distance, 1.0f)) * 1.8f;
            CGFloat boxWidth = estimatedH * 0.5f;
            snapshot.boxX = screenX - boxWidth * 0.5;
            snapshot.boxY = screenY - estimatedH;
            snapshot.boxW = boxWidth;
            snapshot.boxH = estimatedH;
            snapshot.headX = screenX;
            snapshot.headY = screenY - estimatedH;
            snapshot.footX = screenX;
            snapshot.footY = screenY;
        }

        [entities addObject:snapshot];
    }

    [entities sortUsingComparator:^NSComparisonResult(FreeFireEntitySnapshot *a, FreeFireEntitySnapshot *b) {
        if (a.onScreen && !b.onScreen) return NSOrderedAscending;
        if (!a.onScreen && b.onScreen) return NSOrderedDescending;
        if (a.distance < b.distance) return NSOrderedAscending;
        if (a.distance > b.distance) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    if (entities.count > 50) {
        [entities removeObjectsInRange:NSMakeRange(50, entities.count - 50)];
    }
    [entities sortUsingComparator:^NSComparisonResult(FreeFireEntitySnapshot *a, FreeFireEntitySnapshot *b) {
        if (a.actorAddress < b.actorAddress) return NSOrderedAscending;
        if (a.actorAddress > b.actorAddress) return NSOrderedDescending;
        return NSOrderedSame;
    }];

    @synchronized(self) {
        self.viewProjectionData = [NSData dataWithBytes:viewProjection
                                                 length:sizeof(viewProjection)];
        self.entitySnapshots = [entities copy];
        self.hasValidFrame = YES;
        [self showOverlay:remoteCall];
    }

    // A frame went through, so the next failure is reported again.
    [self reportStage:@""];

    if ([self diagnosticsDue]) {
        char classes[128] = {0};
        strncpy(classes, sampleClasses.c_str(), sizeof(classes) - 1);
        [self
            reportDiagnostics:
                [NSString
                    stringWithFormat:@"ok: camMgr=0x%lx cam=0x%lx container=0x%lx "
                                     @"isList=%d count=%d scanned=%lu nonPlayer=%lu "
                                     @"dead=%lu team=%lu noPos=%lu noProj=%lu "
                                     @"projected=%lu classes=[%s]",
                                     (unsigned long)camMgr,
                                     (unsigned long)camera,
                                     (unsigned long)containerInfo.container,
                                     containerInfo.isList ? 1 : 0,
                                     (int)containerInfo.count,
                                     (unsigned long)scannedCount,
                                     (unsigned long)nonPlayerCount,
                                     (unsigned long)deadSkipped,
                                     (unsigned long)teamSkipped,
                                     (unsigned long)positionFailures,
                                     (unsigned long)projectionFailures,
                                     (unsigned long)projectedCount, classes]];
    }
}

- (void)dealloc {
    [self stopLoop];
}

@end

NS_ASSUME_NONNULL_END
