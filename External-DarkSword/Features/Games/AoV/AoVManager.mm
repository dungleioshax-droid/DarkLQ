//
//  AoVManager.mm
//  External-DarkSword
//
//  Created by Le Tien Dat on 8/6/26.
//

#import "AoVManager.h"
#import "../../../App/Configuration/Macros.h"
#import "../../../App/Notifications/AppNotifications.h"
#import "../../../App/Support/helper.h"
#import "../../Overlay/RemoteWebViewOverlay.h"
#import "../../Unity/VInt3.h"
#import "../../Unity/Vector3.h"
#import "AoVOffset.h"
#import "AoVUtils.h"
#import "Heroes/AoVHeroNameResolver.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <dlfcn.h>

NS_ASSUME_NONNULL_BEGIN

@interface AoVEntitySnapshot : NSObject

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

/// Bounding box in screen coordinates (Player Box ESP).
@property(nonatomic, assign) CGFloat boxX;
@property(nonatomic, assign) CGFloat boxY;
@property(nonatomic, assign) CGFloat boxW;
@property(nonatomic, assign) CGFloat boxH;

@end

@implementation AoVEntitySnapshot
@end

@interface AoVManager ()
@property(nonatomic, assign) BOOL isRunning;
@property(nonatomic, assign) uint64_t unityFrameworkBase;
@property(nonatomic, copy) NSData *viewProjectionData;
@property(nonatomic, copy) NSArray<AoVEntitySnapshot *> *entitySnapshots;
@property(nonatomic, readwrite) BOOL hasValidFrame;
@property(nonatomic, assign) BOOL cameraHeightApplyPending;
@property(nonatomic, assign) BOOL cameraHeightApplyInFlight;
@property(nonatomic, assign) NSInteger cameraHeightApplyCooldownFrames;
@property(nonatomic, assign) BOOL isCameraBattleActive;
@property(nonatomic, assign) uint64_t cameraWorkGeneration;
@property(nonatomic, assign) NSTimeInterval nextBattlePollTime;
@property(nonatomic, assign) NSTimeInterval nextHackMapApplyTime;
@property(nonatomic, strong) NSMutableSet<NSNumber *> *hackMapMarkers;
@property(nonatomic, strong) RemoteWebViewOverlay *remoteWebViewOverlay;

- (void)notifyCameraHeightChangedWithRemoteCall:(RemoteCall *)remoteCall
                                   cameraSystem:(uintptr_t)cameraSystem;
- (BOOL)shouldRunCameraWorkForCall:(RemoteCall *)remoteCall
                  cameraGeneration:(uint64_t)cameraGeneration;
- (void)refreshCameraBattleActivityIfNeededForRemoteCall:
    (RemoteCall *)remoteCall;
- (void)updateHackMapWithRemoteCall:(RemoteCall *)remoteCall;
- (void)applyHackMapToActorList:(uintptr_t)actors
                          limit:(int)limit
                       hostCamp:(int)hostCamp
                     remoteCall:(RemoteCall *)remoteCall
                           kind:(const char *)kind;
- (void)restoreHackMapMarkersWithRemoteCall:(RemoteCall *)remoteCall;
@end

static const NSInteger kCameraHeightApplyCooldownFrames = 30;
static const NSTimeInterval kBattlePollInterval = 0.5;
static const NSTimeInterval kHackMapApplyInterval = 1;
static constexpr int kMaxHackMapHeroes = 20;
static constexpr int kMaxHackMapWorldActors = 128;

@implementation AoVManager

- (instancetype)initWithRemoteCall:(RemoteCall *)remoteCall {
    self = [super init];
    if (self) {
        [[AoVHeroNameResolver sharedResolver] loadFromRemote];
        _remoteCall = remoteCall;
        _cameraHeight = -1.0f;
        _isESPEnabled = YES;
        _isHackMapEnabled = NO;
        _showsLine = YES;
        _showsBox = YES;
        _showsHealth = YES;
        _showsName = YES;
        _showsDistance = YES;
        _isRunning = NO;
        _entitySnapshots = @[];
        _viewProjectionData = [NSData data];
        _cameraHeightApplyPending = NO;
        _cameraHeightApplyInFlight = NO;
        _cameraHeightApplyCooldownFrames = 0;
        _isCameraBattleActive = NO;
        _cameraWorkGeneration = 0;
        _nextBattlePollTime = 0.0;
        _nextHackMapApplyTime = 0.0;
        _hackMapMarkers = [NSMutableSet set];

        [self registerNotification];
    }
    return self;
}

