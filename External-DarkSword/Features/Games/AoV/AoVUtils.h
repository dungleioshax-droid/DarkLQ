//
//  Utils.h
//  External-DarkSword
//
//  Created by Le Tien Dat on 8/14/26.
//

#import "../../../App/Configuration/Macros.h"
#import "../../../App/Support/helper.h"
#import "../../../Core/TaskRop/RemoteCall.h"
#import "AoVOffset.h"

static inline uintptr_t ReadSingletonInstance(RemoteCall *remoteCall,
                                              uint64_t base,
                                              uint64_t methodInfoRva) {
    if (!base || !remoteCall)
        return 0;

    uintptr_t mi = ReadMemorySafe<uintptr_t>(remoteCall, base + methodInfoRva);
    if (!validOffsetPtr(mi))
        return 0;

    uintptr_t methodKlass =
        ReadMemorySafe<uintptr_t>(remoteCall, mi + kMethodInfo_Klass);
    if (!validOffsetPtr(methodKlass))
        return 0;

    uintptr_t singletonKlass = methodKlass;
    uintptr_t rgctx = ReadMemorySafe<uintptr_t>(
        remoteCall, methodKlass + kIl2CppClass_RgctxData);
    if (validOffsetPtr(rgctx)) {
        uintptr_t closed =
            ReadMemorySafe<uintptr_t>(remoteCall, rgctx + kRgctx_ClosedClass);
        if (validOffsetPtr(closed))
            singletonKlass = closed;
    }

    uintptr_t staticFields = ReadMemorySafe<uintptr_t>(
        remoteCall, singletonKlass + kIl2CppClass_StaticFields);
    if (!validOffsetPtr(staticFields))

        return 0;

    return ReadMemorySafe<uintptr_t>(remoteCall, staticFields); // s_instance
}

static inline uintptr_t Singleton_CBattleSystem(RemoteCall *remoteCall,
                                                uint64_t base) {
    return ReadSingletonInstance(remoteCall, base, kCBattleSystem);
}

static inline uintptr_t Singleton_BattleLogic(RemoteCall *remoteCall,
                                              uint64_t base) {
    return ReadSingletonInstance(remoteCall, base, kBattleLogic);
}

static inline uintptr_t
Singleton_CHeroSelectNormalSystem(RemoteCall *remoteCall, uint64_t base) {
    return ReadSingletonInstance(remoteCall, base, kCHeroSelectNormalSystem);
}

static inline uintptr_t Singleton_CHeroSelectBaseSystem(RemoteCall *remoteCall,
                                                        uint64_t base) {
    return ReadSingletonInstance(remoteCall, base, kCHeroSelectBaseSystem);
}

static inline uintptr_t Singleton_CRoleInfoManager(RemoteCall *remoteCall,
                                                   uint64_t base) {
    return ReadSingletonInstance(remoteCall, base, kCRoleInfoManager);
}

static inline uintptr_t Singleton_CLadderSystem(RemoteCall *remoteCall,
                                                uint64_t base) {
    return ReadSingletonInstance(remoteCall, base, kCLadderSystem);
}

static inline uintptr_t MonoSingleton_CameraSystem(RemoteCall *remoteCall,
                                                   uint64_t base) {
    return ReadSingletonInstance(remoteCall, base, kCameraSystem);
}

static inline uintptr_t MonoSingleton_GameFramework(RemoteCall *remoteCall,
                                                    uint64_t base) {
    return ReadSingletonInstance(remoteCall, base, kGameFramework);
}

static inline uintptr_t Singleton_LLogicCore(RemoteCall *remoteCall,
                                             uint64_t base) {
    return ReadSingletonInstance(remoteCall, base, kLLogicCore);
}

static inline uintptr_t MonoSingleton_KyriosFramework(RemoteCall *remoteCall,
                                                      uint64_t base) {
    return ReadSingletonInstance(remoteCall, base, kAdrKyriosFramework);
}

static inline int ReadRemoteListCount(RemoteCall *remoteCall, uintptr_t list) {
    if (!validOffsetPtr(list))
        return 0;
    int count = ReadMemorySafe<int>(remoteCall, list + kList_Size);

    return count >= 0 && count <= 256 ? count : 0;
}

static inline uintptr_t ReadRemoteListObject(RemoteCall *remoteCall,
                                             uintptr_t list, int index) {
    int count = ReadRemoteListCount(remoteCall, list);
    if (index < 0 || index >= count)
        return 0;

    uintptr_t items = ReadMemorySafe<uintptr_t>(remoteCall, list + kList_Items);
    if (!validOffsetPtr(items))
        return 0;

    uintptr_t length =
        ReadMemorySafe<uintptr_t>(remoteCall, items + kArray_Length);
    if ((uintptr_t)index >= length)
        return 0;

    return ReadMemorySafe<uintptr_t>(remoteCall,
                                     items + kArray_Items +
                                         (uintptr_t)index * sizeof(uintptr_t));
}

