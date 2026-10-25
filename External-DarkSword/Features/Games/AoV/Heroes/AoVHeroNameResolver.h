//
//  AoVHeroNameResolver.h
//  External-DarkSword
//
//  Created by Le Tien Dat on 8/28/26.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AoVHeroNameResolver : NSObject

+ (instancetype)sharedResolver;

- (void)loadFromRemote;
- (NSString *)heroNameForID:(int)heroID;

@end

NS_ASSUME_NONNULL_END