- (uint64_t)getRealOffset:(uint64_t)offset {
    return self.unityFrameworkBase + offset;
}

- (uint64_t)getRealOffsetWithBinary:(uint64_t)baseBinary
                             offset:(uint64_t)offset {
    return baseBinary + offset;
}

- (void)runLoop {
    if (!self.remoteCall || self.isRunning)
        return;

    self.isRunning = YES;
    @synchronized(self) {
        self.isCameraBattleActive = NO;
        self.cameraWorkGeneration++;
        self.nextBattlePollTime = 0.0;
    }
    LOG(@"[AoV] Starting external snapshot loop...");
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
      while (self.isRunning && self.remoteCall) {
          @autoreleasepool {
              if (self.unityFrameworkBase == 0) {
                  self.unityFrameworkBase = [self getUnityFrameworkBaseAddress];
                  if (self.unityFrameworkBase != 0)
                      LOG(@"[AoV] UnityFramework base: 0x%llx",
                          self.unityFrameworkBase);
              }
              if (self.unityFrameworkBase != 0) {
                  if (!self.remoteWebViewOverlay.isOverlayReady) {
                      if (!self.remoteWebViewOverlay) {
                          self.remoteWebViewOverlay =
                              [[RemoteWebViewOverlay alloc]
                                  initWithRemoteCall:self.remoteCall];
                      }
                      if ([self.remoteWebViewOverlay setupBaseOverlay]) {
                          LOG(@"[AoV] WKWebView overlay setup done.");
                      } else {
                          LOG(@"[AoV] WKWebView overlay setup failed, will "
                              @"retry.");
                      }
                  }

                  if (self.isESPEnabled) {
                      [self updateSnapshot:self.remoteCall];
                  }
                  [self updateCameraHeight:self.remoteCall];
                  [self updateHackMapWithRemoteCall:self.remoteCall];
              }
          }
          usleep(10000);
      }
      LOG(@"[AoV] Snapshot loop stopped.");
    });
}

- (uintptr_t)fetchCameraSystem:(RemoteCall *)remoteCall {
    if (!remoteCall || self.unityFrameworkBase == 0)
        return 0;

    return MonoSingleton_CameraSystem(remoteCall, self.unityFrameworkBase);
}

- (uintptr_t)fetchActorManager:(RemoteCall *)remoteCall {
    if (!self.actorManager) {
        self.actorManager =
            GetActorManager(remoteCall, self.unityFrameworkBase);
    }

    return self.actorManager;
}