static inline int ReadRemoteArrayCount(RemoteCall *remoteCall,
                                       uintptr_t array) {
    if (!validOffsetPtr(array))
        return 0;

    uintptr_t length =
        ReadMemorySafe<uintptr_t>(remoteCall, array + kArray_Length);
    return length <= 256 ? (int)length : 0;
}

static inline uintptr_t FindHorizonCampMarkerForCamp(RemoteCall *remoteCall,
                                                     uintptr_t horizonMarker,
                                                     int camp) {
    if (!validOffsetPtr(horizonMarker))
        return 0;

    uintptr_t markers = ReadMemorySafe<uintptr_t>(
        remoteCall, horizonMarker + kHorizonMarker_CampMarkers);
    int markerCount = ReadRemoteArrayCount(remoteCall, markers);
    for (int index = 0; index < markerCount; ++index) {
        uintptr_t marker = ReadMemorySafe<uintptr_t>(
            remoteCall,
            markers + kArray_Items + (uintptr_t)index * sizeof(uintptr_t));
        if (validOffsetPtr(marker) &&
            ReadMemorySafe<int>(remoteCall, marker + kHorizonCampMarker_Camp) ==
                camp) {
            return marker;
        }
    }

    return 0;
}

static inline uintptr_t ReadRemotePoolHandleObject(RemoteCall *remoteCall,
                                                   uintptr_t list, int index) {
    int count = ReadRemoteListCount(remoteCall, list);
    if (index < 0 || index >= count)
        return 0;

    uintptr_t items = ReadMemorySafe<uintptr_t>(remoteCall, list + kList_Items);
    if (!validOffsetPtr(items))
        return 0;

    uintptr_t length =
        ReadMemorySafe<uintptr_t>(remoteCall, items + kArray_Length);
    if ((uintptr_t)index >= length)
        return 0;

    return ReadMemorySafe<uintptr_t>(remoteCall, items + kArray_Items +
                                                     (uintptr_t)index *
                                                         kPoolObjHandle_Size +
                                                     kPoolObjHandle_Object);
}

static inline uintptr_t GetActorManager(RemoteCall *remoteCall, uint64_t base) {
    uintptr_t framework = MonoSingleton_KyriosFramework(remoteCall, base);
    if (!validOffsetPtr(framework))
        return 0;

    return ReadMemorySafe<uintptr_t>(remoteCall,
                                     framework + kKyriosFramework_ActorManager);
}

static inline uintptr_t GetHostLogic(RemoteCall *remoteCall, uint64_t base) {
    uintptr_t framework = MonoSingleton_KyriosFramework(remoteCall, base);
    if (!validOffsetPtr(framework))
        return 0;

    return ReadMemorySafe<uintptr_t>(remoteCall,
                                     framework + kKyriosFramework_HostLogic);
}

static inline uintptr_t GetHostPlayer(RemoteCall *remoteCall, uint64_t base) {
    uintptr_t hostLogic = GetHostLogic(remoteCall, base);
    if (!validOffsetPtr(hostLogic))
        return 0;

    return ReadMemorySafe<uintptr_t>(remoteCall,
                                     hostLogic + kVHostLogic_HostPlayer);
}

static inline int GetHostCamp(RemoteCall *remoteCall, uint64_t base) {
    uintptr_t hostPlayer = GetHostPlayer(remoteCall, base);

    return validOffsetPtr(hostPlayer)
               ? ReadMemorySafe<int>(remoteCall,
                                     hostPlayer + kPlayer_PlayerCamp)
               : 0;
}

static inline uintptr_t GetHostCaptain(RemoteCall *remoteCall, uint64_t base) {
    uintptr_t hostPlayer = GetHostPlayer(remoteCall, base);
    if (!validOffsetPtr(hostPlayer))
        return 0;

    return ReadMemorySafe<uintptr_t>(
        remoteCall, hostPlayer + kPlayer_CaptainLinker + kPoolObjHandle_Object);
}

static inline int ReadCrypticInt32(RemoteCall *remoteCall, uintptr_t address) {
    int key = ReadMemorySafe<int>(remoteCall, address);
    int value = ReadMemorySafe<int>(remoteCall, address + sizeof(int));

    return key ^ value;
}

static inline uintptr_t ReadGameActorManagerFromDesk(RemoteCall *remoteCall,
                                                     uintptr_t desk) {
    if (!validOffsetPtr(desk))
        return 0;

    uintptr_t battleLogic = ReadMemorySafe<uintptr_t>(
        remoteCall, desk + kLDeskBase_DeskBattleLogic);
    if (!validOffsetPtr(battleLogic))
        return 0;

    return ReadMemorySafe<uintptr_t>(remoteCall,
                                     battleLogic + kLBattleLogic_GameActorMgr);
}

