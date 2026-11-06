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
    address = address & 0x7fffffffffULL;
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

    for (int i = 0; i < 16; ++i) {
        if (!std::isfinite(matrix[i]) || fabsf(matrix[i]) > 100000.0f)
            return false;
    }

    // In Unity column-major ViewProjection matrix:
    // w = matrix[3]*x + matrix[7]*y + matrix[11]*z + matrix[15]
    // The forward direction vector (matrix[3], matrix[7], matrix[11]) in world space
    // MUST have length squared approximately 1.0 (typically 0.01 to 25.0).
    float colForwardLenSq = matrix[3] * matrix[3] +
                            matrix[7] * matrix[7] +
                            matrix[11] * matrix[11];

    // Row-major transpose check just in case:
    float rowForwardLenSq = matrix[12] * matrix[12] +
                            matrix[13] * matrix[13] +
                            matrix[14] * matrix[14];

    bool validCol = (colForwardLenSq > 0.01f && colForwardLenSq < 25.0f);
    bool validRow = (rowForwardLenSq > 0.01f && rowForwardLenSq < 25.0f);

    if (!validCol && !validRow)
        return false;

    return true;
}

// Native camera matrix offsets drift between Unity builds; remember the ones
// that actually produced a valid view-projection matrix so we don't keep
// guessing every frame.
static uint64_t gFreeFireNativeCameraViewOffset = kNativeCamera_WorldToCamera;
static uint64_t gFreeFireNativeCameraProjectionOffset = kNativeCamera_Projection;
static uint64_t gFreeFireNativeCameraWorldToClipOffset = kNativeCamera_Fl0rkWorldToClip;
static bool gFreeFireNativeCameraOffsetsResolved = false;

static bool ReadCameraVPAndWorldMatrix(RemoteCall *remoteCall, uintptr_t camera,
                                      float *outVP, float *outView) {
    if (!validOffsetPtr(camera) || !checkPointer64bits(camera) || !remoteCall || !outVP)
        return false;

    camera = CleanPointer(camera);

    uintptr_t nativeCandidates[6] = {0};
    int numNative = 0;

    // 1. Component m_CachedPtr at +0x10 (Fl0rk: v1 = ReadAddr(cameraMain + 0x10))
    uintptr_t n10 = CleanPointer(
        ReadMemorySafe<uintptr_t>(remoteCall, camera + kUnityObject_CachedPtr));
    if (validOffsetPtr(n10)) nativeCandidates[numNative++] = n10;

    // 2. Camera pointer itself (in case camera is already native Camera*)
    nativeCandidates[numNative++] = camera;

    // 3. Offsets 0x8, 0x18, 0x20
    for (uint64_t off : { (uint64_t)0x8, (uint64_t)0x18, (uint64_t)0x20 }) {
        uintptr_t nc = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, camera + off));
        if (validOffsetPtr(nc)) nativeCandidates[numNative++] = nc;
    }

    uint64_t candidateViewOffsets[] = {
        gFreeFireNativeCameraViewOffset, kNativeCamera_WorldToCamera, 0x70, 0x80, 0x90, 0xA0
    };
    uint64_t candidateProjOffsets[] = {
        gFreeFireNativeCameraProjectionOffset, kNativeCamera_Projection, 0xB0, 0xC0, 0xD0, 0xE0
    };
    uint64_t candidateClipOffsets[] = {
        gFreeFireNativeCameraWorldToClipOffset,
        kNativeCamera_Fl0rkWorldToClip, // 0xD8 (Fl0rk reference WorldToClip matrix)
        kNativeCamera_WorldToClip,      // 0x100
        0x80, 0xC0, 0xF0, 0x110, 0x120, 0x130, 0x140, 0x180, 0x1C0, 0x200
    };

    for (int candIdx = 0; candIdx < numNative; ++candIdx) {
        uintptr_t nativeCamera = nativeCandidates[candIdx];
        if (!validOffsetPtr(nativeCamera)) continue;

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
            if (fabsf(viewProjection[3]) < 1e-4f && fabsf(viewProjection[7]) < 1e-4f &&
                fabsf(viewProjection[11]) < 1e-4f && fabsf(viewProjection[15]) < 1e-4f) {
                return false;
            }
            memcpy(outVP, viewProjection, sizeof(viewProjection));
            if (outView) {
                bool foundView = false;
                const uint64_t vOffsets[] = {
                    gFreeFireNativeCameraViewOffset, kNativeCamera_WorldToCamera, 0x70, 0x80, 0x90, 0xA0
                };
                for (uint64_t vo : vOffsets) {
                    if (ReadValidMatrix(remoteCall, nativeCamera + vo, outView)) {
                        foundView = true;
                        gFreeFireNativeCameraViewOffset = vo;
                        break;
                    }
                }
                if (!foundView) {
                    memset(outView, 0, sizeof(float) * 16);
                }
            }
            gFreeFireNativeCameraWorldToClipOffset = clipOff;
            gFreeFireNativeCameraOffsetsResolved = true;
            return true;
        };

        // Check direct WorldToClip first (matches Fl0rk)
        for (size_t i = 0;
             i < sizeof(candidateClipOffsets) / sizeof(candidateClipOffsets[0]);
             ++i) {
            if (tryWorldToClip(candidateClipOffsets[i]))
                return true;
        }

        // Check View * Projection
        for (size_t i = 0;
             i < sizeof(candidateViewOffsets) / sizeof(candidateViewOffsets[0]);
             ++i) {
            if (tryViewProjection(candidateViewOffsets[i],
                                  candidateProjOffsets[i]))
                return true;
        }

        // Fast consecutive matrix block discovery
        for (uint64_t baseOff = 0x50; baseOff <= 0x140; baseOff += 0x8) {
            if (tryWorldToClip(baseOff))
                return true;
            if (tryViewProjection(baseOff, baseOff + 0x40))
                return true;
        }
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

