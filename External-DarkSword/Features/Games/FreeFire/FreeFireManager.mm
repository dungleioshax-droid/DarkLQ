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
    self = [super init];
    if (self) {
        _remoteCall = remoteCall;
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
                              self.remoteWebViewOverlay =
                                  [[RemoteWebViewOverlay alloc]
                                      initWithRemoteCall:self.remoteCall];
                          }
                          if ([self.remoteWebViewOverlay setupBaseOverlay]) {
                              LOG(@"[FreeFire] WKWebView overlay setup done.");
                          } else {
                              overlayCooldown = 50; // Throttle retry to ~0.5s
                          }
                      } else {
                          overlayCooldown--;
                      }
                  }

                  if (self.isESPEnabled) {
                      [self updateSnapshot:self.remoteCall];
                  }

                  // Never go silent: say why nothing is being drawn.
                  if (!self.remoteWebViewOverlay.isOverlayReady) {
                      [self reportStatus:@"overlay not ready: ESP menu and drawing unavailable"];
                  } else if (!self.isESPEnabled) {
                      [self reportStatus:@"ESP is off: enable Player ESP in the overlay menu"];
                  }
              }
          }
          usleep(10000); // ~100 FPS loop
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


-(uintptr_t)resolveGameFacadeStaticFields:(RemoteCall *)remoteCall {
    if (self.staticFieldsAddress != 0) {
        return self.staticFieldsAddress;
    }

    uintptr_t candidate = 0;

    // Attempt 1: Decode from GameFacade..cctor (0x5944B44)
    uintptr_t cctorAddr = self.binaryBase + kGameFacade_CCtor;
    candidate = DecodeArm64AdrLdr(remoteCall, cctorAddr);

    // Attempt 2: Decode from CurrentLocalPlayer (0x591BD2C)
    if (!validOffsetPtr(candidate)) {
        uintptr_t clpAddr = self.binaryBase + kGameFacade_CurrentLocalPlayer;
        candidate = DecodeArm64AdrLdr(remoteCall, clpAddr);
    }

    // Attempt 3: Decode from SetCurrentGame (0x5918864)
    if (!validOffsetPtr(candidate)) {
        uintptr_t scgAddr = self.binaryBase + 0x5918864;
        candidate = DecodeArm64AdrLdr(remoteCall, scgAddr);
    }

    if (!validOffsetPtr(candidate)) {
        [self reportStatus:@"static fields: no candidates decoded"];
        return 0;
    }

    // Verify the candidate is actually a GameFacade Il2CppClass before using +0xB8.
    // In IL2CPP, Il2CppClass.name is at klass + gFreeFireKlassNameOffset (0x10 by default).
    uintptr_t namePtr = ReadMemorySafe<uintptr_t>(remoteCall, candidate + gFreeFireKlassNameOffset);
    char className[64] = {0};
    if (validOffsetPtr(namePtr)) {
        [remoteCall remoteRead:namePtr to:nameBuf size:sizeof(className) - 1];
    }
    BOOL classNameMatches =
        (strstr(className, "GameFacade") != NULL ||
         strstr(className, "COW_GameFacade") != NULL);

    // Also read the +0xB8 slot; if it already looks like a valid pointer,
    // treat candidate as a potential static_fields address.
    uintptr_t staticFieldsFromCandidate = ReadMemorySafe<uintptr_t>(remoteCall, candidate + 0xB8);
    BOOL staticFieldsLooksValid = validOffsetPtr(staticFieldsFromCandidate);

    // Strategy A: candidate is an Il2CppClass* and class name matches.
    if (classNameMatches && staticFieldsLooksValid) {
        self.staticFieldsAddress = staticFieldsFromCandidate;
        LOG(@"[FreeFire] GameFacade static fields (class-name verified): 0x%lx (candidate=0x%lx)",
            (unsigned long)self.staticFieldsAddress, (unsigned long)candidate);
        [self reportStatus:@@"static fields resolved via GameFacade class name"];
        return self.staticFieldsAddress;
    }

    // Strategy B: candidate may already be static_fields (no valid class name).
    // Scan the first few slots for hints that this block belongs to GameFacade.
    if (!staticFieldsLooksValid) {
        BOOL hintsGameFacade = NO;
        for (uint64_t slot = 0x0; slot <= 0x38; slot += sizeof(uintptr_t)) {
            uintptr_t slotVal = ReadMemorySafe<uintptr_t>(remoteCall, candidate + slot);
            if (validOffsetPtr(slotVal) &&
                (Il2CppClassNameContains(remoteCall, slotVal, "GameFacade") ||
                 Il2CppClassNameContains(remoteCall, slotVal, "MatchGame") ||
                 Il2CppClassNameContains(remoteCall, slotVal, "BaseGame"))) {
            hintsGameFacade = YES;
            break;
        }
        }
        if (hintsGameFacade) {
            self.staticFieldsAddress = candidate;
            LOG(@"[FreeFire] GameFacade static fields (candidate already static_fields): 0x%lx",
                (unsigned long)self.staticFieldsAddress);
            [self reportStatus:@@"static fields resolved as pre-existing static_fields block"];
            return self.staticFieldsAddress;
        }
    }

    // Strategy C: scan the image for the literal "GameFacade" string and remap
    // the class-name offset for all candidates. This corrects stale dump offsets
    // across game updates.
    if (gGameFacadeNameScanned == NO) {
        uintptr_t nameAddr = FindGameFacadeNameInImage(remoteCall, self.binaryBase);
        if (validOffsetPtr(nameAddr)) {
            gGameFacadeNameScanned = YES;
            gFreeFireKlassNameOffset = FindNameOffsetByString(
                remoteCall, candidates[0], nameAddr);
        }
    }
    if (gFreeFireKlassNameOffset != 0) {
        namePtr = ReadMemorySafe<uintptr_t>(remoteCall, candidate + gFreeFireKlassNameOffset);
        char correctedName[64] = {0};
        if (validOffsetPtr(namePtr)) {
            [remoteCall remoteRead:namePtr to:correctedName size:sizeof(correctedName) - 1];
        }
        BOOL correctedClassNameMatches =
            (strstr(correctedName, "GameFacade") != NULL ||
             strstr(correctedName, "COW_GameFacade") != NULL);
        if (correctedClassNameMatches) {
            uintptr_t sf = ReadMemorySafe<uintptr_t>(remoteCall, candidate + 0xB8);
            if (validOffsetPtr(sf)) {
                self.staticFieldsAddress = sf;
                LOG(@"[FreeFire] GameFacade static fields (image-corrected name): 0x%lx",
                    (unsigned long)self.staticFieldsAddress);
                [self reportStatus:@@"static fields resolved via image-corrected class name"];
                return self.staticFieldsAddress;
            }
        }
    }

    // Fallback: weak heuristic via LooksLikeGameFacadeStaticBlock.
    if (LooksLikeGameFacadeStaticBlock(remoteCall, candidate)) {
        self.staticFieldsAddress = candidate;
        LOG(@"[FreeFire] GameFacade static fields (LooksLike heuristic): 0x%lx",
            (unsigned long)self.staticFieldsAddress);
        [self reportStatus:@@"static fields resolved via LooksLikeGameFacadeStaticBlock heuristic"];
        return self.staticFieldsAddress;
    }

    [self reportStatus:
        [NSString stringWithFormat:@"static fields unverified: cands=1 name='%s'", className]];
    return 0;
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

// Resolves the camera controller manager and its main camera. Field offsets
// come from the dump first and are rediscovered by class name when they no
// longer point at a live camera.
- (BOOL)resolveCamera:(RemoteCall *)remoteCall
            matchGame:(uintptr_t)currentMatchGame
               camera:(uintptr_t *)outCamera
               camMgr:(uintptr_t *)outCamMgr {
    if (!remoteCall || !validOffsetPtr(currentMatchGame))
        return NO;

    uint64_t camMgrOffset = gFreeFireCameraManagerFieldOffset != 0
                                ? gFreeFireCameraManagerFieldOffset
                                : kMatchGame_CameraControllerManager;
    uintptr_t camMgr =
        ReadMemorySafe<uintptr_t>(remoteCall, currentMatchGame + camMgrOffset);

    uint64_t cameraOffset = gFreeFireCameraFieldOffset != 0
                                ? gFreeFireCameraFieldOffset
                                : kCameraControllerManager_MainCamera;
    uintptr_t camera =
        validOffsetPtr(camMgr)
            ? ReadMemorySafe<uintptr_t>(remoteCall, camMgr + cameraOffset)
            : 0;

    if (!validOffsetPtr(camera) && validOffsetPtr(camMgr)) {
        camera = ReadMemorySafe<uintptr_t>(
            remoteCall, camMgr + kCameraControllerManager_SubCamera);
        if (validOffsetPtr(camera))
            cameraOffset = kCameraControllerManager_SubCamera;
    }

    if (!validOffsetPtr(camera) && [self discoveryDue]) {
        uint64_t discoveredMgr = FindIl2CppFieldMatching(
            remoteCall, currentMatchGame, 0x300, LooksLikeCameraManager);
        if (discoveredMgr != 0) {
            camMgrOffset = discoveredMgr;
            gFreeFireCameraManagerFieldOffset = discoveredMgr;
            camMgr = ReadMemorySafe<uintptr_t>(
                remoteCall, currentMatchGame + discoveredMgr);
        }

        if (validOffsetPtr(camMgr)) {
            cameraOffset = kCameraControllerManager_MainCamera;
            camera = ReadMemorySafe<uintptr_t>(remoteCall,
                                              camMgr + cameraOffset);
            if (!validOffsetPtr(camera)) {
                cameraOffset = kCameraControllerManager_SubCamera;
                camera = ReadMemorySafe<uintptr_t>(remoteCall,
                                                  camMgr + cameraOffset);
            }
        }

        if (validOffsetPtr(camMgr) && !validOffsetPtr(camera)) {
            uint64_t discoveredCamera = FindIl2CppFieldMatching(
                remoteCall, camMgr, 0x100, FieldHoldsCamera);
            if (discoveredCamera != 0) {
                cameraOffset = discoveredCamera;
                gFreeFireCameraFieldOffset = discoveredCamera;
                camera = ReadMemorySafe<uintptr_t>(
                    remoteCall, camMgr + discoveredCamera);
            }
        }
    }

    if (!validOffsetPtr(camera))
        return NO;

    gFreeFireCameraFieldOffset = cameraOffset;
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

    // 2. Read CurrentMatchGame
    // In match, CurrentMatchGame sits at the static field discovered above.
    // In lobby, CurrentMatchGame is NULL (0x0). Do NOT fall back to CurrentGame
    // (which is LobbyGame).
    uint64_t matchGameOffset = gFreeFireMatchGameFieldOffset != 0
                                   ? gFreeFireMatchGameFieldOffset
                                   : kGameFacadeStatic_CurrentMatchGame;
    uintptr_t currentMatchGame = ReadMemorySafe<uintptr_t>(
        remoteCall, staticFields + matchGameOffset);

    char matchGameClass[64] = {0};
    BOOL hasMatchGameClass =
        ReadIl2CppClassName(remoteCall, currentMatchGame, matchGameClass,
                            sizeof(matchGameClass));
    BOOL isMatchGame = hasMatchGameClass &&
        (strstr(matchGameClass, "MatchGame") != NULL ||
         IsSubclassOf(remoteCall, currentMatchGame, "MatchGame") ||
         IsSubclassOf(remoteCall, currentMatchGame, "COWGameBase"));

    if (validOffsetPtr(currentMatchGame) && hasMatchGameClass && !isMatchGame) {
        // The dump offset points at another object in this build; repair it with
        // the field that verifiably holds a MatchGame reference. When nothing
        // verifies (renamed classes) the dump offset is kept, so behaviour never
        // gets worse than a plain offset read.
        uint64_t discovered = 0;
        if ([self discoveryDue]) {
            discovered = FindIl2CppFieldMatchingFrom(
                remoteCall, staticFields, 0x0, 0x300, FieldHoldsMatchGame);
        }

        if (discovered != 0) {
            matchGameOffset = discovered;
            gFreeFireMatchGameFieldOffset = discovered;
            currentMatchGame = ReadMemorySafe<uintptr_t>(
                remoteCall, staticFields + discovered);
            [self reportDiagnostics:
                      [NSString stringWithFormat:
                                    @"MatchGame field repaired to 0x%llx",
                                    (unsigned long long)discovered]];
        } else {
            [self reportStage:
                      [NSString stringWithFormat:@"stage 2/6: field 0x%llx "
                                                 @"holds '%s', not MatchGame",
                                                 (unsigned long long)matchGameOffset,
                                                 matchGameClass]];
        }
    }

    if (!validOffsetPtr(currentMatchGame)) {
        [self reportStage:@"stage 2/6: no CurrentMatchGame (lobby)"];
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
        [self reportStage:@"stage 3/6: camera not found"];
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

    // 4. Read Entities from MatchGame.m_ReplicationEntitis
    uint64_t entitiesOffset = gFreeFireEntitiesFieldOffset != 0
                                  ? gFreeFireEntitiesFieldOffset
                                  : kMatchGame_ReplicationEntities;
    uintptr_t repDict = ReadMemorySafe<uintptr_t>(
        remoteCall, currentMatchGame + entitiesOffset);
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
                  [NSString stringWithFormat:@"stage 5/6: replication "
                                             @"dictionary missing (field "
                                             @"0x%llx)",
                                             (unsigned long long)entitiesOffset]];
        @synchronized(self) {
            self.hasValidFrame = NO;
        }
        return;
    }

    int32_t dictCount =
        ReadMemorySafe<int32_t>(remoteCall, repDict + kDictionary_Count);
    if (dictCount <= 0 || dictCount > 10000) {
        [self reportStage:
                  [NSString stringWithFormat:@"stage 5/6: dictionary count "
                                             @"%d out of range",
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
        if (!validOffsetPtr(klass))
            continue;

        uintptr_t namePtr =
            ReadMemorySafe<uintptr_t>(remoteCall, klass + gFreeFireKlassNameOffset);
        if (!validOffsetPtr(namePtr))
            continue;

        char className[64] = {0};
        if (![remoteCall remoteRead:namePtr
                                 to:className
                               size:sizeof(className) - 1])
            continue;

        if (sampleClasses.size() < 96 &&
            sampleClasses.find(className) == std::string::npos) {
            if (!sampleClasses.empty())
                sampleClasses += ",";
            sampleClasses += className;
        }

        if (strncmp(className, "Player", 6) != 0 &&
            !IsSubclassOf(remoteCall, entity, "Player")) {
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
        // Team filtering disabled: show all non-local players\n        // (Player.TeamModeID is a game-mode enum, not a unique team ID)\n        // uint32_t teamID =\n        //     ReadMemorySafe<uint32_t>(remoteCall, entity + kPlayer_TeamModeID);\n        // if (hostTeamID != 0 && teamID == hostTeamID) {\n        //     ++teamSkipped;\n        //     continue;\n        // }\n        Vector3 pos = Vector3::zero();
        if (!ReadEntityPosition(remoteCall, entity, &pos)) {
            ++positionFailures;
            continue;
        }

        // Read Name
        uintptr_t nameStr = ReadMemorySafe<uintptr_t>(
            remoteCall, entity + kPlayer_OriginalNickName);
        NSString *playerName = ReadIl2CppString(remoteCall, nameStr);
        if (playerName.length == 0) {
            playerName = @"Player";
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
        snapshot.onScreen = IsScreenPointInside(screenX, screenY, sw, sh);
        snapshot.distance = distance;

        if (headVisible && footVisible) {
            snapshot.headX = headSX;
            snapshot.headY = headSY;
            snapshot.footX = footSX;
            snapshot.footY = footSY;

            CGFloat boxHeight = fabs(footSY - headSY);
            CGFloat boxWidth = boxHeight * 0.55;
            snapshot.boxX = screenX - boxWidth / 2.0;
            snapshot.boxY = headSY;
            snapshot.boxW = boxWidth;
            snapshot.boxH = boxHeight;
        }

        [entities addObject:snapshot];
    }

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