- (void)stopLoop {
    self.isRunning = NO;
    @synchronized(self) {
        self.isCameraBattleActive = NO;
        self.cameraWorkGeneration++;
        self.nextBattlePollTime = 0.0;
        self.nextHackMapApplyTime = 0.0;
        [self.hackMapMarkers removeAllObjects];
        self.cameraHeightApplyPending = NO;
        self.cameraHeightApplyCooldownFrames = 0;
        self.entitySnapshots = @[];
        self.viewProjectionData = [NSData data];
        self.hasValidFrame = NO;
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

- (void)updateCameraHeight:(RemoteCall *)remoteCall {
    [self refreshCameraBattleActivityIfNeededForRemoteCall:remoteCall];

    @synchronized(self) {
        if (!self.isCameraBattleActive) {
            self.cameraSystem = 0;
            self.cameraHeightApplyPending = NO;
            self.cameraHeightApplyCooldownFrames = 0;
            return;
        }
    }

    uintptr_t cameraSystem = [self fetchCameraSystem:remoteCall];

    if (!checkValidPointer64bits(cameraSystem)) {
        self.cameraSystem = 0;
        @synchronized(self) {
            self.cameraHeightApplyPending = NO;
            self.cameraHeightApplyCooldownFrames = 0;
        }
        return;
    }

    BOOL cameraSystemChanged = self.cameraSystem != cameraSystem;
    self.cameraSystem = cameraSystem;

    float targetZoom = (float)self.cameraHeight;
    if (std::isfinite(targetZoom) && targetZoom >= 1.0f) {
        uintptr_t zoomRateAddress =
            cameraSystem + kCameraSystem_ZoomRateFromAge;
        float currentZoom = 0.0f;
        BOOL didReadZoom = [remoteCall remoteRead:zoomRateAddress
                                               to:&currentZoom
                                             size:sizeof(currentZoom)];
        BOOL hasValidCurrentZoom = didReadZoom && std::isfinite(currentZoom);
        BOOL zoomValueDiffers =
            hasValidCurrentZoom && fabsf(currentZoom - targetZoom) > 0.01f;

        BOOL didWriteCameraHeight = NO;
        if (!hasValidCurrentZoom || zoomValueDiffers || cameraSystemChanged) {
            WriteMemorySafe<float>(remoteCall, zoomRateAddress, targetZoom);
            didWriteCameraHeight = YES;
        }

        BOOL shouldNotifyCameraHeightChanged = NO;
        @synchronized(self) {
            if (self.cameraHeightApplyCooldownFrames > 0) {
                self.cameraHeightApplyCooldownFrames--;
            }

            if (didWriteCameraHeight || cameraSystemChanged) {
                self.cameraHeightApplyPending = YES;
            }

            BOOL isZoomSettled = hasValidCurrentZoom && !zoomValueDiffers;
            if (self.cameraHeightApplyPending && isZoomSettled &&
                self.cameraHeightApplyCooldownFrames <= 0 &&
                !self.cameraHeightApplyInFlight) {
                shouldNotifyCameraHeightChanged = YES;
                self.cameraHeightApplyInFlight = YES;
                self.cameraHeightApplyCooldownFrames =
                    kCameraHeightApplyCooldownFrames;
                self.cameraHeightApplyPending = NO;
            }
        }

        if (shouldNotifyCameraHeightChanged) {
            [self notifyCameraHeightChangedWithRemoteCall:remoteCall
                                             cameraSystem:cameraSystem];
        }
    }
}

- (void)refreshCameraBattleActivityIfNeededForRemoteCall:
    (RemoteCall *)remoteCall {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    @synchronized(self) {
        if (now < self.nextBattlePollTime)
            return;
        self.nextBattlePollTime = now + kBattlePollInterval;
    }

    BOOL isBattleActive = IsBattleActive(remoteCall, self.unityFrameworkBase);
    BOOL didChange = NO;
    @synchronized(self) {
        if (!self.isRunning || self.remoteCall != remoteCall)
            return;

        didChange = self.isCameraBattleActive != isBattleActive;
        self.isCameraBattleActive = isBattleActive;
        if (!isBattleActive) {
            self.cameraHeightApplyPending = NO;
            self.cameraHeightApplyCooldownFrames = 0;
            if (didChange)
                self.cameraWorkGeneration++;
        }
    }

    if (didChange) {
        LOG(@"[AoV] Camera writes %@ by battle gate.",
            isBattleActive ? @"enabled" : @"disabled");
    }
}

- (void)updateHackMapWithRemoteCall:(RemoteCall *)remoteCall {
    if (!remoteCall)
        return;

    BOOL isBattleActive = NO;
    @synchronized(self) {
        isBattleActive = self.isCameraBattleActive;
    }
    if (!isBattleActive) {
        @synchronized(self) {
            [self.hackMapMarkers removeAllObjects];
        }
        return;
    }

    if (!self.isHackMapEnabled) {
        [self restoreHackMapMarkersWithRemoteCall:remoteCall];
        return;
    }

    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    @synchronized(self) {
        if (now < self.nextHackMapApplyTime)
            return;
        self.nextHackMapApplyTime = now + kHackMapApplyInterval;
    }

    uintptr_t logicManager =
        GetLGameActorManager(remoteCall, self.unityFrameworkBase);
    if (!validOffsetPtr(logicManager))
        return;

    int hostCamp = GetHostCamp(remoteCall, self.unityFrameworkBase);
    if (hostCamp == 0)
        return;

    uintptr_t heroes = ReadMemorySafe<uintptr_t>(
        remoteCall, logicManager + kLGameActorMgr_HeroActors);
    uintptr_t monsters = ReadMemorySafe<uintptr_t>(
        remoteCall, logicManager + kLGameActorMgr_MonsterActors);
    uintptr_t soldiers = ReadMemorySafe<uintptr_t>(
        remoteCall, logicManager + kLGameActorMgr_SoldierActors);

    [self applyHackMapToActorList:heroes
                            limit:kMaxHackMapHeroes
                         hostCamp:hostCamp
                       remoteCall:remoteCall
                             kind:"hero"];
    [self applyHackMapToActorList:monsters
                            limit:kMaxHackMapWorldActors
                         hostCamp:hostCamp
                       remoteCall:remoteCall
                             kind:"monster"];
    [self applyHackMapToActorList:soldiers
                            limit:kMaxHackMapWorldActors
                         hostCamp:hostCamp
                       remoteCall:remoteCall
                             kind:"soldier"];
}

- (void)applyHackMapToActorList:(uintptr_t)actors
                          limit:(int)limit
                       hostCamp:(int)hostCamp
                     remoteCall:(RemoteCall *)remoteCall
                           kind:(const char *)kind {
    int actorCount = std::min(ReadRemoteListCount(remoteCall, actors), limit);
    for (int index = 0; index < actorCount; ++index) {
        uintptr_t actor = ReadRemotePoolHandleObject(remoteCall, actors, index);
        if (!validOffsetPtr(actor))
            continue;

        int actorCamp =
            ReadMemorySafe<int>(remoteCall, actor + kLActorRoot_Camp);
        if (actorCamp == hostCamp)
            continue;

        uintptr_t control = ReadMemorySafe<uintptr_t>(
            remoteCall, actor + kLActorRoot_ActorControl);
        bool dead = validOffsetPtr(control) &&
                    ReadMemorySafe<int>(remoteCall,
                                        control + kLObjWrapper_DeadState) == 1;
        if (dead)
            continue;

        uintptr_t horizon = ReadMemorySafe<uintptr_t>(
            remoteCall, actor + kLActorRoot_HorizonMarker);
        uintptr_t marker =
            FindHorizonCampMarkerForCamp(remoteCall, horizon, hostCamp);
        if (!validOffsetPtr(marker))
            continue;

        uint8_t forceShow = ReadMemorySafe<uint8_t>(
            remoteCall, marker + kHorizonCampMarker_IsForceShow);
        if (forceShow != 0)
            continue;

        bool didForceShow = WriteMemorySafe<uint8_t>(
            remoteCall, marker + kHorizonCampMarker_IsForceShow, 1);
        bool didScheduleRefresh =
            didForceShow &&
            WriteMemorySafe<int>(remoteCall,
                                 marker + kHorizonCampMarker_FadingCounter, 1);
        if (!didScheduleRefresh)
            continue;

        @synchronized(self) {
            [self.hackMapMarkers addObject:@(marker)];
        }
        LOG(@"[HackMap] reveal %s=0x%lx marker=0x%lx hostCamp=%d", kind, actor,
            marker, hostCamp);
    }
}

- (void)restoreHackMapMarkersWithRemoteCall:(RemoteCall *)remoteCall {
    NSArray<NSNumber *> *markers = nil;
    @synchronized(self) {
        if (self.hackMapMarkers.count == 0)
            return;
        markers = self.hackMapMarkers.allObjects;
        [self.hackMapMarkers removeAllObjects];
    }

    for (NSNumber *value in markers) {
        uintptr_t marker = (uintptr_t)value.unsignedLongLongValue;
        if (!validOffsetPtr(marker))
            continue;

        uint8_t forceShow = ReadMemorySafe<uint8_t>(
            remoteCall, marker + kHorizonCampMarker_IsForceShow);
        if (forceShow == 0)
            continue;

        bool didClear = WriteMemorySafe<uint8_t>(
            remoteCall, marker + kHorizonCampMarker_IsForceShow, 0);
        if (didClear) {
            WriteMemorySafe<int>(remoteCall,
                                 marker + kHorizonCampMarker_FadingCounter, 1);
        }
    }
}

- (BOOL)shouldRunCameraWorkForCall:(RemoteCall *)remoteCall
                  cameraGeneration:(uint64_t)cameraGeneration {
    @synchronized(self) {
        return self.isRunning && self.remoteCall == remoteCall &&
               self.isCameraBattleActive &&
               self.cameraWorkGeneration == cameraGeneration;
    }
}

- (void)showOverlay:(RemoteCall *)remoteCall {
    if (!self.remoteWebViewOverlay.isOverlayReady ||
        !self.remoteWebViewOverlay) {
        return;
    }

    NSMutableArray<NSDictionary *> *overlayTargets = [NSMutableArray array];

    for (AoVEntitySnapshot *entity in self.entitySnapshots) {

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
    uintptr_t cameraSystem =
        MonoSingleton_CameraSystem(remoteCall, self.unityFrameworkBase);
    uintptr_t actorManager =
        GetActorManager(remoteCall, self.unityFrameworkBase);

    if (!checkValidPointer64bits(cameraSystem) ||
        !checkValidPointer64bits(actorManager)) {
        @synchronized(self) {
            self.hasValidFrame = NO;
        }
        return;
    }

    float viewProjection[16] = {};
    if (!BuildMobaVPMatrix(remoteCall, cameraSystem, viewProjection)) {
        @synchronized(self) {
            self.hasValidFrame = NO;
        }
        return;
    }

    uintptr_t logicManager =
        GetLGameActorManager(remoteCall, self.unityFrameworkBase);
    uintptr_t visualHeroes = ReadMemorySafe<uintptr_t>(
        remoteCall, actorManager + kActorManager_HeroActors);
    uintptr_t logicHeroes =
        validOffsetPtr(logicManager)
            ? ReadMemorySafe<uintptr_t>(
                  remoteCall, logicManager + kLGameActorMgr_HeroActors)
            : 0;
    int visualCount = ReadRemoteListCount(remoteCall, visualHeroes);
    int logicCount = ReadRemoteListCount(remoteCall, logicHeroes);
    int loopCount = std::min(visualCount, 20);

    int hostCamp = GetHostCamp(remoteCall, self.unityFrameworkBase);
    uintptr_t hostCaptain = GetHostCaptain(remoteCall, self.unityFrameworkBase);
    if (hostCamp == 0 && validOffsetPtr(hostCaptain)) {
        hostCamp =
            ReadMemorySafe<int>(remoteCall, hostCaptain + kActorLinker_Camp);
    }
    Vector3 hostPosition = validOffsetPtr(hostCaptain)
                               ? ReadActorPosition(remoteCall, hostCaptain, 0)
                               : Vector3::zero();
    BOOL hasHostPosition = validOffsetPtr(hostCaptain);

    NSMutableArray<AoVEntitySnapshot *> *entities =
        [NSMutableArray arrayWithCapacity:(NSUInteger)std::max(loopCount, 0)];
    AoVHeroNameResolver *heroNameResolver =
        [AoVHeroNameResolver sharedResolver];
    for (int i = 0; i < loopCount; ++i) {
        uintptr_t actor =
            ReadRemotePoolHandleObject(remoteCall, visualHeroes, i);
        if (!validOffsetPtr(actor))
            continue;

        uintptr_t logicActor =
            i < logicCount
                ? ReadRemotePoolHandleObject(remoteCall, logicHeroes, i)
                : 0;
        bool isHost =
            actor == hostCaptain ||
            ReadMemorySafe<uint8_t>(remoteCall,
                                    actor + kActorLinker_IsHostControlled) != 0;
        int camp = ReadMemorySafe<int>(remoteCall, actor + kActorLinker_Camp);
        if (isHost || (hostCamp != 0 && camp == hostCamp))
            continue;

        uintptr_t actorControl = ReadMemorySafe<uintptr_t>(
            remoteCall, actor + kActorLinker_ActorControl);
        bool dead =
            validOffsetPtr(actorControl) &&
            ReadMemorySafe<int>(remoteCall,
                                actorControl + kObjLinkerWrapper_Behavior) == 1;
        if (!dead && validOffsetPtr(logicActor)) {
            uintptr_t logicControl = ReadMemorySafe<uintptr_t>(
                remoteCall, logicActor + kLActorRoot_ActorControl);
            dead = validOffsetPtr(logicControl) &&
                   ReadMemorySafe<int>(
                       remoteCall, logicControl + kLObjWrapper_DeadState) == 1;
        }
        if (dead)
            continue;

        int health = 0;
        int maxHealth = 0;
        uintptr_t valueComponent = ReadMemorySafe<uintptr_t>(
            remoteCall, actor + kActorLinker_ValueComponent);
        if (validOffsetPtr(valueComponent)) {
            health = ReadMemorySafe<int>(remoteCall,
                                         valueComponent + kValueLinker_ActorHp);
            maxHealth = ReadMemorySafe<int>(
                remoteCall, valueComponent + kValueLinker_ActorHpTotal);
        }
        if (health <= 0 && validOffsetPtr(logicActor)) {
            uintptr_t logicValue = ReadMemorySafe<uintptr_t>(
                remoteCall, logicActor + kLActorRoot_ValueComponent);
            if (validOffsetPtr(logicValue)) {
                health = ReadCrypticInt32(
                    remoteCall, logicValue + kValueProperty_CurrentHp);
            }
        }
        if (health <= 0)
            continue;
        if (maxHealth < health)
            maxHealth = health;

        uintptr_t config = ReadMemorySafe<uintptr_t>(
            remoteCall, actor + kActorLinker_ObjLinker);
        int heroId = validOffsetPtr(config)
                         ? ReadMemorySafe<int>(remoteCall,
                                               config + kActorConfig_ConfigID)
                         : 0;

        AoVEntitySnapshot *entity = [AoVEntitySnapshot new];
        entity.actorAddress = actor;
        entity.position = ReadActorPosition(remoteCall, actor, logicActor);
        entity.health = health;
        entity.maxHealth = std::max(maxHealth, 1);
        entity.name = [heroNameResolver heroNameForID:heroId];
        entity.distance = hasHostPosition
                              ? Vector3::Distance(hostPosition, entity.position)
                              : 0.0f;

        CGFloat screenX = 0.0;
        CGFloat screenY = 0.0;

        CGFloat sw = self.remoteWebViewOverlay.cachedScreenWidth;
        CGFloat sh = self.remoteWebViewOverlay.cachedScreenHeight;
        if (sw <= 0 || sh <= 0) {
            sw = kWidth;
            sh = kHeight;
        }

        BOOL visible = ProjectToOverlayPoint(entity.position, viewProjection,
                                             sw, sh, &screenX, &screenY);
        if (!visible)
            continue;

        entity.visible = YES;
        entity.screenX = screenX;
        entity.screenY = screenY;
        entity.onScreen = IsScreenPointInside(screenX, screenY, sw, sh);

        static const float kActorHeightWorld = 2.0f;
        static const float kFootPaddingWorld = 0.08f;
        static const float kMaxCameraHeight = 10.0f;

        Vector3 headWorld =
            Vector3(entity.position.x, entity.position.y + kActorHeightWorld,
                    entity.position.z);
        Vector3 footWorld =
            Vector3(entity.position.x, entity.position.y + kFootPaddingWorld,
                    entity.position.z);

        CGFloat headSX = 0, headSY = 0, footSX = 0, footSY = 0;
        BOOL headOk = ProjectToOverlayPoint(headWorld, viewProjection, sw, sh,
                                            &headSX, &headSY);
        BOOL footOk = ProjectToOverlayPoint(footWorld, viewProjection, sw, sh,
                                            &footSX, &footSY);

        if (headOk && footOk) {
            entity.headX = headSX;
            entity.headY = headSY;
            entity.footX = footSX;
            entity.footY = footSY;

            CGFloat boxHeight = fabs(footSY - headSY);
            CGFloat boxWidth = boxHeight * 0.6;
            CGFloat camH = (CGFloat)self.cameraHeight;
            if (camH < 1.0)
                camH = 1.0;
            CGFloat boxPaddingY = 3.0 - (camH / kMaxCameraHeight) * 3.0;
            if (boxPaddingY < 0.0)
                boxPaddingY = 0.0;

            entity.boxX = screenX - boxWidth / 2.0;
            entity.boxY = headSY - boxPaddingY;
            entity.boxW = boxWidth;
            entity.boxH = boxHeight + boxPaddingY * 2.0;
        }

        [entities addObject:entity];
    }

    @synchronized(self) {
        self.viewProjectionData = [NSData dataWithBytes:viewProjection
                                                 length:sizeof(viewProjection)];
        self.entitySnapshots = [entities copy];
        self.hasValidFrame = YES;

        [self showOverlay:self.remoteCall];
    }
}

- (uint64_t)getUnityFrameworkBaseAddress {
    uint64_t task_info_addr = (uint64_t)dlsym(RTLD_DEFAULT, "task_info");
    uint64_t mach_task_self_addr =
        (uint64_t)dlsym(RTLD_DEFAULT, "mach_task_self_");

    if (!task_info_addr || !mach_task_self_addr) {
        return 0;
    }

    uint32_t target_mach_task_self = 0;
    // Get mach_task_self of process need get
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

    /*
    Get info a task (process)
    flavor = 17 (TASK_DYLD_INFO) => Get pointer refer to image dyld table of a
    process

    kern_return_t task_info
                  (task_t task,
                  task_flavor_t flavor,
                  task_info_t task_info,
                  mach_msg_type_number_t task_info_count);
    */
    uint64_t args[4] = {
        target_mach_task_self, // x0
        TASK_DYLD_INFO,        // x1 = 17 => Get info dylib loaded
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

    /*
    task_info (type task_info_t) is task_dyld_info

    struct task_dyld_info {
        uint64_t all_image_info_addr;       // +0x0
        uint64_t all_image_info_size;       // +0x8
        uint32_t all_image_info_format;     // +0x10
    }
    */
    uint64_t all_image_info_addr = 0;
    if (![self.remoteCall remoteRead:(scratch_addr + 8)
                                  to:&all_image_info_addr
                                size:sizeof(all_image_info_addr)] ||
        !validOffsetPtr(all_image_info_addr)) {
        return 0;
    }

    /*
    Read all_image_info_addr + 0x0 => address of dyld_all_image_infos

    struct dyld_all_image_infos {
     uint32_t version;                // +0x00
     uint32_t infoArrayCount;         // +0x04
     uint64_t infoArray;              // +0x08, array of dyld_image_info
     ...
    };

    struct dyld_image_info {
     uint64_t imageLoadAddress;    // +0x00
     uint64_t imageFilePath;       // +0x08
     uint64_t imageFileModDate;    // +0x10
    };

    dyld_image_info => 8 (uint64_t) * 3 = 24 = 0x18 (size of object type
    dyld_image_info)
    */
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
    }

    return 0;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// MARK: Notification

- (void)registerNotification {
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(cameraHeightDidChange)
               name:CameraHeightDidChange
             object:nil];
}

- (void)notifyCameraHeightChangedWithRemoteCall:(RemoteCall *)remoteCall
                                   cameraSystem:(uintptr_t)cameraSystem {
    uint64_t fn = [self getRealOffset:kOnCameraHeightChanged];

    if (!remoteCall || !checkValidPointer64bits(fn) ||
        !checkValidPointer64bits(cameraSystem)) {
        @synchronized(self) {
            self.cameraHeightApplyInFlight = NO;
        }
        return;
    }

    uint64_t cameraGeneration = 0;
    uint64_t unityFrameworkBase = 0;
    @synchronized(self) {
        if (!self.isCameraBattleActive) {
            self.cameraHeightApplyInFlight = NO;
            return;
        }
        cameraGeneration = self.cameraWorkGeneration;
        unityFrameworkBase = self.unityFrameworkBase;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      @try {
          if ([self shouldRunCameraWorkForCall:remoteCall
                              cameraGeneration:cameraGeneration] &&
              IsBattleActive(remoteCall, unityFrameworkBase) &&
              [self fetchCameraSystem:remoteCall] == cameraSystem) {
              uint64_t args[1] = {cameraSystem};
              [remoteCall
                  doRemoteCallStableWithTimeout:5
                                   functionName:(char *)"OnCameraHeightChanged"
                                functionPointer:(void *)fn
                                           args:args
                                       argCount:ARRAY_LENGTH(args)];
          }
      } @finally {
          @synchronized(self) {
              self.cameraHeightApplyInFlight = NO;
          }
      }
    });
}

- (void)cameraHeightDidChange {
    @synchronized(self) {
        if (!self.isCameraBattleActive)
            return;
        self.cameraHeightApplyPending = YES;
        self.cameraHeightApplyCooldownFrames = 0;
    }
}

@end

NS_ASSUME_NONNULL_END