// MARK: - Pure Memory Transform & Entity Position (Fl0rk Reference Implementation)

struct UnityVector4 {
    float x, y, z, w;
};

struct UnityQuaternion {
    float x, y, z, w;
};

struct UnityTMatrix {
    UnityVector4 position;
    UnityQuaternion rotation;
    UnityVector4 scale;
};

static Vector3 GetPositionExt(RemoteCall *remoteCall, uintptr_t transObj2) {
    transObj2 = CleanPointer(transObj2);
    if (!validOffsetPtr(transObj2) || !remoteCall)
        return Vector3::zero();

    uintptr_t transObj = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, transObj2 + 0x10));
    if (!validOffsetPtr(transObj)) {
        transObj = transObj2;
    }

    uintptr_t matrix = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, transObj + 0x38));
    int32_t index = ReadMemorySafe<int32_t>(remoteCall, transObj + 0x40);
    if (!validOffsetPtr(matrix) || index < 0 || index > 50000)
        return Vector3::zero();

    uintptr_t matrix_list = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, matrix + 0x18));
    uintptr_t matrix_indices = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, matrix + 0x20));
    if (!validOffsetPtr(matrix_list) || !validOffsetPtr(matrix_indices))
        return Vector3::zero();

    UnityTMatrix rootMat = ReadMemorySafe<UnityTMatrix>(remoteCall, matrix_list + sizeof(UnityTMatrix) * index);
    Vector3 result(rootMat.position.x, rootMat.position.y, rootMat.position.z);
    int transformIndex = ReadMemorySafe<int>(remoteCall, matrix_indices + sizeof(int) * index);

    int depth = 0;
    while (transformIndex >= 0 && depth++ < 100) {
        UnityTMatrix tMatrix = ReadMemorySafe<UnityTMatrix>(remoteCall, matrix_list + sizeof(UnityTMatrix) * transformIndex);

        float rotX = tMatrix.rotation.x;
        float rotY = tMatrix.rotation.y;
        float rotZ = tMatrix.rotation.z;
        float rotW = tMatrix.rotation.w;

        float scaleX = result.x * tMatrix.scale.x;
        float scaleY = result.y * tMatrix.scale.y;
        float scaleZ = result.z * tMatrix.scale.z;

        result.x = tMatrix.position.x + scaleX +
                    (scaleX * ((rotY * rotY * -2.0f) - (rotZ * rotZ * 2.0f))) +
                    (scaleY * ((rotW * rotZ * -2.0f) - (rotY * rotX * -2.0f))) +
                    (scaleZ * ((rotZ * rotX * 2.0f) - (rotW * rotY * -2.0f)));
        result.y = tMatrix.position.y + scaleY +
                    (scaleX * ((rotX * rotY * 2.0f) - (rotW * rotZ * -2.0f))) +
                    (scaleY * ((rotZ * rotZ * -2.0f) - (rotX * rotX * 2.0f))) +
                    (scaleZ * ((rotW * rotX * -2.0f) - (rotZ * rotY * -2.0f)));
        result.z = tMatrix.position.z + scaleZ +
                    (scaleX * ((rotW * rotY * -2.0f) - (rotX * rotZ * -2.0f))) +
                    (scaleY * ((rotY * rotZ * 2.0f) - (rotW * rotX * -2.0f))) +
                    (scaleZ * ((rotX * rotX * -2.0f) - (rotY * rotY * 2.0f)));

        transformIndex = ReadMemorySafe<int>(remoteCall, matrix_indices + sizeof(int) * transformIndex);
    }

    if (std::isfinite(result.x) && std::isfinite(result.y) && std::isfinite(result.z) &&
        (fabsf(result.x) > 0.01f || fabsf(result.y) > 0.01f || fabsf(result.z) > 0.01f) &&
        fabsf(result.x) < 50000.0f && fabsf(result.z) < 50000.0f) {
        return result;
    }

    return Vector3::zero();
}

