//
//  helper.h
//  External-DarkSword
//
//  Created by Le Tien Dat on 8/6/26.
//

#ifndef helper_h
#define helper_h

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

static inline bool checkPointer64bits(uintptr_t addr) {
    return addr != 0 && (addr & 7) == 0;
}

static inline bool validOffsetPtr(uintptr_t p) {
    return p > 0x10000 && p < 0x80000000000ULL;
}

static inline bool checkValidPointer64bits(uintptr_t addr) {
    return validOffsetPtr(addr) && checkPointer64bits(addr);
}

#ifdef __cplusplus
}
#endif

#ifdef __cplusplus

#import "../../Core/TaskRop/RemoteCall.h"

template <typename T> static inline bool checkPointer(uintptr_t addr) {
    return addr != 0 && (addr & (alignof(T) - 1)) == 0;
}

template <typename T> static inline bool isAlignedAddr(uintptr_t addr) {
    constexpr size_t alignment = alignof(T);
    if ((alignment & (alignment - 1)) == 0) {
        return (addr & (alignment - 1)) == 0;
    }
    return addr % alignment == 0;
}

/// Read sizeof(T) from remote process address space via RemoteCall.
template <typename T>
static inline T ReadMemorySafe(RemoteCall *remoteCall, uintptr_t addr,
                               T defaultValue = T()) {
    if (!remoteCall || addr == 0) {
        return defaultValue;
    }
    if (!isAlignedAddr<T>(addr)) {
        return defaultValue;
    }

    T value{};
    if (![remoteCall remoteRead:addr to:&value size:sizeof(T)]) {
        return defaultValue;
    }
    return value;
}

/// Write sizeof(T) into remote process address space via RemoteCall.
template <typename T>
static inline bool WriteMemorySafe(RemoteCall *remoteCall, uintptr_t addr,
                                   T value) {
    if (!remoteCall || addr == 0) {
        return false;
    }
    if (!isAlignedAddr<T>(addr)) {
        return false;
    }
    return [remoteCall remote_write:addr from:&value size:sizeof(T)];
}

#endif /* __cplusplus */

#endif /* helper_h */
