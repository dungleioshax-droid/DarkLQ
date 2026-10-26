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
    if (fabsf(w) < 1.0e-6f)
        return Vector3(0.0f, 0.0f, w);

    return Vector3(x / w * 0.5f + 0.5f, y / w * 0.5f + 0.5f, w);
}

static BOOL ProjectToOverlayPoint(Vector3 world, const float *viewProjection,
                                  CGFloat screenWidth, CGFloat screenHeight,
                                  CGFloat *outX, CGFloat *outY) {
    Vector3 viewport = WorldToViewportPoint(world, viewProjection);
    if (!std::isfinite(viewport.x) || !std::isfinite(viewport.y) ||
        !std::isfinite(viewport.z)) {
        return NO;
    }

    CGFloat x = 0.0;
    CGFloat y = 0.0;
    if (viewport.z > 0.0f) {
        x = viewport.x * screenWidth;
        y = (1.0f - viewport.y) * screenHeight;
    } else {
        x = (1.0f - viewport.x) * screenWidth;
        y = viewport.y * screenHeight;
    }

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

static bool ReadCameraVPAndWorldMatrix(RemoteCall *remoteCall, uintptr_t camera,
                                      float *outVP, float *outView) {
    if (!validOffsetPtr(camera) || !remoteCall || !outVP)
        return false;

    uintptr_t nativeCamera =
        ReadMemorySafe<uintptr_t>(remoteCall, camera + kUnityObject_CachedPtr);
    if (!validOffsetPtr(nativeCamera)) {
        nativeCamera = ReadMemorySafe<uintptr_t>(remoteCall, camera + 0x8);
        if (!validOffsetPtr(nativeCamera)) {
            nativeCamera = ReadMemorySafe<uintptr_t>(remoteCall, camera + 0x18);
        }
    }
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
            memcpy(outVP, viewProjection, sizeof(viewProjection));
            if (outView) {
                memcpy(outView, view, sizeof(view));
            }
            return true;
        }
    }

    if (ReadValidMatrix(remoteCall, nativeCamera + kNativeCamera_WorldToClip,
                        viewProjection) &&
        LooksLikeViewProjection(viewProjection)) {
        memcpy(outVP, viewProjection, sizeof(viewProjection));
        if (outView) {
            if (!ReadValidMatrix(remoteCall,
                                 nativeCamera + kNativeCamera_WorldToCamera,
                                 outView)) {
                memset(outView, 0, sizeof(float) * 16);
            }
        }
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
    if (!validOffsetPtr(managedTransform) || !remoteCall || !outPos)
        return false;

    uintptr_t nativeTransform = ReadMemorySafe<uintptr_t>(
        remoteCall, managedTransform + kUnityObject_CachedPtr);
    if (!validOffsetPtr(nativeTransform)) {
        nativeTransform = ReadMemorySafe<uintptr_t>(remoteCall, managedTransform + 0x8);
        if (!validOffsetPtr(nativeTransform)) {
            nativeTransform = ReadMemorySafe<uintptr_t>(remoteCall, managedTransform + 0x18);
        }
    }
    if (!validOffsetPtr(nativeTransform))
        return false;

    // TransformAccessReadOnly at nativeTransform + 0x38
    uintptr_t pTransformAccess =
        ReadMemorySafe<uintptr_t>(remoteCall, nativeTransform + 0x38);
    int32_t index =
        ReadMemorySafe<int32_t>(remoteCall, nativeTransform + 0x40);

    if (validOffsetPtr(pTransformAccess) && index >= 0 && index < 20000) {
        uintptr_t pTransformArray =
            ReadMemorySafe<uintptr_t>(remoteCall, pTransformAccess + 0x18);
        if (!validOffsetPtr(pTransformArray)) {
            pTransformArray =
                ReadMemorySafe<uintptr_t>(remoteCall, pTransformAccess);
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
    uintptr_t transform =
        ReadMemorySafe<uintptr_t>(remoteCall, entity + kEntity_CachedTransform);
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

static bool ReadIl2CppClassName(RemoteCall *remoteCall, uintptr_t object,
                                char *out, size_t capacity) {
    if (!remoteCall || !out || capacity == 0)
        return false;

    out[0] = '\0';
    if (!validOffsetPtr(object))
        return false;

    uintptr_t klass = ReadMemorySafe<uintptr_t>(remoteCall, object);
    if (!validOffsetPtr(klass))
        return false;

    uintptr_t namePtr =
        ReadMemorySafe<uintptr_t>(remoteCall, klass + kIl2CppClass_Name);
    if (!validOffsetPtr(namePtr))
        return false;

    char buffer[64] = {0};
    if (![remoteCall remoteRead:namePtr to:buffer size:sizeof(buffer) - 1])
        return false;

    size_t length = 0;
    while (length < sizeof(buffer) && buffer[length] != '\0')
        ++length;
    if (length == 0 || length >= capacity)
        return false;

    memcpy(out, buffer, length);
    out[length] = '\0';
    return true;
}

static bool IsSubclassOf(RemoteCall *remoteCall, uintptr_t object,
                         const char *targetName) {
    if (!remoteCall || !validOffsetPtr(object) || !targetName)
        return false;

    uintptr_t klass = ReadMemorySafe<uintptr_t>(remoteCall, object);
    for (int depth = 0; depth < 10 && validOffsetPtr(klass); ++depth) {
        uintptr_t namePtr =
            ReadMemorySafe<uintptr_t>(remoteCall, klass + kIl2CppClass_Name);
        if (validOffsetPtr(namePtr)) {
            char buffer[64] = {0};
            if ([remoteCall remoteRead:namePtr to:buffer size:sizeof(buffer) - 1]) {
                buffer[sizeof(buffer) - 1] = '\0';
                if (strstr(buffer, targetName) != NULL) {
                    return true;
                }
            }
        }
        klass = ReadMemorySafe<uintptr_t>(remoteCall, klass + kIl2CppClass_Parent);
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

static bool FieldHoldsMatchGame(RemoteCall *remoteCall, uintptr_t value) {
    return IsSubclassOf(remoteCall, value, "MatchGame") ||
           IsSubclassOf(remoteCall, value, "COWGameBase") ||
           Il2CppClassNameContains(remoteCall, value, "MatchGame");
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

static bool IsDictionaryObject(RemoteCall *remoteCall, uintptr_t object) {
    return Il2CppClassNameContains(remoteCall, object, "Dictionary");
}

// Replication dictionaries are the ones whose values are Player objects.
static bool LooksLikePlayerDictionary(RemoteCall *remoteCall, uintptr_t dict) {
    if (!IsDictionaryObject(remoteCall, dict))
        return false;

    int32_t count =
        ReadMemorySafe<int32_t>(remoteCall, dict + kDictionary_Count);
    if (count < 0 || count > 10000)
        return false;
    if (count == 0)
        return true;

    uintptr_t entries =
        ReadMemorySafe<uintptr_t>(remoteCall, dict + kDictionary_Entries);
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

        uintptr_t value =
            ReadMemorySafe<uintptr_t>(remoteCall, entryAddr + kEntry_Value);
        if (validOffsetPtr(value) &&
            (IsSubclassOf(remoteCall, value, "Player") ||
             Il2CppClassNameContains(remoteCall, value, "Player")))
            return true;
    }

    return false;
}

static uint64_t FindIl2CppFieldMatching(
    RemoteCall *remoteCall, uintptr_t object, uint64_t endOffset,
    bool (*predicate)(RemoteCall *, uintptr_t)) {
    if (!remoteCall || !predicate || !validOffsetPtr(object))
        return 0;

    for (uint64_t offset = 0x10;
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

// MARK: - Dynamic ARM64 Static Fields Resolution

static uintptr_t DecodeArm64AdrLdr(RemoteCall *remoteCall, uintptr_t funcAddr) {
    if (!validOffsetPtr(funcAddr) || !remoteCall)
        return 0;

    uint32_t insns[32] = {0};
    if (![remoteCall remoteRead:funcAddr to:insns size:sizeof(insns)])
        return 0;

    uintptr_t adrpTargets[32] = {0};

    for (int i = 0; i < 32; ++i) {
        uint32_t insn = insns[i];
        uintptr_t pc = funcAddr + (uintptr_t)i * 4;

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
            continue;
        }

        // LDR Xt, [Xn, #imm12] (64-bit)
        if ((insn & 0xFFC00000) == 0xF9400000) {
            uint32_t rn = (insn >> 5) & 0x1F;
            if (adrpTargets[rn] != 0) {
                uint32_t imm12 = ((insn >> 10) & 0xFFF) << 3;
                uintptr_t ptrAddr = adrpTargets[rn] + imm12;
                uintptr_t resolved = ReadMemorySafe<uintptr_t>(remoteCall, ptrAddr);
                if (validOffsetPtr(resolved))
                    return resolved;
            }
        }

        // ADD Xd, Xn, #imm12 (64-bit)
        if ((insn & 0xFF800000) == 0x91000000) {
            uint32_t rn = (insn >> 5) & 0x1F;
            if (adrpTargets[rn] != 0) {
                uint32_t imm12 = (insn >> 10) & 0xFFF;
                uintptr_t targetAddr = adrpTargets[rn] + imm12;
                if (validOffsetPtr(targetAddr)) {
                    uintptr_t deref = ReadMemorySafe<uintptr_t>(remoteCall, targetAddr);
                    if (validOffsetPtr(deref))
                        return deref;
                    return targetAddr;
                }
            }
        }
    }

    return 0;
}

#endif /* FreeFireUtils_h */
