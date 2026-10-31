//
//  FreeFireUtils.h
//  External-DarkSword
//

#ifndef FreeFireUtils_h
#define FreeFireUtils_h

#import "../../../App/Configuration/Macros.h"
#import "../../../App/Support/helper.h"
#import "../../../Core/TaskRop/RemoteCall.h"
#import "../../Unity/Vector3.h"
#import "FreeFireOffset.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

// MARK: - Matrix 4x4 Math

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

// MARK: - Native Camera Reading

static bool ReadValidMatrix(RemoteCall *remoteCall, uintptr_t address,
                            float *out) {
    if (!validOffsetPtr(address) || !out || !remoteCall)
        return false;
    address = CleanPointer(address);
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
    if (!matrix)
        return false;
    return fabsf(matrix[11]) > 0.01f || fabsf(matrix[14]) > 0.01f ||
           fabsf(matrix[15]) < 0.95f;
}

// Native camera matrix offsets drift between Unity builds; remember the ones
// that actually produced a valid view-projection matrix so we don't keep
// guessing every frame.
static uint64_t gFreeFireNativeCameraViewOffset = kNativeCamera_WorldToCamera;
static uint64_t gFreeFireNativeCameraProjectionOffset = kNativeCamera_Projection;
static uint64_t gFreeFireNativeCameraWorldToClipOffset = kNativeCamera_WorldToClip;
static bool gFreeFireNativeCameraOffsetsResolved = false;

static bool ReadCameraVPAndWorldMatrix(RemoteCall *remoteCall, uintptr_t camera,
                                      float *outVP, float *outView) {
    if (!validOffsetPtr(camera) || !remoteCall || !outVP)
        return false;

    camera = CleanPointer(camera);

    uintptr_t nativeCamera = CleanPointer(
        ReadMemorySafe<uintptr_t>(remoteCall, camera + kUnityObject_CachedPtr));
    if (!validOffsetPtr(nativeCamera)) {
        nativeCamera =
            CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, camera + 0x8));
        if (!validOffsetPtr(nativeCamera)) {
            nativeCamera = CleanPointer(
                ReadMemorySafe<uintptr_t>(remoteCall, camera + 0x18));
            if (!validOffsetPtr(nativeCamera)) {
                nativeCamera = CleanPointer(
                    ReadMemorySafe<uintptr_t>(remoteCall, camera + 0x20));
                if (!validOffsetPtr(nativeCamera)) {
                    nativeCamera = camera;
                }
            }
        }
    }
    if (!validOffsetPtr(nativeCamera))
        return false;

    // Try the offsets that worked before (or the dump defaults) first.
    uint64_t candidateViewOffsets[] = {
        gFreeFireNativeCameraViewOffset, kNativeCamera_WorldToCamera, 0x70, 0x80, 0x90, 0xA0
    };
    uint64_t candidateProjOffsets[] = {
        gFreeFireNativeCameraProjectionOffset, kNativeCamera_Projection, 0xB0, 0xC0, 0xD0, 0xE0
    };
    uint64_t candidateClipOffsets[] = {
        gFreeFireNativeCameraWorldToClipOffset, kNativeCamera_WorldToClip, 0x100,
        0xF0, 0x110, 0x120, 0x130, 0x140, 0x180, 0x1C0, 0x200
    };

    auto tryViewProjection = [&](uint64_t viewOff, uint64_t projOff) -> bool {
        float view[16] = {};
        float projection[16] = {};
        float viewProjection[16] = {};
        if (!ReadValidMatrix(remoteCall, nativeCamera + viewOff, view))
            return false;
        if (!ReadValidMatrix(remoteCall, nativeCamera + projOff, projection))
            return false;
        MultiplyMatrix4x4(projection, view, viewProjection);
        if (!LooksLikeViewProjection(viewProjection))
            return false;
        memcpy(outVP, viewProjection, sizeof(viewProjection));
        if (outView) {
            memcpy(outView, view, sizeof(view));
        }
        gFreeFireNativeCameraViewOffset = viewOff;
        gFreeFireNativeCameraProjectionOffset = projOff;
        gFreeFireNativeCameraOffsetsResolved = true;
        return true;
    };

    auto tryWorldToClip = [&](uint64_t clipOff) -> bool {
        float viewProjection[16] = {};
        if (!ReadValidMatrix(remoteCall, nativeCamera + clipOff, viewProjection))
            return false;
        if (!LooksLikeViewProjection(viewProjection))
            return false;
        memcpy(outVP, viewProjection, sizeof(viewProjection));
        if (outView) {
            if (!ReadValidMatrix(remoteCall,
                                 nativeCamera + gFreeFireNativeCameraViewOffset,
                                 outView)) {
                memset(outView, 0, sizeof(float) * 16);
            }
        }
        gFreeFireNativeCameraWorldToClipOffset = clipOff;
        gFreeFireNativeCameraOffsetsResolved = true;
        return true;
    };

    for (size_t i = 0;
         i < sizeof(candidateViewOffsets) / sizeof(candidateViewOffsets[0]);
         ++i) {
        if (tryViewProjection(candidateViewOffsets[i],
                              candidateProjOffsets[i]))
            return true;
    }
    for (size_t i = 0;
         i < sizeof(candidateClipOffsets) / sizeof(candidateClipOffsets[0]);
         ++i) {
        if (tryWorldToClip(candidateClipOffsets[i]))
            return true;
    }

    // Fast consecutive matrix block discovery (m_WorldToCamera, m_Projection, m_WorldToClip)
    for (uint64_t baseOff = 0x40; baseOff <= 0x200; baseOff += 0x8) {
        if (tryViewProjection(baseOff, baseOff + 0x40))
            return true;
        if (tryWorldToClip(baseOff + 0x80))
            return true;
        if (tryWorldToClip(baseOff))
            return true;
    }

    return false;
}

static bool ReadCameraVPMatrixFromNative(RemoteCall *remoteCall,
                                        uintptr_t camera, float *out) {
    return ReadCameraVPAndWorldMatrix(remoteCall, camera, out, NULL);
}

