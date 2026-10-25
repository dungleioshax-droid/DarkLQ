//
//  AppUserDefaults.m
//  External-DarkSword
//
//  Created by Le Tien Dat on 8/21/26.
//

#import "AppUserDefaults.h"

NS_ASSUME_NONNULL_BEGIN

#define UD [NSUserDefaults standardUserDefaults]

@implementation AppUserDefaults

+ (void)setInteger:(NSInteger)value forKey:(NSString *)key {
    [UD setInteger:value forKey:key];
    [UD synchronize];
}

+ (NSInteger)integerForKey:(NSString *)key
             fallbackValue:(NSInteger)fallbackValue {
    if ([UD objectForKey:key]) {
        return [UD integerForKey:key];
    }
    return fallbackValue;
}

+ (void)setBool:(BOOL)value forKey:(NSString *)key {
    [UD setBool:value forKey:key];
    [UD synchronize];
}

+ (BOOL)boolForKey:(NSString *)key fallbackValue:(BOOL)fallbackValue {
    if ([UD objectForKey:key]) {
        return [UD boolForKey:key];
    }
    return fallbackValue;
}

+ (void)setFloat:(float)value forKey:(NSString *)key {
    [UD setFloat:value forKey:key];
    [UD synchronize];
}

+ (float)floatForKey:(NSString *)key fallbackValue:(float)fallbackValue {
    if ([UD objectForKey:key]) {
        return [UD floatForKey:key];
    }
    return fallbackValue;
}

+ (void)setDouble:(double)value forKey:(NSString *)key {
    [UD setDouble:value forKey:key];
    [UD synchronize];
}

+ (double)doubleForKey:(NSString *)key fallbackValue:(double)fallbackValue {
    if ([UD objectForKey:key]) {
        return [UD doubleForKey:key];
    }
    return fallbackValue;
}

+ (void)setString:(NSString *)value forKey:(NSString *)key {
    [UD setObject:value forKey:key];
    [UD synchronize];
}

+ (NSString *)stringForKey:(NSString *)key
             fallbackValue:(NSString *)fallbackValue {
    if ([UD objectForKey:key]) {
        NSString *value = [UD stringForKey:key];
        if (value) {
            return value;
        }
    }
    return fallbackValue;
}

@end

#undef UD

NS_ASSUME_NONNULL_END
