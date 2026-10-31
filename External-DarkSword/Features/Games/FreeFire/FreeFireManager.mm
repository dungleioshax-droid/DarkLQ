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
@property(nonatomic, assign) NSTimeInterval lastStaticResolveAttempt;
@property(nonatomic, copy) NSString *binaryBaseSource;
@property(nonatomic, strong) RemoteWebViewOverlay *remoteWebViewOverlay;
@property(nonatomic, assign) NSTimeInterval lastDiscoveryAttempt;
@property(nonatomic, assign) uintptr_t cachedCamera;
@property(nonatomic, assign) uintptr_t cachedCamMgr;

- (uint64_t)getFreeFireBaseAddress;
- (void)updateSnapshot:(RemoteCall *)remoteCall;
- (void)showOverlay:(RemoteCall *)remoteCall;
- (BOOL)resolveCamera:(RemoteCall *)remoteCall
            matchGame:(uintptr_t)currentMatchGame
               camera:(uintptr_t *)outCamera
               camMgr:(uintptr_t *)outCamMgr;
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
                          : kGameFacadeStatic_CurrentMatchGame;
    const uint64_t dumpSlots[] = {
        kGameFacadeStatic_CurrentMatchGame,
        kGameFacadeStatic_CurrentGame
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
        matchGame = ReadMemorySafe<uintptr_t>(remoteCall,
                                              staticFields + matchGameOffset);
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

// Resolves the camera controller manager and its main camera.
- (BOOL)resolveCamera:(RemoteCall *)remoteCall
            matchGame:(uintptr_t)currentMatchGame
               camera:(uintptr_t *)outCamera
               camMgr:(uintptr_t *)outCamMgr {
    if (!remoteCall || !validOffsetPtr(currentMatchGame))
        return NO;

    currentMatchGame = CleanPointer(currentMatchGame);

    // Strategy 0: Test cached camera if still valid
    if (validOffsetPtr(self.cachedCamera)) {
        float testVP[16] = {}, testView[16] = {};
        if (ReadCameraVPAndWorldMatrix(remoteCall, self.cachedCamera, testVP, testView)) {
            if (outCamera) *outCamera = self.cachedCamera;
            if (outCamMgr) *outCamMgr = self.cachedCamMgr;
            return YES;
        } else {
            self.cachedCamera = 0;
            self.cachedCamMgr = 0;
        }
    }

    uintptr_t camera = 0;
    uintptr_t camMgr = 0;

    // Strategy 1: CameraControllerManager in currentMatchGame (Standard Match: BR / CS)
    uint64_t camMgrOffset = gFreeFireCameraManagerFieldOffset != 0
                                ? gFreeFireCameraManagerFieldOffset
                                : kMatchGame_CameraControllerManager;
    camMgr = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, currentMatchGame + camMgrOffset));
    if (validOffsetPtr(camMgr)) {
        uint64_t cameraOffset = gFreeFireCameraFieldOffset != 0
                                    ? gFreeFireCameraFieldOffset
                                    : kCameraControllerManager_MainCamera;
        uintptr_t candCam = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, camMgr + cameraOffset));
        if (validOffsetPtr(candCam)) {
            float testVP[16] = {}, testView[16] = {};
            if (ReadCameraVPAndWorldMatrix(remoteCall, candCam, testVP, testView)) {
                camera = candCam;
            }
        }
        if (!validOffsetPtr(camera)) {
            candCam = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, camMgr + kCameraControllerManager_SubCamera));
            if (validOffsetPtr(candCam)) {
                float testVP[16] = {}, testView[16] = {};
                if (ReadCameraVPAndWorldMatrix(remoteCall, candCam, testVP, testView)) {
                    camera = candCam;
                    gFreeFireCameraFieldOffset = kCameraControllerManager_SubCamera;
                }
            }
        }
    }

    // Dynamic scan for CameraControllerManager in matchGame
    if (!validOffsetPtr(camera) && [self discoveryDue]) {
        uint64_t discoveredMgr = FindIl2CppFieldMatching(
            remoteCall, currentMatchGame, 0x300, LooksLikeCameraManager);
        if (discoveredMgr != 0) {
            camMgrOffset = discoveredMgr;
            gFreeFireCameraManagerFieldOffset = discoveredMgr;
            camMgr = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, currentMatchGame + discoveredMgr));
            if (validOffsetPtr(camMgr)) {
                for (uint64_t cOff = 0x20; cOff <= 0x80; cOff += sizeof(uintptr_t)) {
                    uintptr_t candCam = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, camMgr + cOff));
                    if (validOffsetPtr(candCam)) {
                        float testVP[16] = {}, testView[16] = {};
                        if (ReadCameraVPAndWorldMatrix(remoteCall, candCam, testVP, testView)) {
                            camera = candCam;
                            gFreeFireCameraFieldOffset = cOff;
                            break;
                        }
                    }
                }
            }
        }
    }

    // Strategy 2: Call Camera.get_main() via RemoteCall (Unity standard MainCamera)
    if (!validOffsetPtr(camera) && [self discoveryDue]) {
        uint64_t mainCam = [remoteCall doRemoteCallStableWithTimeout:2
                                                       functionName:(char *)"Camera_get_main"
                                                    functionPointer:(void *)(self.binaryBase + kCamera_GetMain)
                                                               args:NULL
                                                           argCount:0];
        mainCam = CleanPointer(mainCam);
        if (validOffsetPtr(mainCam)) {
            float testVP[16] = {}, testView[16] = {};
            if (ReadCameraVPAndWorldMatrix(remoteCall, mainCam, testVP, testView)) {
                camera = mainCam;
                LOG(@"[FreeFire] Discovered camera via Camera.get_main(): 0x%lx", (unsigned long)mainCam);
            }
        }
    }

    // Strategy 3: Call UICamera.get_mainCamera() via RemoteCall (RVA 0x15431B0)
    if (!validOffsetPtr(camera) && [self discoveryDue]) {
        uint64_t uiMainCam = [remoteCall doRemoteCallStableWithTimeout:2
                                                          functionName:(char *)"UICamera_get_mainCamera"
                                                       functionPointer:(void *)(self.binaryBase + 0x15431B0)
                                                                  args:NULL
                                                              argCount:0];
        uiMainCam = CleanPointer(uiMainCam);
        if (validOffsetPtr(uiMainCam)) {
            float testVP[16] = {}, testView[16] = {};
            if (ReadCameraVPAndWorldMatrix(remoteCall, uiMainCam, testVP, testView)) {
                camera = uiMainCam;
                LOG(@"[FreeFire] Discovered camera via UICamera.get_mainCamera(): 0x%lx", (unsigned long)uiMainCam);
            }
        }
    }

    // Strategy 4: Call Camera.get_current() via RemoteCall (RVA 0x8CFF0F4)
    if (!validOffsetPtr(camera) && [self discoveryDue]) {
        uint64_t curCam = [remoteCall doRemoteCallStableWithTimeout:2
                                                       functionName:(char *)"Camera_get_current"
                                                    functionPointer:(void *)(self.binaryBase + 0x8CFF0F4)
                                                               args:NULL
                                                           argCount:0];
        curCam = CleanPointer(curCam);
        if (validOffsetPtr(curCam)) {
            float testVP[16] = {}, testView[16] = {};
            if (ReadCameraVPAndWorldMatrix(remoteCall, curCam, testVP, testView)) {
                camera = curCam;
                LOG(@"[FreeFire] Discovered camera via Camera.get_current(): 0x%lx", (unsigned long)curCam);
            }
        }
    }

    // Strategy 5: Inspect BaseGame.m_UIScene (Training Mode / Social Area / FrontEndGame)
    if (!validOffsetPtr(camera)) {
        uintptr_t uiScene = CleanPointer(ReadMemorySafe<uintptr_t>(
            remoteCall, currentMatchGame + kBaseGame_UIScene));
        if (validOffsetPtr(uiScene)) {
            const uint64_t sceneCamOffsets[] = {
                kUIFrontEndScene_UI3DCamera, // 0x170
                kUIFrontEndScene_BgCamera,   // 0x178
                0x450,                       // m_CameraEntryCtrl
                0x458,                       // m_CameraInGameCtrl
                0x1080                       // CameraHeightCtrl
            };
            for (uint64_t off : sceneCamOffsets) {
                uintptr_t cand = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, uiScene + off));
                if (validOffsetPtr(cand)) {
                    float testVP[16] = {}, testView[16] = {};
                    if (ReadCameraVPAndWorldMatrix(remoteCall, cand, testVP, testView)) {
                        camera = cand;
                        break;
                    }
                }
            }

            if (!validOffsetPtr(camera)) {
                uintptr_t gyro = CleanPointer(ReadMemorySafe<uintptr_t>(
                    remoteCall, uiScene + kUIFrontEndScene_LobbyCamGyro));
                if (validOffsetPtr(gyro)) {
                    uintptr_t c1 = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, gyro + 0x20));
                    uintptr_t c2 = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, gyro + 0x28));
                    float testVP[16] = {}, testView[16] = {};
                    if (validOffsetPtr(c1) && ReadCameraVPAndWorldMatrix(remoteCall, c1, testVP, testView)) {
                        camera = c1;
                    } else if (validOffsetPtr(c2) && ReadCameraVPAndWorldMatrix(remoteCall, c2, testVP, testView)) {
                        camera = c2;
                    }
                }
            }

            if (!validOffsetPtr(camera)) {
                for (uint64_t off = 0x100; off <= 0x300; off += sizeof(uintptr_t)) {
                    uintptr_t ptr = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, uiScene + off));
                    if (validOffsetPtr(ptr)) {
                        float testVP[16] = {}, testView[16] = {};
                        if (ReadCameraVPAndWorldMatrix(remoteCall, ptr, testVP, testView)) {
                            camera = ptr;
                            break;
                        }
                    }
                }
            }
        }
    }

    // Strategy 6: Scan currentMatchGame fields for any camera (0x10 to 0x250)
    if (!validOffsetPtr(camera)) {
        for (uint64_t off = 0x10; off <= 0x250; off += sizeof(uintptr_t)) {
            uintptr_t ptr = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, currentMatchGame + off));
            if (validOffsetPtr(ptr)) {
                float testVP[16] = {}, testView[16] = {};
                if (ReadCameraVPAndWorldMatrix(remoteCall, ptr, testVP, testView)) {
                    camera = ptr;
                    break;
                }
            }
        }
    }

    if (!validOffsetPtr(camera))
        return NO;

    self.cachedCamera = camera;
    self.cachedCamMgr = camMgr;

    if (outCamera)
        *outCamera = camera;
    if (outCamMgr)
        *outCamMgr = camMgr;
    return YES;
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

    char mgName[48] = {0}, cgName[48] = {0};
    if (validOffsetPtr(mg))
        ReadIl2CppClassName(remoteCall, mg, mgName, sizeof(mgName));
    if (validOffsetPtr(cg))
        ReadIl2CppClassName(remoteCall, cg, cgName, sizeof(cgName));

    if (FieldHoldsMatchGame(remoteCall, mg)) {
        currentMatchGame = mg;
        matchGameOffset = kGameFacadeStatic_CurrentMatchGame;
    } else if (FieldHoldsMatchGame(remoteCall, cg)) {
        currentMatchGame = cg;
        matchGameOffset = kGameFacadeStatic_CurrentGame;
    } else if (validOffsetPtr(cg) && FieldHoldsAnyGame(remoteCall, cg)) {
        // Training Mode / Social Area / Custom Mode
        currentMatchGame = cg;
        matchGameOffset = kGameFacadeStatic_CurrentGame;
    } else if (validOffsetPtr(cg)) {
        // GameFacade.CurrentGame fallback: in Free Fire, offset 0x0 is guaranteed to be the active BaseGame
        currentMatchGame = cg;
        matchGameOffset = kGameFacadeStatic_CurrentGame;
    } else if (validOffsetPtr(mg)) {
        currentMatchGame = mg;
        matchGameOffset = kGameFacadeStatic_CurrentMatchGame;
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
    if (validOffsetPtr(currentMatchGame)) {
        ReadIl2CppClassName(remoteCall, currentMatchGame, matchGameClass,
                            sizeof(matchGameClass));
    }

    if (!validOffsetPtr(currentMatchGame)) {
        [self reportStage:[NSString stringWithFormat:@"stage 2/6: no game (cg=0x%lx'%s', mg=0x%lx'%s')",
                                                     (unsigned long)cg, cgName,
                                                     (unsigned long)mg, mgName]];
        @synchronized(self) {
            self.hasValidFrame = NO;
            [self clearOverlayTargets];
        }
        return;
    }

    // 3. Resolve Camera and ViewProjection Matrix (100% PURE MEMORY READ)
    uintptr_t camMgr = 0;
    uintptr_t camera = 0;
    if (![self resolveCamera:remoteCall
                   matchGame:currentMatchGame
                      camera:&camera
                      camMgr:&camMgr]) {
        uintptr_t uiScene = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, currentMatchGame + kBaseGame_UIScene));
        uintptr_t c170 = validOffsetPtr(uiScene) ? CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, uiScene + 0x170)) : 0;
        uintptr_t c178 = validOffsetPtr(uiScene) ? CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, uiScene + 0x178)) : 0;
        uintptr_t mgrD8 = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, currentMatchGame + 0xD8));
        [self reportStage:[NSString stringWithFormat:@"stage 3/6: camera not found (cg=0x%lx'%s', ui=0x%lx, c170=0x%lx, c178=0x%lx, mgr=0x%lx)",
                                                      (unsigned long)currentMatchGame, matchGameClass,
                                                      (unsigned long)uiScene,
                                                      (unsigned long)c170, (unsigned long)c178,
                                                      (unsigned long)mgrD8]];
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

    // Local player identification (by user ID)
    uint64_t localUserID = ReadMemorySafe<uint64_t>(
        remoteCall, staticFields + kGameFacadeStatic_LocalPlayerUserID);
    uint32_t hostTeamID = 0;

    // 4. Read Entities from MatchGame.m_ReplicationEntitis or BaseGame.sAllEntities
    uint64_t entitiesOffset = gFreeFireEntitiesFieldOffset != 0
                                  ? gFreeFireEntitiesFieldOffset
                                  : kMatchGame_ReplicationEntities;
    uintptr_t repDict = ReadMemorySafe<uintptr_t>(
        remoteCall, currentMatchGame + entitiesOffset);

    if (!IsDictionaryObject(remoteCall, repDict)) {
        // Fallback to BaseGame.sAllEntities (used in Training Mode / Social Area)
        uintptr_t allEntities = ResolveBaseGameAllEntities(remoteCall, currentMatchGame);
        if (validOffsetPtr(allEntities)) {
            repDict = allEntities;
            entitiesOffset = kBaseGameStatic_sAllEntities;
        }
    }

    if (!IsDictionaryObject(remoteCall, repDict) && [self discoveryDue]) {
        uint64_t discovered = FindIl2CppFieldMatching(
            remoteCall, currentMatchGame, 0x300, LooksLikePlayerDictionary);
        if (discovered != 0) {
            entitiesOffset = discovered;
            gFreeFireEntitiesFieldOffset = discovered;
            repDict = ReadMemorySafe<uintptr_t>(
                remoteCall, currentMatchGame + discovered);
        }
    }
    if (!validOffsetPtr(repDict)) {
        [self reportStage:
                  [NSString stringWithFormat:@"stage 5/6: entity dictionary missing (game='%s')",
                                             matchGameClass]];
        @synchronized(self) {
            self.hasValidFrame = NO;
        }
        return;
    }

    int32_t dictCount =
        ReadMemorySafe<int32_t>(remoteCall, repDict + kDictionary_Count);
    if (dictCount <= 0 || dictCount > 10000) {
        [self reportStage:
                  [NSString stringWithFormat:@"stage 5/6: entities=%d (waiting for targets/match)",
                                             (int)dictCount]];
        @synchronized(self) {
            self.hasValidFrame = NO;
        }
        return;
    }

    uintptr_t entriesArray =
        ReadMemorySafe<uintptr_t>(remoteCall, repDict + kDictionary_Entries);
    if (!validOffsetPtr(entriesArray)) {
        [self reportStage:@"stage 5/6: dictionary entries unreadable"];
        @synchronized(self) {
            self.hasValidFrame = NO;
        }
        return;
    }

    int32_t maxEntries = ReadMemorySafe<int32_t>(
        remoteCall, entriesArray + kArray_Length);
    int32_t loopLimit = std::min(maxEntries, 2048);

    CGFloat sw = self.remoteWebViewOverlay.cachedScreenWidth;
    CGFloat sh = self.remoteWebViewOverlay.cachedScreenHeight;
    if (sw <= 0 || sh <= 0) {
        sw = MAX(kWidth, kHeight);
        sh = MIN(kWidth, kHeight);
    }

    // Pass 1: find hostTeamID if localUserID is known
    if (localUserID != 0) {
        for (int32_t i = 0; i < loopLimit; ++i) {
            uintptr_t entryAddr =
                entriesArray + kArray_Vector + (uint64_t)i * kEntry_Size;
            int32_t hashCode =
                ReadMemorySafe<int32_t>(remoteCall, entryAddr + kEntry_HashCode);
            if (hashCode < 0)
                continue;

            uintptr_t entity =
                ReadMemorySafe<uintptr_t>(remoteCall, entryAddr + kEntry_Value);
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
        uintptr_t entryAddr =
            entriesArray + kArray_Vector + (uint64_t)i * kEntry_Size;
        int32_t hashCode =
            ReadMemorySafe<int32_t>(remoteCall, entryAddr + kEntry_HashCode);
        if (hashCode < 0)
            continue;

        uintptr_t entity =
            ReadMemorySafe<uintptr_t>(remoteCall, entryAddr + kEntry_Value);
        if (!validOffsetPtr(entity))
            continue;

        ++scannedCount;

        // Skip local player
        if (localUserID != 0) {
            uint64_t uid = ReadMemorySafe<uint64_t>(
                remoteCall, entity + kPlayer_UserID);
            if (uid == localUserID)
                continue;
        }

        // Check if Entity is Player
        uintptr_t klass = ReadMemorySafe<uintptr_t>(remoteCall, entity);
        char className[64] = {0};
        if (validOffsetPtr(klass)) {
            ReadKlassName(remoteCall, klass, className, sizeof(className));
        }

        if (className[0] != '\0' && sampleClasses.size() < 96 &&
            sampleClasses.find(className) == std::string::npos) {
            if (!sampleClasses.empty())
                sampleClasses += ",";
            sampleClasses += className;
        }

        BOOL isTargetOrPlayer = NO;
        if (className[0] != '\0') {
            isTargetOrPlayer = (strncmp(className, "Player", 6) == 0 ||
                                strstr(className, "Player") != NULL ||
                                strstr(className, "Target") != NULL ||
                                strstr(className, "Dummy") != NULL ||
                                strstr(className, "AIPawn") != NULL ||
                                IsSubclassOf(remoteCall, entity, "Player") ||
                                IsSubclassOf(remoteCall, entity, "AttackableEntity"));
        } else {
            // Structural fallback: check if entity has a valid 3D position
            Vector3 testPos = Vector3::zero();
            if (ReadEntityPosition(remoteCall, entity, &testPos)) {
                isTargetOrPlayer = YES;
                snprintf(className, sizeof(className), "Target_%u", (unsigned int)(entity & 0xFFFF));
            }
        }

        if (!isTargetOrPlayer) {
            ++nonPlayerCount;
            continue;
        }

        // Check Dead State
        uint8_t isDead = ReadMemorySafe<uint8_t>(
            remoteCall, entity + kAttackableEntity_IsDeadFlag);
        if (isDead != 0) {
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

        // Read Position using Pure Memory Reads
        Vector3 pos = Vector3::zero();
        if (!ReadEntityPosition(remoteCall, entity, &pos)) {
            ++positionFailures;
            continue;
        }

        // Read Name
        uintptr_t nameStr = ReadMemorySafe<uintptr_t>(
            remoteCall, entity + kPlayer_OriginalNickName);
        NSString *playerName = ReadIl2CppString(remoteCall, nameStr);
        if (playerName.length == 0) {
            playerName = [NSString stringWithUTF8String:className];
        }

        // Distance from camera to player
        float distance = Vector3::Distance(cameraPos, pos);

        // Project Foot & Head
        Vector3 headWorld = Vector3(pos.x, pos.y + 1.8f, pos.z);
        Vector3 footWorld = Vector3(pos.x, pos.y + 0.1f, pos.z);

        CGFloat screenX = 0.0, screenY = 0.0;
        CGFloat headSX = 0.0, headSY = 0.0;
        CGFloat footSX = 0.0, footSY = 0.0;

        BOOL visible = ProjectToOverlayPoint(pos, viewProjection, sw, sh,
                                             &screenX, &screenY);
        if (!visible) {
            ++projectionFailures;
            continue;
        }

        ++projectedCount;

        BOOL headVisible = ProjectToOverlayPoint(headWorld, viewProjection,
                                                sw, sh, &headSX, &headSY);
        BOOL footVisible = ProjectToOverlayPoint(footWorld, viewProjection,
                                                sw, sh, &footSX, &footSY);

        FreeFireEntitySnapshot *snapshot = [FreeFireEntitySnapshot new];
        snapshot.actorAddress = entity;
        snapshot.position = pos;
        snapshot.health = 200;
        snapshot.maxHealth = 200;
        snapshot.name = playerName;
        snapshot.screenX = screenX;
        snapshot.screenY = screenY;
        snapshot.visible = YES;
        BOOL onScreen = IsScreenPointInside(screenX, screenY, sw, sh) ||
                        (headVisible && IsScreenPointInside(headSX, headSY, sw, sh));
        snapshot.onScreen = onScreen;
        snapshot.distance = distance;

        if (headVisible && footVisible) {
            snapshot.headX = headSX;
            snapshot.headY = headSY;
            snapshot.footX = footSX;
            snapshot.footY = footSY;

            CGFloat boxHeight = fabs(footSY - headSY);
            CGFloat boxWidth = boxHeight * 0.55;
            CGFloat centerX = (headSX + footSX) * 0.5;
            snapshot.boxX = centerX - boxWidth / 2.0;
            snapshot.boxY = MIN(headSY, footSY);
            snapshot.boxW = boxWidth;
            snapshot.boxH = boxHeight;
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
    if (entities.count > 5) {
        [entities removeObjectsInRange:NSMakeRange(5, entities.count - 5)];
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
                    stringWithFormat:@"ok: camMgr=0x%lx cam=0x%lx dict=0x%lx "
                                     @"count=%d scanned=%lu nonPlayer=%lu "
                                     @"dead=%lu team=%lu noPos=%lu noProj=%lu "
                                     @"projected=%lu classes=[%s]",
                                     (unsigned long)camMgr,
                                     (unsigned long)camera,
                                     (unsigned long)repDict, (int)dictCount,
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