static Vector3 GetCameraPositionFromViewMatrix(const float *view) {
    if (!view)
        return Vector3::zero();
    float tx = view[12];
    float ty = view[13];
    float tz = view[14];
    float x = -(view[0] * tx + view[1] * ty + view[2] * tz);
    float y = -(view[4] * tx + view[5] * ty + view[6] * tz);
    float z = -(view[8] * tx + view[9] * ty + view[10] * tz);
    if (!std::isfinite(x) || !std::isfinite(y) || !std::isfinite(z))
        return Vector3::zero();
    return Vector3(x, y, z);
}

// MARK: - Pure Memory Transform & Entity Position

struct UnityMatrix3x4 {
    float data[12];
};

static bool ReadTransformPosition(RemoteCall *remoteCall,
                                  uintptr_t managedTransform, Vector3 *outPos) {
    managedTransform = CleanPointer(managedTransform);
    if (!validOffsetPtr(managedTransform) || !remoteCall || !outPos)
        return false;

    uintptr_t nativeTransform = CleanPointer(ReadMemorySafe<uintptr_t>(
        remoteCall, managedTransform + kUnityObject_CachedPtr));
    if (!validOffsetPtr(nativeTransform)) {
        nativeTransform = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, managedTransform + 0x8));
        if (!validOffsetPtr(nativeTransform)) {
            nativeTransform = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, managedTransform + 0x18));
        }
    }
    if (!validOffsetPtr(nativeTransform))
        return false;

    // TransformAccessReadOnly at nativeTransform + 0x38
    uintptr_t pTransformAccess =
        CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, nativeTransform + 0x38));
    int32_t index =
        ReadMemorySafe<int32_t>(remoteCall, nativeTransform + 0x40);

    if (validOffsetPtr(pTransformAccess) && index >= 0 && index < 20000) {
        uintptr_t pTransformArray =
            CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, pTransformAccess + 0x18));
        if (!validOffsetPtr(pTransformArray)) {
            pTransformArray =
                CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, pTransformAccess));
        }

        if (validOffsetPtr(pTransformArray)) {
            uintptr_t matrixAddr = pTransformArray + (uintptr_t)index * 48;
            UnityMatrix3x4 mat = {};
            if ([remoteCall remoteRead:matrixAddr to:&mat size:sizeof(mat)]) {
                Vector3 pos(mat.data[3], mat.data[7], mat.data[11]);
                if (std::isfinite(pos.x) && std::isfinite(pos.y) &&
                    std::isfinite(pos.z) &&
                    (fabsf(pos.x) > 0.01f || fabsf(pos.y) > 0.01f ||
                     fabsf(pos.z) > 0.01f) &&
                    fabsf(pos.x) < 50000.0f && fabsf(pos.z) < 50000.0f) {
                    *outPos = pos;
                    return true;
                }
            }
        }
    }

    return false;
}

static bool ReadEntityPosition(RemoteCall *remoteCall, uintptr_t entity,
                               Vector3 *outPos) {
    if (!validOffsetPtr(entity) || !remoteCall || !outPos)
        return false;

    // 1. Try Transform
    uintptr_t transform = CleanPointer(
        ReadMemorySafe<uintptr_t>(remoteCall, entity + kEntity_CachedTransform));
    if (validOffsetPtr(transform)) {
        if (ReadTransformPosition(remoteCall, transform, outPos)) {
            return true;
        }
    }

    // 2. Try Vector3 fields in Player / AttackableEntity
    // Position1 at 0xD0
    Vector3 v1 = ReadMemorySafe<Vector3>(remoteCall, entity + kPlayer_Position1);
    if (std::isfinite(v1.x) && std::isfinite(v1.y) && std::isfinite(v1.z) &&
        (fabsf(v1.x) > 0.1f || fabsf(v1.z) > 0.1f) &&
        fabsf(v1.x) < 50000.0f && fabsf(v1.z) < 50000.0f) {
        *outPos = v1;
        return true;
    }

    // Position2 at 0x10C
    Vector3 v2 = ReadMemorySafe<Vector3>(remoteCall, entity + kPlayer_Position2);
    if (std::isfinite(v2.x) && std::isfinite(v2.y) && std::isfinite(v2.z) &&
        (fabsf(v2.x) > 0.1f || fabsf(v2.z) > 0.1f) &&
        fabsf(v2.x) < 50000.0f && fabsf(v2.z) < 50000.0f) {
        *outPos = v2;
        return true;
    }

    // Position3 at 0x270
    Vector3 v3 = ReadMemorySafe<Vector3>(remoteCall, entity + kPlayer_Position3);
    if (std::isfinite(v3.x) && std::isfinite(v3.y) && std::isfinite(v3.z) &&
        (fabsf(v3.x) > 0.1f || fabsf(v3.z) > 0.1f) &&
        fabsf(v3.x) < 50000.0f && fabsf(v3.z) < 50000.0f) {
        *outPos = v3;
        return true;
    }

    return false;
}

// MARK: - Il2Cpp String Reading

static NSString *ReadIl2CppString(RemoteCall *remoteCall, uintptr_t stringAddr) {
    if (!validOffsetPtr(stringAddr) || !remoteCall)
        return @"";

    int32_t length =
        ReadMemorySafe<int32_t>(remoteCall, stringAddr + kSystemString_Length);
    if (length <= 0 || length > 128)
        return @"";

    uint16_t buffer[129] = {0};
    size_t readBytes = length * sizeof(uint16_t);
    if (![remoteCall remoteRead:stringAddr + kSystemString_Chars
                             to:buffer
                           size:readBytes]) {
        return @"";
    }

    buffer[length] = 0;
    return [NSString stringWithCharacters:buffer length:length];
}

// MARK: - Il2Cpp Object Introspection

// Which Il2CppClass offset holds the class name. The dump says 0x10, but a
// mismatch silently breaks every class-name based check, so the resolver
// corrects this at runtime once it matches a known class name from the image.
static uint64_t gFreeFireKlassNameOffset = kIl2CppClass_Name;