struct UnityMatrix3x4 {
    float data[12];
};

static bool ReadTransformPosition(RemoteCall *remoteCall,
                                  uintptr_t managedTransform, Vector3 *outPos) {
    managedTransform = CleanPointer(managedTransform);
    if (!validOffsetPtr(managedTransform) || !remoteCall || !outPos)
        return false;

    // Try Fl0rk hierarchical calculation first
    Vector3 extPos = GetPositionExt(remoteCall, managedTransform);
    if (extPos.x != 0.0f || extPos.y != 0.0f || extPos.z != 0.0f) {
        *outPos = extPos;
        return true;
    }

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

    // TransformAccessReadOnly at nativeTransform + 0x38 / 0x40 / 0x30 / 0x28
    const uint64_t kAccessOffsets[] = { 0x38, 0x40, 0x30, 0x28, 0x48 };
    for (uint64_t accOff : kAccessOffsets) {
        uintptr_t pTransformAccess =
            CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, nativeTransform + accOff));
        int32_t index =
            ReadMemorySafe<int32_t>(remoteCall, nativeTransform + accOff + 0x8);

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
    }

    return false;
}

static bool ReadEntityPosition(RemoteCall *remoteCall, uintptr_t entity,
                               Vector3 *outPos) {
    if (!validOffsetPtr(entity) || !remoteCall || !outPos)
        return false;

    // 1. Try Head / Toe bones via Fl0rk BodyPart offsets
    uintptr_t headBodyPart = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, entity + kPlayer_HeadBodyPart)); // 0x550
    if (validOffsetPtr(headBodyPart)) {
        uintptr_t headTrans = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, headBodyPart + 0x10));
        Vector3 head = GetPositionExt(remoteCall, headTrans);
        if (head.x != 0.0f || head.y != 0.0f || head.z != 0.0f) {
            *outPos = head;
            return true;
        }
    }

    uintptr_t toeBodyPart = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, entity + kPlayer_RightToeBodyPart)); // 0x5A0
    if (validOffsetPtr(toeBodyPart)) {
        uintptr_t toeTrans = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, toeBodyPart + 0x10));
        Vector3 toe = GetPositionExt(remoteCall, toeTrans);
        if (toe.x != 0.0f || toe.y != 0.0f || toe.z != 0.0f) {
            *outPos = toe;
            return true;
        }
    }

    // 2. Try CachedTransform
    uintptr_t transform = CleanPointer(
        ReadMemorySafe<uintptr_t>(remoteCall, entity + kEntity_CachedTransform));
    if (validOffsetPtr(transform)) {
        if (ReadTransformPosition(remoteCall, transform, outPos)) {
            return true;
        }
    }

    // 3. Try Vector3 fields in Player / AttackableEntity / Training Targets
    static const uint64_t kCandidateVecOffsets[] = {
        kPlayer_Position1, // 0xD0
        kPlayer_Position2, // 0x10C
        0x214,             // <KFIOIKIHPPD>k__BackingField
        0x238,             // DICMMHDGPII
        kPlayer_Position3, // 0x270
        0x24D4             // MGIGJOPFDMD (Training Human Target)
    };

    for (uint64_t off : kCandidateVecOffsets) {
        Vector3 v = ReadMemorySafe<Vector3>(remoteCall, entity + off);
        if (std::isfinite(v.x) && std::isfinite(v.y) && std::isfinite(v.z) &&
            (fabsf(v.x) > 0.1f || fabsf(v.z) > 0.1f) &&
            fabsf(v.x) < 50000.0f && fabsf(v.z) < 50000.0f) {
            *outPos = v;
            return true;
        }
    }

    return false;
}

