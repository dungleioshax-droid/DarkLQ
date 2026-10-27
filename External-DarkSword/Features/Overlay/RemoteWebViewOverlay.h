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

@protocol RemoteWebViewOverlayDelegate <NSObject>
@optional
- (void)overlayDidToggleLine:(BOOL)enabled;
- (void)overlayDidToggleBox:(BOOL)enabled;
- (void)overlayDidToggleHealth:(BOOL)enabled;
- (void)overlayDidToggleName:(BOOL)enabled;
- (void)overlayDidToggleHackMap:(BOOL)enabled;
@end

@interface RemoteWebViewOverlay : NSObject

@property(nonatomic, weak, nullable) id<RemoteWebViewOverlayDelegate> delegate;
@property(nonatomic, assign, readonly) RemoteCall *remoteCall;
@property(nonatomic, assign, readonly) RemoteObjectRef window;
@property(nonatomic, assign, readonly) CGFloat cachedScreenWidth;
@property(nonatomic, assign, readonly) CGFloat cachedScreenHeight;
@property(nonatomic, assign, readonly) BOOL isOverlayReady;
@property(nonatomic, assign, readonly) BOOL isSpringBoard;

- (instancetype)initWithRemoteCall:(RemoteCall *)remoteCall;
- (instancetype)initWithRemoteCall:(RemoteCall *)remoteCall
                     isSpringBoard:(BOOL)isSpringBoard;
- (BOOL)setupBaseOverlay;
- (void)teardownOverlay;
- (BOOL)updateOverlayTargets:(NSArray<NSDictionary *> *)targets;
- (BOOL)clearTargets;
- (void)setOverlayMenuVisible:(BOOL)visible;
- (void)toggleOverlayMenu;
- (void)setOverlayFloatButtonPositionX:(CGFloat)xRatio y:(CGFloat)yRatio;
- (void)refreshOverlayLayout;

@end

NS_ASSUME_NONNULL_END