// Lazily scanned location of the "GameFacade" string inside the image, and
// whether the scan already ran (it streams the whole mapped binary once).
static uintptr_t gGameFacadeNameAddress = 0;
static bool gGameFacadeNameScanned = false;

static bool ReadKlassName(RemoteCall *remoteCall, uintptr_t klass,
                          char *out, size_t capacity) {
    if (!remoteCall || !out || capacity == 0)
        return false;

    out[0] = '\0';
    uintptr_t raw = CleanPointer(klass);
    if (!validOffsetPtr(raw))
        return false;

    // In 64-bit iOS, Il2CppClass pointers may carry low tag bits (e.g. 0x4).
    // We try both aligned (raw & ~7ULL) and raw.
    const uintptr_t candidates[2] = { raw & ~7ULL, raw };
    for (int k = 0; k < 2; ++k) {
        uintptr_t kAddr = candidates[k];
        if (!validOffsetPtr(kAddr))
            continue;

        // Scan candidate offsets for class name.
        // In Il2CppClass, name is at 0x10. We check 0x10 first, then 0x18, 0x20, 0x28, 0x30, 0x08.
        const uint64_t candidateOffsets[] = { 0x10, 0x18, 0x20, 0x28, 0x30, 0x08 };
        for (int i = 0; i < 6; ++i) {
            uint64_t off = candidateOffsets[i];
            uintptr_t namePtr = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, kAddr + off));
            if (!validOffsetPtr(namePtr))
                continue;

            char buffer[64] = {0};
            if (![remoteCall remoteRead:namePtr to:buffer size:sizeof(buffer) - 1])
                continue;

            size_t length = 0;
            while (length < sizeof(buffer) && buffer[length] != '\0') {
                unsigned char c = (unsigned char)buffer[length];
                if (c < 0x20 || c > 0x7E)
                    break;
                ++length;
            }

            if (length == 0 || length >= capacity || buffer[length] != '\0')
                continue;

            // Skip image/assembly names
            if (strcmp(buffer, "Assembly-CSharp") == 0 ||
                strstr(buffer, "Assembly-CSharp") != NULL ||
                strstr(buffer, ".dll") != NULL) {
                continue;
            }

            // Skip common top-level namespaces
            if (strcmp(buffer, "COW") == 0 ||
                strcmp(buffer, "UnityEngine") == 0 ||
                strcmp(buffer, "System") == 0) {
                continue;
            }

            memcpy(out, buffer, length);
            out[length] = '\0';
            return true;
        }
    }

    return false;
}

static bool ReadIl2CppClassName(RemoteCall *remoteCall, uintptr_t object,
                                char *out, size_t capacity) {
    if (!remoteCall || !out || capacity == 0)
        return false;

    out[0] = '\0';
    object = CleanPointer(object);
    if (!validOffsetPtr(object))
        return false;

    // Check klass at +0x00
    uintptr_t klass0 = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, object + 0x0));
    if (validOffsetPtr(klass0) && ReadKlassName(remoteCall, klass0, out, capacity))
        return true;

    // Check klass at +0x08 (in case object has native vtable at 0x00)
    uintptr_t klass8 = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, object + 0x8));
    if (validOffsetPtr(klass8) && ReadKlassName(remoteCall, klass8, out, capacity))
        return true;

    return false;
}

static bool FreeFireStaticBlockHasGameSlot(RemoteCall *remoteCall, uintptr_t block) {
    if (!remoteCall || !validOffsetPtr(block))
        return false;

    for (uint64_t slot = 0x0; slot <= 0x8; slot += 0x8) {
        uintptr_t value = ReadMemorySafe<uintptr_t>(remoteCall, block + slot);
        if (value == 0)
            return true;
        if (!validOffsetPtr(value))
            continue;

        char name[64] = {0};
        if (ReadIl2CppClassName(remoteCall, value, name, sizeof(name)) &&
            strstr(name, "Game") != NULL) {
            return true;
        }
    }

    uint64_t uid = ReadMemorySafe<uint64_t>(remoteCall, block + 0x58);
    if (uid > 10000000ULL && uid < 10000000000000ULL) {
        int stringMatches = 0;
        for (uint64_t slot = 0x10; slot <= 0x40; slot += sizeof(uintptr_t)) {
            uintptr_t strObj =
                ReadMemorySafe<uintptr_t>(remoteCall, block + slot);
            if (!validOffsetPtr(strObj))
                continue;
            int32_t strLen =
                ReadMemorySafe<int32_t>(remoteCall, strObj + 0x10);
            if (strLen > 0 && strLen < 128) {
                uint16_t firstChar =
                    ReadMemorySafe<uint16_t>(remoteCall, strObj + 0x14);
                if (firstChar >= 0x20 && firstChar <= 0x7E)
                    ++stringMatches;
            }
        }
        if (stringMatches >= 2)
            return true;
    }

    return false;
}


static bool IsSubclassOf(RemoteCall *remoteCall, uintptr_t object,
                         const char *targetName) {
    object = CleanPointer(object);
    if (!remoteCall || !validOffsetPtr(object) || !targetName)
        return false;

    const uintptr_t klasses[2] = {
        CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, object + 0x0)),
        CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, object + 0x8))
    };

    for (int k = 0; k < 2; ++k) {
        uintptr_t rootKlass = klasses[k];
        if (!validOffsetPtr(rootKlass)) continue;
        uintptr_t klass = rootKlass & ~7ULL;
        for (int depth = 0; depth < 10 && validOffsetPtr(klass); ++depth) {
            char buffer[64] = {0};
            if (ReadKlassName(remoteCall, klass, buffer, sizeof(buffer))) {
                if (strstr(buffer, targetName) != NULL) {
                    return true;
                }
            }
            klass = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, klass + kIl2CppClass_Parent)) & ~7ULL;
        }
    }
    return false;
}