// MARK: - Il2Cpp String Reading

static NSString *ReadIl2CppString(RemoteCall *remoteCall, uintptr_t stringAddr) {
    if (!validOffsetPtr(stringAddr) || !remoteCall)
        return @"";

    stringAddr = CleanPointer(stringAddr);

    int32_t length =
        ReadMemorySafe<int32_t>(remoteCall, stringAddr + kSystemString_Length);
    if (length > 0 && length <= 128) {
        uint16_t buffer[129] = {0};
        size_t readBytes = (size_t)length * sizeof(uint16_t);
        if ([remoteCall remoteRead:stringAddr + kSystemString_Chars
                                 to:buffer
                               size:readBytes]) {
            buffer[length] = 0;
            return [NSString stringWithCharacters:buffer length:length];
        }
    }

    // Direct UTF16 fallback (Fl0rk pattern: read chars at stringAddr + 0x14)
    uint16_t rawBuf[32] = {0};
    if ([remoteCall remoteRead:stringAddr + kSystemString_Chars to:rawBuf size:sizeof(rawBuf)]) {
        size_t rawLen = 0;
        while (rawLen < 31 && rawBuf[rawLen] != 0 && rawBuf[rawLen] >= 0x20 && rawBuf[rawLen] < 0xD800) {
            ++rawLen;
        }
        if (rawLen > 0) {
            return [NSString stringWithCharacters:rawBuf length:rawLen];
        }
    }

    return @"";
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

static inline uintptr_t CleanStringAddress(uintptr_t p) {
    return p & 0x7fffffffffULL; // Strip PAC/TBI bits, keep byte alignment
}

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
            uintptr_t rawName = ReadMemorySafe<uintptr_t>(remoteCall, kAddr + off);
            uintptr_t namePtr = CleanStringAddress(rawName);
            if (namePtr < 0x10000 || namePtr >= 0x80000000000ULL)
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

static bool IsLikelyPlayerOrTarget(RemoteCall *remoteCall, uintptr_t entity,
                                   char *outClassName, size_t classCap,
                                   bool isDedicatedPlayerContainer) {
    if (!remoteCall || !validOffsetPtr(entity))
        return false;
    entity = CleanPointer(entity);
    if (outClassName && classCap > 0)
        outClassName[0] = '\0';

    // 1. Check Skeleton Bones (Fl0rk Head & Toe BodyPart)
    // Humanoid players, bots, and training human targets have Head (0x550) or RightToe (0x5A0) body parts.
    // Static props, weapons, vehicles, and buildings NEVER have these body parts.
    uintptr_t headBp = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, entity + kPlayer_HeadBodyPart)); // 0x550
    uintptr_t toeBp = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, entity + kPlayer_RightToeBodyPart)); // 0x5A0
    if (validOffsetPtr(headBp) || validOffsetPtr(toeBp)) {
        if (outClassName && classCap > 0 && outClassName[0] == '\0') {
            ReadIl2CppClassName(remoteCall, entity, outClassName, classCap);
            if (outClassName[0] == '\0') {
                strncpy(outClassName, "Player", classCap - 1);
            }
        }
        return true;
    }

    // 2. Check HP Data Pool (IPRIDataPool at 0x68)
    // Real Player instances have an IPRIDataPool pointer containing CurHP/MaxHP.
    uintptr_t ipriPool = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, entity + kPlayer_IPRIDataPool)); // 0x68
    if (validOffsetPtr(ipriPool)) {
        uintptr_t v2 = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, ipriPool + 0x10));
        if (validOffsetPtr(v2)) {
            if (outClassName && classCap > 0 && outClassName[0] == '\0') {
                ReadIl2CppClassName(remoteCall, entity, outClassName, classCap);
                if (outClassName[0] == '\0') {
                    strncpy(outClassName, "Player", classCap - 1);
                }
            }
            return true;
        }
    }

    // 3. Check Class Name
    char className[64] = {0};
    if (ReadIl2CppClassName(remoteCall, entity, className, sizeof(className)) && className[0] != '\0') {
        if (outClassName && classCap > 0) {
            strncpy(outClassName, className, classCap - 1);
            outClassName[classCap - 1] = '\0';
        }
        if (strstr(className, "Player") != NULL ||
            strstr(className, "Target") != NULL ||
            strstr(className, "Dummy") != NULL ||
            strstr(className, "Human") != NULL ||
            strstr(className, "AIPawn") != NULL ||
            strstr(className, "Bot") != NULL ||
            strstr(className, "Stand") != NULL ||
            IsSubclassOf(remoteCall, entity, "Player") ||
            IsSubclassOf(remoteCall, entity, "AttackableEntity")) {
            return true;
        }
    }

    // 4. In dedicated player / training target containers:
    // Any entity with a valid 3D position (via bones, CachedTransform, or vector fields) is confirmed!
    if (isDedicatedPlayerContainer) {
        Vector3 targetPos = Vector3::zero();
        if (ReadEntityPosition(remoteCall, entity, &targetPos)) {
            if (std::isfinite(targetPos.x) && std::isfinite(targetPos.y) && std::isfinite(targetPos.z) &&
                (fabsf(targetPos.x) > 0.1f || fabsf(targetPos.z) > 0.1f) &&
                fabsf(targetPos.x) < 50000.0f && fabsf(targetPos.z) < 50000.0f) {
                if (outClassName && classCap > 0 && outClassName[0] == '\0') {
                    strncpy(outClassName, "Target", classCap - 1);
                }
                return true;
            }
        }
    }

    return false;
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
    uint32_t entrySize = 0x18;
    uint32_t valueOffset = 0x10;
};