static inline bool ReadBattleSystemIsInBattle(RemoteCall *remoteCall,
                                              uint64_t base) {
    uintptr_t battleSystem = Singleton_CBattleSystem(remoteCall, base);
    if (!validOffsetPtr(battleSystem))
        return false;

    return ReadMemorySafe<uint8_t>(
               remoteCall, battleSystem + kCBattleSystem_IsInBattle) == 1;
}

static inline bool IsBattleActive(RemoteCall *remoteCall, uint64_t base) {
    return ReadBattleSystemIsInBattle(remoteCall, base);
}

static inline uintptr_t GetLGameActorManager(RemoteCall *remoteCall,
                                             uint64_t base) {
    uintptr_t logicCore = Singleton_LLogicCore(remoteCall, base);
    if (!validOffsetPtr(logicCore))
        return 0;

    uintptr_t manager = ReadGameActorManagerFromDesk(
        remoteCall, ReadMemorySafe<uintptr_t>(
                        remoteCall, logicCore + kLLogicCore_CurUpdatingDesk));
    if (validOffsetPtr(manager))
        return manager;

    uintptr_t listView = ReadMemorySafe<uintptr_t>(
        remoteCall, logicCore + kLLogicCore_Instances);
    if (!validOffsetPtr(listView))
        return 0;

    uintptr_t context =
        ReadMemorySafe<uintptr_t>(remoteCall, listView + kListView_Context);
    int count = ReadRemoteListCount(remoteCall, context);
    for (int i = 0; i < count; ++i) {
        manager = ReadGameActorManagerFromDesk(
            remoteCall, ReadRemoteListObject(remoteCall, context, i));
        if (validOffsetPtr(manager))
            return manager;
    }

    return 0;
}

// MARK: - Resolve calculate vector/matrix

static void MultiplyMatrix4x4(const float *a, const float *b, float *out) {
    for (int column = 0; column < 4; ++column) {
        for (int row = 0; row < 4; ++row) {
            out[column * 4 + row] = a[row] * b[column * 4] +
                                    a[4 + row] * b[column * 4 + 1] +
                                    a[8 + row] * b[column * 4 + 2] +
                                    a[12 + row] * b[column * 4 + 3];
        }
    }
}

static bool ReadValidMatrix(RemoteCall *remoteCall, uintptr_t address,
                            float *out) {
    if (!validOffsetPtr(address) || !out)
        return false;
    if (![remoteCall remoteRead:address to:out size:sizeof(float) * 16])
        return false;

    float magnitude = 0.0f;
    for (int i = 0; i < 16; ++i) {
        if (!std::isfinite(out[i]))
            return false;
        magnitude += fabsf(out[i]);
    }

    return magnitude > 0.5f && magnitude < 1.0e8f;
}

static bool LooksLikeViewProjection(const float *matrix) {
    return fabsf(matrix[11]) > 0.01f || fabsf(matrix[15]) < 0.95f;
}

static bool ReadCameraVPMatrix(RemoteCall *remoteCall, uintptr_t camera,
                               float *out) {
    if (!validOffsetPtr(camera))
        return false;

    uintptr_t nativeCamera =
        ReadMemorySafe<uintptr_t>(remoteCall, camera + kUnityObject_CachedPtr);
    if (!validOffsetPtr(nativeCamera))
        return false;

    float view[16] = {};
    float projection[16] = {};
    float viewProjection[16] = {};
    if (ReadValidMatrix(remoteCall, nativeCamera + kNativeCamera_WorldToCamera,
                        view) &&
        ReadValidMatrix(remoteCall, nativeCamera + kNativeCamera_Projection,
                        projection)) {
        MultiplyMatrix4x4(projection, view, viewProjection);
        if (LooksLikeViewProjection(viewProjection)) {
            memcpy(out, viewProjection, sizeof(viewProjection));
            return true;
        }
    }

    return ReadValidMatrix(remoteCall, nativeCamera + kNativeCamera_WorldToClip,
                           viewProjection) &&
           LooksLikeViewProjection(viewProjection) &&
           (static_cast<void>(
                memcpy(out, viewProjection, sizeof(viewProjection))),
            true);
}