static bool Il2CppClassNameContains(RemoteCall *remoteCall, uintptr_t object,
                                    const char *needle) {
    if (!needle)
        return false;

    char name[64] = {0};
    if (!ReadIl2CppClassName(remoteCall, object, name, sizeof(name)))
        return false;

    return strstr(name, needle) != NULL;
}

// MARK: - Verified Field Discovery
//
// The offsets in FreeFireOffset.h come from one dump and shift between Free
// Fire builds. These helpers find a field by the il2cpp class name of the
// object it points at, so the ESP survives an offset mismatch.

static uint64_t gFreeFireMatchGameFieldOffset = 0;
static uint64_t gFreeFireCameraManagerFieldOffset = 0;
static uint64_t gFreeFireCameraFieldOffset = 0;
static uint64_t gFreeFireEntitiesFieldOffset = 0;

enum FreeFireContainerType {
    kContainerType_None = 0,
    kContainerType_Dictionary = 1,
    kContainerType_List = 2,
    kContainerType_Queue = 3,
    kContainerType_Array = 4
};

struct FreeFireEntityContainer {
    uintptr_t container = 0;
    int containerType = kContainerType_None;
    bool isList = false;
    int32_t count = 0;
    uintptr_t arrayPtr = 0;
    int32_t head = 0;
    int32_t capacity = 0;
};

static inline bool InspectEntityContainer(RemoteCall *remoteCall, uintptr_t cand, FreeFireEntityContainer *outContainer) {
    if (!remoteCall || !outContainer)
        return false;

    cand = CleanPointer(cand);
    if (!validOffsetPtr(cand))
        return false;

    // 1. Check Dictionary: 0x18 = entries, 0x20 = count
    uintptr_t entries = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, cand + kDictionary_Entries));
    int32_t dictCount = ReadMemorySafe<int32_t>(remoteCall, cand + kDictionary_Count);
    if (validOffsetPtr(entries) && dictCount >= 0 && dictCount < 10000) {
        int32_t arrLen = ReadMemorySafe<int32_t>(remoteCall, entries + kArray_Length);
        if (arrLen >= dictCount && arrLen <= 25000) {
            outContainer->container = cand;
            outContainer->containerType = kContainerType_Dictionary;
            outContainer->isList = false;
            outContainer->count = dictCount;
            outContainer->arrayPtr = entries;
            outContainer->head = 0;
            outContainer->capacity = arrLen;
            return true;
        }
    }

    // 2. Check Queue<T>: 0x10 = _array, 0x18 = _head, 0x20 = _size
    uintptr_t qArray = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, cand + 0x10));
    int32_t qHead = ReadMemorySafe<int32_t>(remoteCall, cand + 0x18);
    int32_t qSize = ReadMemorySafe<int32_t>(remoteCall, cand + 0x20);
    if (validOffsetPtr(qArray) && qSize >= 0 && qSize < 10000 && qHead >= 0) {
        int32_t arrLen = ReadMemorySafe<int32_t>(remoteCall, qArray + kArray_Length);
        if (arrLen >= qSize && arrLen <= 25000 && (arrLen == 0 || qHead < arrLen)) {
            outContainer->container = cand;
            outContainer->containerType = kContainerType_Queue;
            outContainer->isList = true;
            outContainer->count = qSize;
            outContainer->arrayPtr = qArray;
            outContainer->head = qHead;
            outContainer->capacity = arrLen;
            return true;
        }
    }

    // 3. Check List<T>: 0x10 = _items, 0x18 = _size
    uintptr_t items = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, cand + 0x10));
    int32_t listSize = ReadMemorySafe<int32_t>(remoteCall, cand + 0x18);
    if (validOffsetPtr(items) && listSize >= 0 && listSize < 10000) {
        int32_t arrLen = ReadMemorySafe<int32_t>(remoteCall, items + kArray_Length);
        if (arrLen >= listSize && arrLen <= 25000) {
            outContainer->container = cand;
            outContainer->containerType = kContainerType_List;
            outContainer->isList = true;
            outContainer->count = listSize;
            outContainer->arrayPtr = items;
            outContainer->head = 0;
            outContainer->capacity = arrLen;
            return true;
        }
    }

    // 4. Check direct Array: 0x18 = length
    int32_t directArrLen = ReadMemorySafe<int32_t>(remoteCall, cand + kArray_Length);
    if (directArrLen > 0 && directArrLen <= 2000) {
        uintptr_t bounds = ReadMemorySafe<uintptr_t>(remoteCall, cand + 0x10);
        if (bounds == 0) {
            outContainer->container = cand;
            outContainer->containerType = kContainerType_Array;
            outContainer->isList = true;
            outContainer->count = directArrLen;
            outContainer->arrayPtr = cand;
            outContainer->head = 0;
            outContainer->capacity = directArrLen;
            return true;
        }
    }

    return false;
}

static inline uintptr_t GetEntityFromContainer(RemoteCall *remoteCall,
                                               const FreeFireEntityContainer &c,
                                               int32_t index) {
    if (!remoteCall || !validOffsetPtr(c.arrayPtr) || index < 0 || index >= c.count)
        return 0;

    switch (c.containerType) {
        case kContainerType_Dictionary: {
            uintptr_t entryAddr = c.arrayPtr + kArray_Vector + (uint64_t)index * kEntry_Size;
            int32_t hashCode = ReadMemorySafe<int32_t>(remoteCall, entryAddr + kEntry_HashCode);
            if (hashCode < 0)
                return 0;
            return CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, entryAddr + kEntry_Value));
        }
        case kContainerType_Queue: {
            if (c.capacity <= 0) return 0;
            int32_t qIndex = (c.head + index) % c.capacity;
            return CleanPointer(ReadMemorySafe<uintptr_t>(
                remoteCall, c.arrayPtr + kArray_Vector + (uint64_t)qIndex * sizeof(uintptr_t)));
        }
        case kContainerType_List:
        case kContainerType_Array:
        default: {
            return CleanPointer(ReadMemorySafe<uintptr_t>(
                remoteCall, c.arrayPtr + kArray_Vector + (uint64_t)index * sizeof(uintptr_t)));
        }
    }
}