static inline bool DetectDictionaryLayout(RemoteCall *remoteCall, uintptr_t entries,
                                           int32_t dictCount, int32_t arrLen,
                                           uint32_t *outEntrySize, uint32_t *outValOffset) {
    if (!remoteCall || !validOffsetPtr(entries) || arrLen <= 0 || !outEntrySize || !outValOffset)
        return false;

    // Default layout (e.g. Dictionary<uint, Entity>, Dictionary<byte, Player>, etc.)
    *outEntrySize = 0x18;
    *outValOffset = 0x10;

    int scanCount = std::min(arrLen, 16);
    int valid28 = 0;
    int valid18 = 0;
    int confirmed28 = 0;
    int confirmed18 = 0;

    // Test Layout 0x28 (stride = 0x28, valOffset = 0x20)
    for (int i = 0; i < scanCount; ++i) {
        uintptr_t entryAddr = entries + kArray_Vector + (uint64_t)i * 0x28;
        int32_t hc = ReadMemorySafe<int32_t>(remoteCall, entryAddr + kEntry_HashCode);
        if (hc < 0) continue;
        uintptr_t val = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, entryAddr + 0x20));
        if (validOffsetPtr(val)) {
            valid28++;
            uintptr_t klass = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, val)) & ~7ULL;
            if (validOffsetPtr(klass)) {
                char className[64] = {0};
                if (ReadKlassName(remoteCall, klass, className, sizeof(className))) {
                    if (strstr(className, "Player") != NULL ||
                        strstr(className, "Entity") != NULL ||
                        strstr(className, "Target") != NULL ||
                        strstr(className, "Pawn") != NULL ||
                        strstr(className, "Human") != NULL ||
                        strstr(className, "Dummy") != NULL ||
                        strstr(className, "Stand") != NULL) {
                        confirmed28 += 10;
                    }
                }
            }
            Vector3 pos = Vector3::zero();
            if (ReadEntityPosition(remoteCall, val, &pos)) {
                confirmed28 += 10;
            }
        }
    }

    // Test Layout 0x18 (stride = 0x18, valOffset = 0x10)
    for (int i = 0; i < scanCount; ++i) {
        uintptr_t entryAddr = entries + kArray_Vector + (uint64_t)i * 0x18;
        int32_t hc = ReadMemorySafe<int32_t>(remoteCall, entryAddr + kEntry_HashCode);
        if (hc < 0) continue;
        uintptr_t val = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, entryAddr + 0x10));
        if (validOffsetPtr(val)) {
            valid18++;
            uintptr_t klass = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, val)) & ~7ULL;
            if (validOffsetPtr(klass)) {
                char className[64] = {0};
                if (ReadKlassName(remoteCall, klass, className, sizeof(className))) {
                    if (strstr(className, "Player") != NULL ||
                        strstr(className, "Entity") != NULL ||
                        strstr(className, "Target") != NULL ||
                        strstr(className, "Pawn") != NULL ||
                        strstr(className, "Human") != NULL ||
                        strstr(className, "Dummy") != NULL ||
                        strstr(className, "Stand") != NULL) {
                        confirmed18 += 10;
                    }
                }
            }
            Vector3 pos = Vector3::zero();
            if (ReadEntityPosition(remoteCall, val, &pos)) {
                confirmed18 += 10;
            }
        }
    }

    if (confirmed28 > confirmed18) {
        *outEntrySize = 0x28;
        *outValOffset = 0x20;
        return true;
    } else if (confirmed18 > 0) {
        *outEntrySize = 0x18;
        *outValOffset = 0x10;
        return true;
    } else if (valid28 > valid18 && valid28 > 0) {
        *outEntrySize = 0x28;
        *outValOffset = 0x20;
        return true;
    } else {
        *outEntrySize = 0x18;
        *outValOffset = 0x10;
        return true;
    }
}

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
            outContainer->entrySize = 0x18;
            outContainer->valueOffset = 0x10;

            if (dictCount > 0) {
                DetectDictionaryLayout(remoteCall, entries, dictCount, arrLen,
                                       &outContainer->entrySize,
                                       &outContainer->valueOffset);
            }
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
            outContainer->entrySize = sizeof(uintptr_t);
            outContainer->valueOffset = 0;
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
            outContainer->entrySize = sizeof(uintptr_t);
            outContainer->valueOffset = 0;
            return true;
        }
    }

    // 4. Check direct Array: 0x18 = length
    int32_t directArrLen = ReadMemorySafe<int32_t>(remoteCall, cand + kArray_Length);
    if (directArrLen > 0 && directArrLen <= 2000) {
        uintptr_t bounds = ReadMemorySafe<uintptr_t>(remoteCall, cand + 0x10);
        if (bounds == 0 || validOffsetPtr(bounds)) {
            outContainer->container = cand;
            outContainer->containerType = kContainerType_Array;
            outContainer->isList = true;
            outContainer->count = directArrLen;
            outContainer->arrayPtr = cand;
            outContainer->head = 0;
            outContainer->capacity = directArrLen;
            outContainer->entrySize = sizeof(uintptr_t);
            outContainer->valueOffset = 0;
            return true;
        }
    }

    return false;
}

