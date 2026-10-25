//
//  RemoteWebViewOverlay.h
//  External-DarkSword
//
//  Created by Le Tien Dat on 8/25/26.
//

#import "../../Core/TaskRop/RemoteCall.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef uint64_t RemoteObjectRef;

@interface RemoteWebViewOverlay : NSObject

@property(nonatomic, assign, readonly) RemoteCall *remoteCall;
@property(nonatomic, assign, readonly) RemoteObjectRef window;
@property(nonatomic, assign, readonly) CGFloat cachedScreenWidth;
@property(nonatomic, assign, readonly) CGFloat cachedScreenHeight;
@property(nonatomic, assign, readonly) BOOL isOverlayReady;

- (instancetype)initWithRemoteCall:(RemoteCall *)remoteCall;
- (BOOL)setupBaseOverlay;
- (BOOL)updateOverlayTargets:(NSArray<NSDictionary *> *)targets;
- (BOOL)clearTargets;
- (void)setOverlayMenuVisible:(BOOL)visible;
- (void)toggleOverlayMenu;
- (void)setOverlayFloatButtonPositionX:(CGFloat)xRatio y:(CGFloat)yRatio;
- (void)refreshOverlayLayout;

@end

NS_ASSUME_NONNULL_END