static bool IsDictionaryObject(RemoteCall *remoteCall, uintptr_t object) {
    if (!validOffsetPtr(object))
        return false;
    if (Il2CppClassNameContains(remoteCall, object, "Dictionary"))
        return true;

    // Structural dictionary validation fallback:
    // In Il2Cpp Dictionary<TKey, TValue>:
    // 0x18: entries (array pointer)
    // 0x20: count (int32)
    uintptr_t entries = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, object + kDictionary_Entries));
    int32_t count = ReadMemorySafe<int32_t>(remoteCall, object + kDictionary_Count);
    if (validOffsetPtr(entries) && count >= 0 && count < 10000) {
        int32_t length = ReadMemorySafe<int32_t>(remoteCall, entries + kArray_Length);
        if (length >= count && length <= 25000) {
            return true;
        }
    }
    return false;
}

static bool LooksLikeCameraManager(RemoteCall *remoteCall, uintptr_t object);

// m_Match (MatchGame + 0x90) is a managed object whose first player/vehicle
// containers live between 0x128 and 0x2A0. At least three of those fields must
// have a real Dictionary/List/Queue shape. This is deliberately structural:
// class names are not reliable on every Free Fire build.
static bool LooksLikeMatchObject(RemoteCall *remoteCall, uintptr_t matchObj) {
    if (!remoteCall || !validOffsetPtr(matchObj))
        return false;
    matchObj = CleanPointer(matchObj);

    static const uint64_t kShapedOffsets[] = {
        kMatch_Players1, kMatch_Players2, kMatch_Players3, kMatch_Players4,
        kMatch_Players5, kMatch_PlayerList1, kMatch_PlayerList2,
        kMatch_AIPawns,    kMatch_Teams,     kMatch_Vehicles,
        kMatch_Containers
    };

    int shaped = 0;
    for (uint64_t off : kShapedOffsets) {
        uintptr_t cand = CleanPointer(
            ReadMemorySafe<uintptr_t>(remoteCall, matchObj + off));
        if (!validOffsetPtr(cand))
            continue;
        FreeFireEntityContainer info;
        if (InspectEntityContainer(remoteCall, cand, &info))
            ++shaped;
        if (shaped >= 3)
            return true;
    }
    return false;
}

static bool FieldHoldsMatchGame(RemoteCall *remoteCall, uintptr_t value) {
    if (!remoteCall || !validOffsetPtr(value))
        return false;
    value = CleanPointer(value);

    char name[64] = {0};
    if (ReadIl2CppClassName(remoteCall, value, name, sizeof(name))) {
        if (strstr(name, "FrontEnd") != NULL ||
            strstr(name, "Lobby") != NULL ||
            strstr(name, "Hotupdater") != NULL)
            return false;
        if (strstr(name, "MatchGame") != NULL)
            return true;
    }

    // MatchGame subclass. Do not accept COWGameBase: FrontEndGame inherits it
    // too, which made the lobby object look like an active match.
    if (IsSubclassOf(remoteCall, value, "MatchGame"))
        return true;

    // Structural validation fallback. Require a real m_Match object plus a
    // second MatchGame-shaped field, so a FrontEndGame cannot pass by itself.
    uintptr_t matchObj = CleanPointer(
        ReadMemorySafe<uintptr_t>(remoteCall, value + kMatchGame_Match));
    if (!LooksLikeMatchObject(remoteCall, matchObj))
        return false;

    uintptr_t camMgr = CleanPointer(
        ReadMemorySafe<uintptr_t>(remoteCall, value + kMatchGame_CameraControllerManager));
    if (validOffsetPtr(camMgr) && LooksLikeCameraManager(remoteCall, camMgr))
        return true;

    uintptr_t repDict = CleanPointer(
        ReadMemorySafe<uintptr_t>(remoteCall, value + kMatchGame_ReplicationEntities));
    if (validOffsetPtr(repDict) && IsDictionaryObject(remoteCall, repDict))
        return true;

    return false;
}

static bool FieldHoldsAnyGame(RemoteCall *remoteCall, uintptr_t value) {
    if (!remoteCall || !validOffsetPtr(value))
        return false;
    char name[64] = {0};
    if (ReadIl2CppClassName(remoteCall, value, name, sizeof(name))) {
        if (strstr(name, "Hotupdater") != NULL)
            return false;
        if (strstr(name, "Game") != NULL)
            return true;
    }
    return IsSubclassOf(remoteCall, value, "COWGameBase") ||
           IsSubclassOf(remoteCall, value, "BaseGame");
}

static uintptr_t ResolveBaseGameStaticFields(RemoteCall *remoteCall, uintptr_t gameObject) {
    if (!remoteCall || !validOffsetPtr(gameObject))
        return 0;

    const uintptr_t klasses[2] = {
        CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, gameObject + 0x0)),
        CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, gameObject + 0x8))
    };

    for (int k = 0; k < 2; ++k) {
        uintptr_t rootKlass = klasses[k];
        if (!validOffsetPtr(rootKlass)) continue;
        uintptr_t klass = rootKlass & ~7ULL;
        for (int depth = 0; depth < 8 && validOffsetPtr(klass); ++depth) {
            char name[64] = {0};
            if (ReadKlassName(remoteCall, klass, name, sizeof(name))) {
                if (strcmp(name, "BaseGame") == 0 || strcmp(name, "COWGameBase") == 0) {
                    return CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, klass + kIl2CppClass_StaticFields));
                }
            }
            klass = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, klass + kIl2CppClass_Parent)) & ~7ULL;
        }
    }
    return 0;
}

