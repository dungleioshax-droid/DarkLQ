//
//  AppUserDefaults.h
//  External-DarkSword
//
//  Created by Le Tien Dat on 8/21/26.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AppUserDefaults : NSObject

+ (void)setInteger:(NSInteger)value forKey:(NSString *)key;
+ (NSInteger)integerForKey:(NSString *)key
             fallbackValue:(NSInteger)fallbackValue;

+ (void)setBool:(BOOL)value forKey:(NSString *)key;
+ (BOOL)boolForKey:(NSString *)key fallbackValue:(BOOL)fallbackValue;

+ (void)setFloat:(float)value forKey:(NSString *)key;
+ (float)floatForKey:(NSString *)key fallbackValue:(float)fallbackValue;

+ (void)setDouble:(double)value forKey:(NSString *)key;
+ (double)doubleForKey:(NSString *)key fallbackValue:(double)fallbackValue;

+ (void)setString:(NSString *)value forKey:(NSString *)key;
+ (NSString *)stringForKey:(NSString *)key
             fallbackValue:(NSString *)fallbackValue;

@end

NS_ASSUME_NONNULL_END
