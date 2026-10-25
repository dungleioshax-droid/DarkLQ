//
//  FreeFireUtils.h
//  External-DarkSword
//

#ifndef FreeFireUtils_h
#define FreeFireUtils_h

#import "../../../App/Configuration/Macros.h"
#import "../../../Core/TaskRop/RemoteCall.h"
#import "../../Unity/Vector3.h"
#import "FreeFireOffset.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <string>

static inline bool validOffsetPtr(uintptr_t ptr) {
    return ptr > 0x100000000ULL && ptr < 0x2000000000ULL;
}

template <typename T>
static inline T ReadMemorySafe(RemoteCall *remoteCall, uintptr_t address) {
    T value = {};
    if (!validOffsetPtr(address) || !remoteCall)
        return value;
    [remoteCall remoteRead:address to:&value size:sizeof(T)];
    return value;
}

template <typename T>
static inline bool WriteMemorySafe(RemoteCall *remoteCall, uintptr_t address,
                                   T value) {
    if (!validOffsetPtr(address) || !remoteCall)
        return false;
    return [remoteCall remote_write:address from:&value size:sizeof(T)];
}

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

static bool ReadCameraVPMatrixFromNative(RemoteCall *remoteCall,
                                        uintptr_t camera, float *out) {
    if (!validOffsetPtr(camera) || !remoteCall || !out)
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

    if (ReadValidMatrix(remoteCall, nativeCamera + kNativeCamera_WorldToClip,
                        viewProjection) &&
        LooksLikeViewProjection(viewProjection)) {
        memcpy(out, viewProjection, sizeof(viewProjection));
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

// MARK: - Dynamic ARM64 Static Fields Resolution

static uintptr_t DecodeArm64AdrLdr(RemoteCall *remoteCall, uintptr_t funcAddr) {
    if (!validOffsetPtr(funcAddr) || !remoteCall)
        return 0;

    uint32_t insns[16] = {0};
    if (![remoteCall remoteRead:funcAddr to:insns size:sizeof(insns)])
        return 0;

    uintptr_t adrpTarget = 0;
    uint32_t adrpReg = 0xFF;

    for (int i = 0; i < 16; ++i) {
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
            adrpTarget = (pc & ~0xFFFULL) + imm;
            adrpReg = rd;
            continue;
        }

        // LDR Xt, [Xn, #imm12] (64-bit)
        if (adrpReg != 0xFF && (insn & 0xFFC00000) == 0xF9400000) {
            uint32_t rn = (insn >> 5) & 0x1F;
            if (rn == adrpReg) {
                uint32_t imm12 = ((insn >> 10) & 0xFFF) << 3;
                uintptr_t ptrAddr = adrpTarget + imm12;
                uintptr_t resolved = ReadMemorySafe<uintptr_t>(remoteCall, ptrAddr);
                if (validOffsetPtr(resolved))
                    return resolved;
            }
        }

        // ADD Xd, Xn, #imm12 (64-bit)
        if (adrpReg != 0xFF && (insn & 0xFF800000) == 0x91000000) {
            uint32_t rn = (insn >> 5) & 0x1F;
            if (rn == adrpReg) {
                uint32_t imm12 = (insn >> 10) & 0xFFF;
                uintptr_t targetAddr = adrpTarget + imm12;
                if (validOffsetPtr(targetAddr))
                    return targetAddr;
            }
        }
    }

    return 0;
}

#endif /* FreeFireUtils_h */