static inline uintptr_t GetEntityFromContainer(RemoteCall *remoteCall,
                                               const FreeFireEntityContainer &c,
                                               int32_t index) {
    if (!remoteCall || !validOffsetPtr(c.arrayPtr) || index < 0)
        return 0;

    switch (c.containerType) {
        case kContainerType_Dictionary: {
            if (index >= c.capacity)
                return 0;
            uint64_t entrySize = c.entrySize > 0 ? c.entrySize : kEntry_Size;
            uint64_t valOffset = c.valueOffset > 0 ? c.valueOffset : kEntry_Value;
            uintptr_t entryAddr = c.arrayPtr + kArray_Vector + (uint64_t)index * entrySize;
            int32_t hashCode = ReadMemorySafe<int32_t>(remoteCall, entryAddr + kEntry_HashCode);
            if (hashCode < 0)
                return 0;
            return CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, entryAddr + valOffset));
        }
        case kContainerType_Queue: {
            if (c.capacity <= 0 || index >= c.count) return 0;
            int32_t qIndex = (c.head + index) % c.capacity;
            return CleanPointer(ReadMemorySafe<uintptr_t>(
                remoteCall, c.arrayPtr + kArray_Vector + (uint64_t)qIndex * sizeof(uintptr_t)));
        }
        case kContainerType_List:
        case kContainerType_Array:
        default: {
            if (index >= c.count) return 0;
            return CleanPointer(ReadMemorySafe<uintptr_t>(
                remoteCall, c.arrayPtr + kArray_Vector + (uint64_t)index * sizeof(uintptr_t)));
        }
    }
}