static uintptr_t ResolveBaseGameAllEntities(RemoteCall *remoteCall, uintptr_t gameObject) {
    if (!remoteCall || !validOffsetPtr(gameObject))
        return 0;

    // Approach 1: Named walk to BaseGame
    uintptr_t staticFields = ResolveBaseGameStaticFields(remoteCall, gameObject);
    if (validOffsetPtr(staticFields)) {
        const uint64_t slots[] = {
            kBaseGameStatic_sAllEntities,
            kBaseGameStatic_sTickedEntities,
            kBaseGameStatic_sAllLEntities
        };
        uintptr_t fallbackDict = 0;
        for (uint64_t slot : slots) {
            uintptr_t dict = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, staticFields + slot));
            if (validOffsetPtr(dict) && IsDictionaryObject(remoteCall, dict)) {
                int32_t cnt = ReadMemorySafe<int32_t>(remoteCall, dict + kDictionary_Count);
                if (cnt > 0)
                    return dict;
                if (fallbackDict == 0)
                    fallbackDict = dict;
            }
        }
        if (fallbackDict != 0)
            return fallbackDict;
    }

    // Approach 2: Structural walk up parent chain of gameObject
    uintptr_t klass = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, gameObject + 0x0)) & ~7ULL;
    for (int depth = 0; depth < 6 && validOffsetPtr(klass); ++depth) {
        uintptr_t sf = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, klass + kIl2CppClass_StaticFields));
        if (validOffsetPtr(sf)) {
            for (uint64_t off = 0x0; off <= 0x18; off += sizeof(uintptr_t)) {
                uintptr_t dict = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, sf + off));
                if (validOffsetPtr(dict) && IsDictionaryObject(remoteCall, dict)) {
                    int32_t cnt = ReadMemorySafe<int32_t>(remoteCall, dict + kDictionary_Count);
                    if (cnt > 0) {
                        return dict;
                    }
                }
            }
        }
        klass = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, klass + kIl2CppClass_Parent)) & ~7ULL;
    }

    return 0;
}

static bool FieldHoldsCamera(RemoteCall *remoteCall, uintptr_t value) {
    return Il2CppClassNameContains(remoteCall, value, "Camera");
}

// A camera manager either carries its type in the class name or owns a
// UnityEngine.Camera reference in one of its first fields.
static bool LooksLikeCameraManager(RemoteCall *remoteCall, uintptr_t object) {
    if (!validOffsetPtr(object))
        return false;

    if (Il2CppClassNameContains(remoteCall, object, "CameraController"))
        return true;

    for (uint64_t offset = 0x10; offset <= 0x60;
         offset += sizeof(uintptr_t)) {
        uintptr_t value =
            ReadMemorySafe<uintptr_t>(remoteCall, object + offset);
        if (!validOffsetPtr(value))
            continue;
        if (FieldHoldsCamera(remoteCall, value))
            return true;
    }

    return false;
}

// Replication dictionaries are the ones whose values are Entity / Player / Target objects.
static bool LooksLikePlayerDictionary(RemoteCall *remoteCall, uintptr_t dict) {
    if (!IsDictionaryObject(remoteCall, dict))
        return false;

    int32_t count =
        ReadMemorySafe<int32_t>(remoteCall, dict + kDictionary_Count);
    if (count <= 0 || count > 10000)
        return false;

    uintptr_t entries = CleanPointer(
        ReadMemorySafe<uintptr_t>(remoteCall, dict + kDictionary_Entries));
    if (!validOffsetPtr(entries))
        return false;

    int32_t maxEntries =
        ReadMemorySafe<int32_t>(remoteCall, entries + kArray_Length);
    if (maxEntries <= 0)
        return false;

    int32_t probe = std::min(maxEntries, 32);
    for (int32_t i = 0; i < probe; ++i) {
        uintptr_t entryAddr =
            entries + kArray_Vector + (uint64_t)i * kEntry_Size;
        int32_t hashCode =
            ReadMemorySafe<int32_t>(remoteCall, entryAddr + kEntry_HashCode);
        if (hashCode < 0)
            continue;

        uintptr_t value = CleanPointer(
            ReadMemorySafe<uintptr_t>(remoteCall, entryAddr + kEntry_Value));
        if (!validOffsetPtr(value))
            continue;

        if (IsSubclassOf(remoteCall, value, "Player") ||
            IsSubclassOf(remoteCall, value, "Entity") ||
            IsSubclassOf(remoteCall, value, "AttackableEntity") ||
            Il2CppClassNameContains(remoteCall, value, "Player") ||
            Il2CppClassNameContains(remoteCall, value, "Entity") ||
            Il2CppClassNameContains(remoteCall, value, "Target") ||
            Il2CppClassNameContains(remoteCall, value, "Dummy"))
            return true;

        Vector3 testPos = Vector3::zero();
        if (ReadEntityPosition(remoteCall, value, &testPos))
            return true;
    }

    return false;
}

static uint64_t FindIl2CppFieldMatchingFrom(
    RemoteCall *remoteCall, uintptr_t object, uint64_t startOffset,
    uint64_t endOffset, bool (*predicate)(RemoteCall *, uintptr_t)) {
    if (!remoteCall || !predicate || !validOffsetPtr(object))
        return 0;

    for (uint64_t offset = startOffset;
         offset + sizeof(uintptr_t) <= endOffset;
         offset += sizeof(uintptr_t)) {
        uintptr_t value =
            ReadMemorySafe<uintptr_t>(remoteCall, object + offset);
        if (!validOffsetPtr(value))
            continue;
        if (predicate(remoteCall, value))
            return offset;
    }

    return 0;
}

// Managed objects start their fields at 0x10 (klass + monitor headers),
// while a static fields block starts at 0x00.
static uint64_t FindIl2CppFieldMatching(
    RemoteCall *remoteCall, uintptr_t object, uint64_t endOffset,
    bool (*predicate)(RemoteCall *, uintptr_t)) {
    return FindIl2CppFieldMatchingFrom(remoteCall, object, 0x10, endOffset,
                                       predicate);
}

// MARK: - GameFacade Static Fields Verification
//
// Dump RVAs and the static_fields offset both drift between Free Fire builds,
// so a pointer only counts as "GameFacade's static fields" when its contents
// prove it: either it is GameFacade's Il2CppClass (found by class name) and
// the block lives inside it, or it IS the block (a dump slot holds a game
// object). Unverifiable pointers are discarded instead of being used.

