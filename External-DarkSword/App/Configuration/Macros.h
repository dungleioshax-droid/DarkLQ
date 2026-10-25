//
//  Macros.h
//  External-DarkSword
//
//  Created by Le Tien Dat on 8/6/26.
//

#ifndef Macros_h
#define Macros_h

#pragma once

#import "Config.h"
#import "Foundation/Foundation.h"
#import <dispatch/dispatch.h>
#import <os/log.h>

#define LOG_PREFIX @"GioVoTinh Mod >>>"

static inline os_log_t GetLogger(void) {
    static os_log_t logger;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
      logger = os_log_create("com.letiendat.external-darksword",
                             "External-DarkSword");
    });

    return logger;
}

#define LOG(...)                                                               \
    do {                                                                       \
        if (!g_isDebug)                                                        \
            break;                                                             \
        os_log_with_type(GetLogger(), OS_LOG_TYPE_DEFAULT,                     \
                         "%{public}@ %{public}@", LOG_PREFIX,                  \
                         [NSString stringWithFormat:__VA_ARGS__]);             \
    } while (0)

static inline void logSwift(NSString *message) { LOG(@"%@", message); }

// Dispatch
#define timer(sec) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, sec * NSEC_PER_SEC), dispatch_get_main_queue(), ^
#define timer_background(sec) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, sec * NSEC_PER_SEC), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^
#define onMain(block) dispatch_async(dispatch_get_main_queue(), block)

// Helper
#define appPath [[NSBundle mainBundle] bundlePath]
#define binaryPath(name) [appPath stringByAppendingPathComponent:name]
#define ARRAY_LENGTH(arr) (sizeof(arr) / sizeof(arr[0]))

#define kWidth UIScreen.mainScreen.bounds.size.width
#define kHeight UIScreen.mainScreen.bounds.size.height

#endif /* Macros_h */