static bool BuildMobaVPMatrix(RemoteCall *remoteCall, uintptr_t cameraSystem,
                              float *out) {
    if (!remoteCall || !validOffsetPtr(cameraSystem) || !out)
        return false;

    uintptr_t mobaCamera = ReadMemorySafe<uintptr_t>(
        remoteCall, cameraSystem + kCameraSystem_MobaCamera);
    uintptr_t requirements =
        validOffsetPtr(mobaCamera)
            ? ReadMemorySafe<uintptr_t>(remoteCall,
                                        mobaCamera + kMobaCamera_Requirements)
            : 0;
    uintptr_t camera =
        validOffsetPtr(requirements)
            ? ReadMemorySafe<uintptr_t>(remoteCall,
                                        requirements + kMobaRequirement_Camera)
            : 0;
    if (ReadCameraVPMatrix(remoteCall, camera, out))
        return true;

    camera = ReadMemorySafe<uintptr_t>(remoteCall,
                                       cameraSystem + kCameraSystem_MainCamera);

    return ReadCameraVPMatrix(remoteCall, camera, out);
}

static double DecimalScale(int value) {
    uint64_t magnitude =
        value < 0 ? (uint64_t)(-(int64_t)value) : (uint64_t)value;
    double scale = 1.0;
    while (magnitude != 0) {
        magnitude /= 10;
        scale *= 10.0;
    }

    return scale;
}

static Vector3 FixedPosition(VInt3 location, VInt3 forward) {
    double xScale = DecimalScale(forward.X);
    double yScale = DecimalScale(forward.Y);
    double zScale = DecimalScale(forward.Z);

    return Vector3(
        (float)(((double)location.X * xScale + forward.X) / (1000.0 * xScale)),
        (float)(((double)location.Y * yScale + forward.Y) / (1000.0 * yScale)),
        (float)(((double)location.Z * zScale + forward.Z) / (1000.0 * zScale)));
}

static Vector3 ReadActorPosition(RemoteCall *remoteCall, uintptr_t actor,
                                 uintptr_t logicActor) {
    Vector3 position = Vector3::zero();

    // 1. Primary: Read Visual ActorLinker Location (updated every graphic frame in Unity)
    if (validOffsetPtr(actor)) {
        VInt3 location =
            ReadMemorySafe<VInt3>(remoteCall, actor + kActorLinker_Location);
        Vector3 visualPos = Vector3((float)location.X * 0.001f, (float)location.Y * 0.001f, (float)location.Z * 0.001f);
        if (fabsf(visualPos.x) > 0.001f || fabsf(visualPos.z) > 0.001f) {
            position = visualPos;
        }
    }

    // 2. Fallback: Only if ActorLinker visual position is zero/unavailable, use LogicActor simulation position
    if (fabsf(position.x) <= 0.001f && fabsf(position.z) <= 0.001f && validOffsetPtr(logicActor)) {
        VInt3 logicLocation = ReadMemorySafe<VInt3>(
            remoteCall, logicActor + kLActorRoot_Location);
        Vector3 logicPosition = Vector3((float)logicLocation.X * 0.001f, (float)logicLocation.Y * 0.001f, (float)logicLocation.Z * 0.001f);
        if (fabsf(logicPosition.x) > 0.001f || fabsf(logicPosition.z) > 0.001f)
            position = logicPosition;
    }

    return position;
}

static Vector3 WorldToViewportPoint(Vector3 world, const float *matrix) {
    float x = matrix[0] * world.x + matrix[4] * world.y + matrix[8] * world.z +
              matrix[12];
    float y = matrix[1] * world.x + matrix[5] * world.y + matrix[9] * world.z +
              matrix[13];
    float w = matrix[3] * world.x + matrix[7] * world.y + matrix[11] * world.z +
              matrix[15];
    if (w <= 0.001f || !std::isfinite(w))
        return Vector3(0.0f, 0.0f, -1.0f);

    return Vector3(x / w * 0.5f + 0.5f, y / w * 0.5f + 0.5f, w);
}

static BOOL ProjectToOverlayPoint(Vector3 world, const float *viewProjection,
                                  CGFloat screenWidth, CGFloat screenHeight,
                                  CGFloat *outX, CGFloat *outY) {
    Vector3 viewport = WorldToViewportPoint(world, viewProjection);
    if (!std::isfinite(viewport.x) || !std::isfinite(viewport.y) ||
        !std::isfinite(viewport.z) || viewport.z <= 0.001f) {
        return NO;
    }

    CGFloat x = viewport.x * screenWidth;
    CGFloat y = (1.0f - viewport.y) * screenHeight;

    if (!std::isfinite((double)x) || !std::isfinite((double)y)) {
        return NO;
    }

    if (outX)
        *outX = x;
    if (outY)
        *outY = y;

    return YES;
}

static BOOL IsScreenPointInside(CGFloat x, CGFloat y, CGFloat screenWidth,
                                CGFloat screenHeight) {
    return x >= 0.0f && y >= 0.0f && x <= screenWidth && y <= screenHeight;
}