static const int kMaxStaticCandidates = 48;

static void PushCandidate(uintptr_t *values, int *count, int capacity,
                          uintptr_t value) {
    if (!values || !count || !validOffsetPtr(value))
        return;
    if (*count >= capacity)
        return;
    for (int i = 0; i < *count; ++i) {
        if (values[i] == value)
            return;
    }
    values[(*count)++] = value;
}

static bool LooksLikeGameFacadeStaticBlock(RemoteCall *remoteCall,
                                           uintptr_t block) {
    if (!remoteCall || !validOffsetPtr(block))
        return false;

    // Check 1: In-match or lobby Game object at 0x08 (CurrentMatchGame) or 0x00 (CurrentGame)
    for (uint64_t slot = 0x0; slot <= 0x38; slot += sizeof(uintptr_t)) {
        uintptr_t value = ReadMemorySafe<uintptr_t>(remoteCall, block + slot);
        if (validOffsetPtr(value)) {
            char name[64] = {0};
            if (ReadIl2CppClassName(remoteCall, value, name, sizeof(name))) {
                if (strstr(name, "Game") != NULL)
                    return true;
            }
        }
    }

    // Check 2: C# static string fields (GameFacade has static strings from 0x10 to 0x40)
    int stringMatches = 0;
    for (uint64_t slot = 0x10; slot <= 0x40; slot += sizeof(uintptr_t)) {
        uintptr_t strObj = ReadMemorySafe<uintptr_t>(remoteCall, block + slot);
        if (validOffsetPtr(strObj)) {
            int32_t strLen = ReadMemorySafe<int32_t>(remoteCall, strObj + 0x10);
            if (strLen > 0 && strLen < 128) {
                uint16_t firstChar = ReadMemorySafe<uint16_t>(remoteCall, strObj + 0x14);
                if (firstChar >= 0x20 && firstChar <= 0x7E) {
                    stringMatches++;
                }
            }
        }
    }
    if (stringMatches >= 2)
        return true;

    // Check 3: LocalPlayerUserID at 0x58 (positive integer > 10000000)
    uint64_t uid = ReadMemorySafe<uint64_t>(remoteCall, block + 0x58);
    if (uid > 10000000ULL && uid < 10000000000000ULL)
        return true;

    return false;
}

static uintptr_t TryResolveGameFacadeFromKlass(RemoteCall *remoteCall,
                                              uintptr_t klass) {
    if (!remoteCall || !validOffsetPtr(klass))
        return 0;

    char className[64] = {0};
    if (ReadKlassName(remoteCall, klass, className, sizeof(className))) {
        if (strcmp(className, "GameFacade") == 0) {
            // Found GameFacade! Read static_fields at 0xB8
            uintptr_t sf = ReadMemorySafe<uintptr_t>(remoteCall, klass + kIl2CppClass_StaticFields);
            if (validOffsetPtr(sf) && FreeFireStaticBlockHasGameSlot(remoteCall, sf)) {
                return sf;
            }
            // Fallback: scan klass fields for static_fields block
            for (uint64_t sfoff = 0x50; sfoff <= 0x200; sfoff += sizeof(uintptr_t)) {
                uintptr_t block = ReadMemorySafe<uintptr_t>(remoteCall, klass + sfoff);
                if (validOffsetPtr(block) &&
                    LooksLikeGameFacadeStaticBlock(remoteCall, block) &&
                    FreeFireStaticBlockHasGameSlot(remoteCall, block))
                    return block;
            }
        }
    }
    return 0;
}

// The static_fields pointer sits at a build-dependent offset inside
// Il2CppClass, so scan instead of trusting a single number.
static uintptr_t FindStaticFieldsBlockInKlass(RemoteCall *remoteCall,
                                              uintptr_t klass) {
    if (!validOffsetPtr(klass))
        return 0;

    // 1. Direct offset from Il2CppClass definition (0xB8)
    uintptr_t primaryBlock = ReadMemorySafe<uintptr_t>(remoteCall, klass + kIl2CppClass_StaticFields);
    if (validOffsetPtr(primaryBlock)) {
        return primaryBlock;
    }

    // 2. Scan fallback
    for (uint64_t offset = 0x20; offset <= 0x280;
         offset += sizeof(uintptr_t)) {
        uintptr_t block = ReadMemorySafe<uintptr_t>(remoteCall, klass + offset);
        if (validOffsetPtr(block) &&
            LooksLikeGameFacadeStaticBlock(remoteCall, block) &&
            FreeFireStaticBlockHasGameSlot(remoteCall, block))
            return block;
    }
    return 0;
}

// Reads the C string pointed to by a struct field — a probe helper: a class
// name field should yield a printable ASCII string.
static void ReadStructPointerString(RemoteCall *remoteCall, uintptr_t structure,
                                    uint64_t fieldOffset, char *out,
                                    size_t capacity) {
    if (!out || capacity == 0)
        return;
    out[0] = '\0';
    if (!remoteCall || !validOffsetPtr(structure))
        return;

    uintptr_t ptr =
        ReadMemorySafe<uintptr_t>(remoteCall, structure + fieldOffset);
    if (!validOffsetPtr(ptr))
        return;

    char buffer[48] = {0};
    if (![remoteCall remoteRead:ptr to:buffer size:sizeof(buffer) - 1])
        return;
    buffer[sizeof(buffer) - 1] = '\0';

    size_t length = 0;
    while (length < sizeof(buffer) && buffer[length] != '\0') {
        unsigned char c = (unsigned char)buffer[length];
        if (c < 0x20 || c > 0x7E)
            return;
        ++length;
    }
    if (length == 0)
        return;

    size_t copyLength = length < capacity - 1 ? length : capacity - 1;
    memcpy(out, buffer, copyLength);
    out[copyLength] = '\0';
}

