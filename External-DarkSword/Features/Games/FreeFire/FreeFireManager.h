//
//  FreeFireManager.h
//  External-DarkSword
//

#import "RemoteCall.h"
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface FreeFireManager : NSObject

@property(nonatomic, strong) RemoteCall *remoteCall;
@property(nonatomic, strong, nullable) RemoteCall *overlayRemoteCall;
@property(nonatomic, assign) BOOL useSpringBoardOverlay;
@property(nonatomic, assign) uintptr_t binaryBase;
@property(nonatomic, assign) BOOL isESPEnabled;
@property(nonatomic, assign) BOOL showsLine;
@property(nonatomic, assign) BOOL showsBox;
@property(nonatomic, assign) BOOL showsHealth;
@property(nonatomic, assign) BOOL showsName;
@property(nonatomic, assign) BOOL showsDistance;
@property(nonatomic, readonly) BOOL hasValidFrame;
@property(nonatomic, copy, nullable) void (^diagnosticsHandler)(NSString *message);

- (instancetype)initWithRemoteCall:(RemoteCall *)remoteCall;
- (instancetype)initWithRemoteCall:(RemoteCall *)remoteCall
                 overlayRemoteCall:(nullable RemoteCall *)overlayRemoteCall;

- (void)runLoop;
- (void)stopLoop;
- (void)clearOverlayTargets;
- (void)setOverlayMenuVisible:(BOOL)visible;
- (void)toggleOverlayMenu;
- (void)setOverlayFloatButtonPositionX:(CGFloat)xRatio y:(CGFloat)yRatio;
- (void)refreshOverlayLayout;

- (uint64_t)getRealOffset:(uint64_t)offset;

@end

NS_ASSUME_NONNULL_END
