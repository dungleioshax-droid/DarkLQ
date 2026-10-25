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
@property(nonatomic, strong) RemoteWebViewOverlay *remoteWebViewOverlay;

- (uint64_t)getFreeFireBaseAddress;
- (void)updateSnapshot:(RemoteCall *)remoteCall;
- (void)showOverlay:(RemoteCall *)remoteCall;

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

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
      uint32_t overlayCooldown = 0;
      while (self.isRunning && self.remoteCall) {
          @autoreleasepool {
              if (self.binaryBase == 0) {
                  self.binaryBase = [self getFreeFireBaseAddress];
                  if (self.binaryBase != 0) {
                      LOG(@"[FreeFire] Binary base: 0x%lx",
                          (unsigned long)self.binaryBase);
                  }
              }

              if (self.binaryBase != 0) {
                  if (self.isESPEnabled) {
                      [self updateSnapshot:self.remoteCall];
                  }

                  if (!self.remoteWebViewOverlay.isOverlayReady && self.staticFieldsAddress != 0) {
                      if (overlayCooldown == 0) {
                          if (!self.remoteWebViewOverlay) {
                              self.remoteWebViewOverlay =
                                  [[RemoteWebViewOverlay alloc]
                                      initWithRemoteCall:self.remoteCall];
                          }
                          if ([self.remoteWebViewOverlay setupBaseOverlay]) {
                              LOG(@"[FreeFire] WKWebView overlay setup done.");
                          } else {
                              overlayCooldown = 200; // Throttle retry to ~2.0s
                          }
                      } else {
                          overlayCooldown--;
                      }
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

    uint64_t scratch_addr = [self.remoteCall trojanMem] + 0x1000;
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
            return imageLoadAddress;
        }

        if ((strcasestr(pathBuf, "freefire") || strstr(pathBuf, "FreeFire")) &&
            freeFireMainBinary == 0) {
            freeFireMainBinary = imageLoadAddress;
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

    uintptr_t candidateTypeInfo = 0;

    // Attempt 1: Decode from GameFacade..cctor (0x5944B44)
    uintptr_t cctorAddr = self.binaryBase + kGameFacade_CCtor;
    candidateTypeInfo = DecodeArm64AdrLdr(remoteCall, cctorAddr);

    // Attempt 2: Decode from CurrentLocalPlayer (0x591BD2C)
    if (!validOffsetPtr(candidateTypeInfo)) {
        uintptr_t clpAddr = self.binaryBase + kGameFacade_CurrentLocalPlayer;
        candidateTypeInfo = DecodeArm64AdrLdr(remoteCall, clpAddr);
    }

    if (!validOffsetPtr(candidateTypeInfo)) {
        return 0;
    }

    // candidateTypeInfo is COW_GameFacade__TypeInfo (an Il2CppClass* / COW_GameFacade_c*)
    // Verify class name at klass + 0x10
    uintptr_t namePtr = ReadMemorySafe<uintptr_t>(remoteCall, candidateTypeInfo + 0x10);
    char nameBuf[32] = {0};
    if (validOffsetPtr(namePtr)) {
        [remoteCall remoteRead:namePtr to:nameBuf size:sizeof(nameBuf) - 1];
    }

    uintptr_t staticFields = 0;
    if (strstr(nameBuf, "GameFacade")) {
        // COW_GameFacade_c* -> static_fields is at offset 0xB8
        staticFields = ReadMemorySafe<uintptr_t>(remoteCall, candidateTypeInfo + 0xB8);
        LOG(@"[FreeFire] Verified GameFacade class (name='%s'), static_fields=0x%lx",
            nameBuf, (unsigned long)staticFields);
    } else {
        // Fallback: check if candidateTypeInfo was already static_fields
        uintptr_t backKlass = candidateTypeInfo >= 0xB8 ? (candidateTypeInfo - 0xB8) : 0;
        uintptr_t backNamePtr = backKlass ? ReadMemorySafe<uintptr_t>(remoteCall, backKlass + 0x10) : 0;
        char backNameBuf[32] = {0};
        if (validOffsetPtr(backNamePtr)) {
            [remoteCall remoteRead:backNamePtr to:backNameBuf size:sizeof(backNameBuf) - 1];
        }
        if (strstr(backNameBuf, "GameFacade")) {
            staticFields = candidateTypeInfo;
            LOG(@"[FreeFire] Candidate was already static_fields: 0x%lx",
                (unsigned long)staticFields);
        } else {
            // Primary fallback: try candidateTypeInfo + 0xB8
            staticFields = ReadMemorySafe<uintptr_t>(remoteCall, candidateTypeInfo + 0xB8);
            if (!validOffsetPtr(staticFields)) {
                staticFields = candidateTypeInfo;
            }
        }
    }

    if (validOffsetPtr(staticFields)) {
        self.staticFieldsAddress = staticFields;
        LOG(@"[FreeFire] Successfully resolved GameFacade static fields: 0x%lx",
            (unsigned long)staticFields);
        return staticFields;
    }

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
        @synchronized(self) {
            self.hasValidFrame = NO;
        }
        return;
    }

    // 2. Read CurrentMatchGame
    // If NULL, the game is in lobby, login screen, or loading screen -> DO NOTHING!
    uintptr_t currentMatchGame = ReadMemorySafe<uintptr_t>(
        remoteCall, staticFields + kGameFacadeStatic_CurrentMatchGame);
    if (!validOffsetPtr(currentMatchGame)) {
        @synchronized(self) {
            self.hasValidFrame = NO;
            [self clearOverlayTargets];
        }
        return;
    }

    // Verify currentMatchGame is actually a COW_MatchGame instance
    uintptr_t matchKlass = ReadMemorySafe<uintptr_t>(remoteCall, currentMatchGame);
    if (!validOffsetPtr(matchKlass)) {
        @synchronized(self) {
            self.hasValidFrame = NO;
            [self clearOverlayTargets];
        }
        return;
    }

    uintptr_t matchClassNamePtr = ReadMemorySafe<uintptr_t>(remoteCall, matchKlass + 0x10);
    char matchClassName[32] = {0};
    if (!validOffsetPtr(matchClassNamePtr) ||
        ![remoteCall remoteRead:matchClassNamePtr to:matchClassName size:sizeof(matchClassName) - 1] ||
        strstr(matchClassName, "MatchGame") == NULL) {
        @synchronized(self) {
            self.hasValidFrame = NO;
            [self clearOverlayTargets];
        }
        return;
    }

    // 3. Resolve Camera and ViewProjection Matrix (100% PURE MEMORY READ)
    uintptr_t camMgr = ReadMemorySafe<uintptr_t>(
        remoteCall, currentMatchGame + kMatchGame_CameraControllerManager);
    if (!validOffsetPtr(camMgr)) {
        @synchronized(self) {
            self.hasValidFrame = NO;
        }
        return;
    }

    uintptr_t camera = ReadMemorySafe<uintptr_t>(
        remoteCall, camMgr + kCameraControllerManager_MainCamera);
    if (!validOffsetPtr(camera)) {
        camera = ReadMemorySafe<uintptr_t>(
            remoteCall, camMgr + kCameraControllerManager_SubCamera);
    }
    if (!validOffsetPtr(camera)) {
        @synchronized(self) {
            self.hasValidFrame = NO;
        }
        return;
    }

    float viewProjection[16] = {};
    float viewMatrix[16] = {};
    if (!ReadCameraVPAndWorldMatrix(remoteCall, camera, viewProjection, viewMatrix)) {
        @synchronized(self) {
            self.hasValidFrame = NO;
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
    uintptr_t repDict = ReadMemorySafe<uintptr_t>(
        remoteCall, currentMatchGame + kMatchGame_ReplicationEntities);
    if (!validOffsetPtr(repDict)) {
        @synchronized(self) {
            self.hasValidFrame = NO;
        }
        return;
    }

    int32_t dictCount =
        ReadMemorySafe<int32_t>(remoteCall, repDict + kDictionary_Count);
    if (dictCount <= 0 || dictCount > 200) {
        @synchronized(self) {
            self.hasValidFrame = NO;
        }
        return;
    }

    uintptr_t entriesArray =
        ReadMemorySafe<uintptr_t>(remoteCall, repDict + kDictionary_Entries);
    if (!validOffsetPtr(entriesArray)) {
        @synchronized(self) {
            self.hasValidFrame = NO;
        }
        return;
    }

    int32_t maxEntries = ReadMemorySafe<int32_t>(
        remoteCall, entriesArray + kArray_Length);
    int32_t loopLimit = std::min(maxEntries, 150);

    CGFloat sw = self.remoteWebViewOverlay.cachedScreenWidth;
    CGFloat sh = self.remoteWebViewOverlay.cachedScreenHeight;
    if (sw <= 0 || sh <= 0) {
        sw = kWidth;
        sh = kHeight;
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
            ReadMemorySafe<uintptr_t>(remoteCall, klass + kIl2CppClass_Name);
        if (!validOffsetPtr(namePtr))
            continue;

        char className[64] = {0};
        if (![remoteCall remoteRead:namePtr
                                 to:className
                               size:sizeof(className) - 1])
            continue;

        if (strncmp(className, "Player", 6) != 0)
            continue;

        // Check Dead State
        uint8_t isDead = ReadMemorySafe<uint8_t>(
            remoteCall, entity + kAttackableEntity_IsDeadFlag);
        if (isDead != 0)
            continue;

        // Check Team (skip teammates)
        uint32_t teamID =
            ReadMemorySafe<uint32_t>(remoteCall, entity + kPlayer_TeamModeID);
        if (hostTeamID != 0 && teamID == hostTeamID)
            continue;

        // Read Position using Pure Memory Reads
        Vector3 pos = Vector3::zero();
        if (!ReadEntityPosition(remoteCall, entity, &pos))
            continue;

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
        if (!visible)
            continue;

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
}

- (void)dealloc {
    [self stopLoop];
}

@end

NS_ASSUME_NONNULL_END