static bool IsDictionaryObject(RemoteCall *remoteCall, uintptr_t object) {
    if (!remoteCall || !validOffsetPtr(object))
        return false;

    // Fast structural dictionary check first (avoids IPC string reads)
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

    if (Il2CppClassNameContains(remoteCall, object, "Dictionary"))
        return true;

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

    // 1. Fl0rk reference match container check at 0xC8 -> + 0x28
    uintptr_t florkC8 = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, matchObj + kMatch_C8));
    if (validOffsetPtr(florkC8)) {
        uintptr_t florkArr = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, florkC8 + kMatch_C8_Array));
        if (validOffsetPtr(florkArr)) {
            int32_t len = ReadMemorySafe<int32_t>(remoteCall, florkArr + kArray_Length);
            if (len >= 0 && len <= 2000) return true;
        }
    }

    // 2. Fl0rk local player check at 0x58
    uintptr_t localPlayer = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, matchObj + kMatch_LocalPlayer));
    if (validOffsetPtr(localPlayer)) {
        return true;
    }

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
        if (shaped >= 1)
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

    // Structural validation fallback. Check CameraControllerManager at 0xD8 first (Fl0rk pattern)
    uintptr_t camMgr = CleanPointer(
        ReadMemorySafe<uintptr_t>(remoteCall, value + kMatchGame_CameraControllerManager));
    if (validOffsetPtr(camMgr)) {
        if (LooksLikeCameraManager(remoteCall, camMgr)) return true;
        uintptr_t c0 = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, camMgr + kCameraControllerManager_CameraMain));
        if (validOffsetPtr(c0) && checkPointer64bits(c0)) return true;
        uintptr_t c1 = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, camMgr + kCameraControllerManager_MainCamera));
        if (validOffsetPtr(c1) && checkPointer64bits(c1)) return true;
    }

    // Check m_Match object at 0x90
    uintptr_t matchObj = CleanPointer(
        ReadMemorySafe<uintptr_t>(remoteCall, value + kMatchGame_Match));
    if (LooksLikeMatchObject(remoteCall, matchObj))
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

    uintptr_t fallbackSf = 0;
    for (int k = 0; k < 2; ++k) {
        uintptr_t rootKlass = klasses[k];
        if (!validOffsetPtr(rootKlass)) continue;
        uintptr_t klass = rootKlass & ~7ULL;
        for (int depth = 0; depth < 8 && validOffsetPtr(klass); ++depth) {
            char name[64] = {0};
            if (ReadKlassName(remoteCall, klass, name, sizeof(name))) {
                if (strcmp(name, "BaseGame") == 0 || strstr(name, "BaseGame") != NULL) {
                    uintptr_t sf = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, klass + kIl2CppClass_StaticFields));
                    if (validOffsetPtr(sf)) {
                        return sf;
                    }
                }
            }

            // Structural check: check if klass->static_fields holds BaseGame dictionaries
            uintptr_t sf = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, klass + kIl2CppClass_StaticFields));
            if (validOffsetPtr(sf)) {
                uintptr_t d0 = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, sf + kBaseGameStatic_sTickedEntities));
                uintptr_t d8 = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, sf + kBaseGameStatic_sAllEntities));
                if ((validOffsetPtr(d8) && IsDictionaryObject(remoteCall, d8)) ||
                    (validOffsetPtr(d0) && IsDictionaryObject(remoteCall, d0))) {
                    return sf;
                }
                if (fallbackSf == 0 && (validOffsetPtr(d8) || validOffsetPtr(d0))) {
                    fallbackSf = sf;
                }
            }
            klass = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, klass + kIl2CppClass_Parent)) & ~7ULL;
        }
    }
    return fallbackSf;
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
        for (uint64_t slot : slots) {
            uintptr_t dict = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, staticFields + slot));
            if (validOffsetPtr(dict) && IsDictionaryObject(remoteCall, dict)) {
                int32_t cnt = ReadMemorySafe<int32_t>(remoteCall, dict + kDictionary_Count);
                if (cnt > 0)
                    return dict;
            }
        }
        uintptr_t allEnt = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, staticFields + kBaseGameStatic_sAllEntities));
        if (validOffsetPtr(allEnt) && IsDictionaryObject(remoteCall, allEnt)) {
            return allEnt;
        }
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
    if (!validOffsetPtr(value) || !checkPointer64bits(value))
        return false;
    value = CleanPointer(value);
    char name[64] = {0};
    if (ReadIl2CppClassName(remoteCall, value, name, sizeof(name))) {
        if (strstr(name, "Camera") != NULL || strstr(name, "Cam") != NULL)
            return true;
    }
    // Authoritative check: does reading native Camera produce a valid ViewProjection matrix?
    float testVP[16] = {};
    if (ReadCameraVPAndWorldMatrix(remoteCall, value, testVP, NULL))
        return true;

    return false;
}