// Returns the offset inside `structure` whose value equals `stringAddr` —
// i.e. which field holds the given class name pointer — or 0.
static uint64_t FindNameOffsetByString(RemoteCall *remoteCall,
                                       uintptr_t structure,
                                       uintptr_t stringAddr) {
    if (!remoteCall || !validOffsetPtr(structure) ||
        !validOffsetPtr(stringAddr))
        return 0;

    for (uint64_t offset = 0x0; offset <= 0x40;
         offset += sizeof(uintptr_t)) {
        uintptr_t value =
            ReadMemorySafe<uintptr_t>(remoteCall, structure + offset);
        if (value == stringAddr)
            return offset;
    }
    return 0;
}

// Streams the mapped image looking for the literal "GameFacade" class name
// and returns its address (cached; runs at most once per process).
static uintptr_t FindGameFacadeNameInImage(RemoteCall *remoteCall,
                                           uintptr_t base) {
    // In Unity Il2Cpp, class names are stored in global-metadata.dat and loaded into heap/metadata structures,
    // not in the Mach-O __TEXT image. Return 0 immediately to avoid blocking IPC reads.
    return 0;
}

// MARK: - Dynamic ARM64 Static Fields Resolution

// Collects candidates reachable through ADRP + LDR/ADD sequences in ARM64 instructions.
// Pushes the data pointer, dereferenced values, and static_fields offsets.
static int CollectArm64StaticCandidates(RemoteCall *remoteCall,
                                        uintptr_t funcAddr, uintptr_t *out,
                                        int maxOut) {
    if (!remoteCall || !validOffsetPtr(funcAddr) || !out || maxOut <= 0)
        return 0;

    uint32_t insns[128] = {0};
    if (![remoteCall remoteRead:funcAddr to:insns size:sizeof(insns)])
        return 0;

    uintptr_t adrpTargets[32] = {0};
    uintptr_t regValues[32] = {0};
    int found = 0;

    for (int i = 0; i < 128 && found < maxOut; ++i) {
        uint32_t insn = insns[i];
        uintptr_t pc = funcAddr + (uintptr_t)i * 4;

        // RET instruction: end of function
        if (insn == 0xD65F03C0) {
            break;
        }

        // ADRP Xd, #imm
        if ((insn & 0x9F000000) == 0x90000000) {
            uint32_t rd = insn & 0x1F;
            int64_t immhi = (insn >> 5) & 0x7FFFF;
            int64_t immlo = (insn >> 29) & 0x3;
            int64_t imm = (immhi << 2) | immlo;
            if (imm & 0x100000) {
                imm |= 0xFFFFFFFFFFE00000LL;
            }
            imm <<= 12;
            adrpTargets[rd] = (pc & ~0xFFFULL) + imm;
            regValues[rd] = 0;
            continue;
        }

        // LDR Xt, [Xn, #imm12] (64-bit unsigned offset: size=3, opc=01 -> 0xF9400000)
        if ((insn & 0xFFC00000) == 0xF9400000) {
            uint32_t rt = insn & 0x1F;
            uint32_t rn = (insn >> 5) & 0x1F;
            uint32_t imm12 = ((insn >> 10) & 0xFFF) << 3;

            uintptr_t baseAddr = 0;
            if (adrpTargets[rn] != 0) {
                baseAddr = adrpTargets[rn] + imm12;
            } else if (regValues[rn] != 0) {
                baseAddr = regValues[rn] + imm12;
            }

            if (validOffsetPtr(baseAddr)) {
                PushCandidate(out, &found, maxOut, baseAddr);
                uintptr_t val = ReadMemorySafe<uintptr_t>(remoteCall, baseAddr);
                if (validOffsetPtr(val)) {
                    PushCandidate(out, &found, maxOut, val);
                    regValues[rt] = val;
                    // Dereferenced value
                    uintptr_t deref = ReadMemorySafe<uintptr_t>(remoteCall, val);
                    if (validOffsetPtr(deref)) {
                        PushCandidate(out, &found, maxOut, deref);
                    }
                    // static_fields offset (0xB8)
                    uintptr_t sf = ReadMemorySafe<uintptr_t>(remoteCall, val + kIl2CppClass_StaticFields);
                    if (validOffsetPtr(sf)) {
                        PushCandidate(out, &found, maxOut, sf);
                    }
                } else {
                    regValues[rt] = 0;
                }
            } else {
                regValues[rt] = 0;
            }
            if (rt != rn) {
                adrpTargets[rt] = 0;
            }
            continue;
        }

        // ADD Xd, Xn, #imm12 (64-bit: 0x91000000)
        if ((insn & 0xFF800000) == 0x91000000) {
            uint32_t rd = insn & 0x1F;
            uint32_t rn = (insn >> 5) & 0x1F;
            uint32_t imm12 = (insn >> 10) & 0xFFF;

            uintptr_t baseAddr = 0;
            if (adrpTargets[rn] != 0) {
                baseAddr = adrpTargets[rn] + imm12;
            } else if (regValues[rn] != 0) {
                baseAddr = regValues[rn] + imm12;
            }

            if (validOffsetPtr(baseAddr)) {
                PushCandidate(out, &found, maxOut, baseAddr);
                regValues[rd] = baseAddr;
                uintptr_t val = ReadMemorySafe<uintptr_t>(remoteCall, baseAddr);
                if (validOffsetPtr(val)) {
                    PushCandidate(out, &found, maxOut, val);
                    uintptr_t deref = ReadMemorySafe<uintptr_t>(remoteCall, val);
                    if (validOffsetPtr(deref)) {
                        PushCandidate(out, &found, maxOut, deref);
                    }
                    uintptr_t sf = ReadMemorySafe<uintptr_t>(remoteCall, val + kIl2CppClass_StaticFields);
                    if (validOffsetPtr(sf)) {
                        PushCandidate(out, &found, maxOut, sf);
                    }
                }
            } else {
                regValues[rd] = 0;
            }
            if (rd != rn) {
                adrpTargets[rd] = 0;
            }
            continue;
        }

        // If another instruction writes to rd, invalidate cached state
        uint32_t rd = insn & 0x1F;
        adrpTargets[rd] = 0;
        regValues[rd] = 0;
    }

    return found;
}

#endif /* FreeFireUtils_h */
