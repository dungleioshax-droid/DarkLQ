//
//  AoVManager.h
//  External-DarkSword
//
//  Created by Le Tien Dat on 8/6/26.
//

#import "RemoteCall.h"
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AoVManager : NSObject

@property(nonatomic, strong) RemoteCall *remoteCall;
@property(nonatomic, assign) uintptr_t cameraSystem;
@property(nonatomic, assign) uintptr_t actorManager;
@property(nonatomic, assign) double cameraHeight;
@property(nonatomic, assign) BOOL isESPEnabled;
@property(nonatomic, assign) BOOL isHackMapEnabled;
@property(nonatomic, assign) BOOL showsLine;
@property(nonatomic, assign) BOOL showsBox;
@property(nonatomic, assign) BOOL showsHealth;
@property(nonatomic, assign) BOOL showsName;
@property(nonatomic, assign) BOOL showsDistance;
@property(nonatomic, readonly) BOOL hasValidFrame;

- (instancetype)initWithRemoteCall:(RemoteCall *)remoteCall;

- (void)runLoop;
- (void)stopLoop;
- (void)clearOverlayTargets;
- (void)setOverlayMenuVisible:(BOOL)visible;
- (void)toggleOverlayMenu;
- (void)setOverlayFloatButtonPositionX:(CGFloat)xRatio y:(CGFloat)yRatio;
- (void)refreshOverlayLayout;

- (uint64_t)getRealOffset:(uint64_t)offset;
- (uint64_t)getRealOffsetWithBinary:(uint64_t)baseBinary
                             offset:(uint64_t)offset;

@end

NS_ASSUME_NONNULL_END