// A camera manager either carries its type in the class name or owns a
// UnityEngine.Camera reference in one of its first fields.
static bool LooksLikeCameraManager(RemoteCall *remoteCall, uintptr_t object) {
    if (!validOffsetPtr(object) || !checkPointer64bits(object))
        return false;
    object = CleanPointer(object);

    if (Il2CppClassNameContains(remoteCall, object, "CameraController") ||
        Il2CppClassNameContains(remoteCall, object, "CameraManager"))
        return true;

    // Check Fl0rk camera at 0x18, then dump offsets 0x20 and 0x28
    const uint64_t candidateOffsets[] = {
        kCameraControllerManager_CameraMain, // 0x18 (Fl0rk)
        kCameraControllerManager_MainCamera, // 0x20
        kCameraControllerManager_SubCamera,  // 0x28
        0x10, 0x30, 0x38, 0x40
    };
    for (uint64_t off : candidateOffsets) {
        uintptr_t cand = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, object + off));
        if (validOffsetPtr(cand) && FieldHoldsCamera(remoteCall, cand))
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

static uintptr_t ResolveBaseGameStaticFieldsFromARM64(RemoteCall *remoteCall, uintptr_t binaryBase) {
    if (!remoteCall || !validOffsetPtr(binaryBase))
        return 0;

    const uint64_t accessorRVAs[] = {
        kBaseGame_CCtor,
        kBaseGame_GetEntityByUniqueID,
        kBaseGame_RegisterEntity,
        kBaseGame_HideAllEntity,
        kBaseGame_UnregisterEntity
    };

    for (uint64_t rva : accessorRVAs) {
        uintptr_t candidates[16] = {0};
        int count = CollectArm64StaticCandidates(remoteCall, binaryBase + rva, candidates, 16);
        for (int i = 0; i < count; ++i) {
            uintptr_t cand = CleanPointer(candidates[i]);
            if (!validOffsetPtr(cand)) continue;

            // 1. Is cand directly the static_fields block?
            uintptr_t d0 = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, cand + kBaseGameStatic_sTickedEntities));
            uintptr_t d8 = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, cand + kBaseGameStatic_sAllEntities));
            if ((validOffsetPtr(d8) && IsDictionaryObject(remoteCall, d8)) ||
                (validOffsetPtr(d0) && IsDictionaryObject(remoteCall, d0))) {
                return cand;
            }

            // 2. Is cand the Il2CppClass* for BaseGame?
            uintptr_t sf = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, cand + kIl2CppClass_StaticFields));
            if (validOffsetPtr(sf)) {
                uintptr_t sfd0 = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, sf + kBaseGameStatic_sTickedEntities));
                uintptr_t sfd8 = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, sf + kBaseGameStatic_sAllEntities));
                if ((validOffsetPtr(sfd8) && IsDictionaryObject(remoteCall, sfd8)) ||
                    (validOffsetPtr(sfd0) && IsDictionaryObject(remoteCall, sfd0))) {
                    return sf;
                }
            }

            // 3. Is *cand the Il2CppClass* or static_fields block?
            uintptr_t deref = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, cand));
            if (validOffsetPtr(deref)) {
                uintptr_t dd0 = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, deref + kBaseGameStatic_sTickedEntities));
                uintptr_t dd8 = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, deref + kBaseGameStatic_sAllEntities));
                if ((validOffsetPtr(dd8) && IsDictionaryObject(remoteCall, dd8)) ||
                    (validOffsetPtr(dd0) && IsDictionaryObject(remoteCall, dd0))) {
                    return deref;
                }
                uintptr_t dsf = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, deref + kIl2CppClass_StaticFields));
                if (validOffsetPtr(dsf)) {
                    uintptr_t dsfd8 = CleanPointer(ReadMemorySafe<uintptr_t>(remoteCall, dsf + kBaseGameStatic_sAllEntities));
                    if (validOffsetPtr(dsfd8) && IsDictionaryObject(remoteCall, dsfd8)) {
                        return dsf;
                    }
                }
            }
        }
    }
    return 0;
}

#endif /* FreeFireUtils_h */
