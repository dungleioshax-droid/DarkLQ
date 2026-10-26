//
//  RemoteWebViewOverlay.m
//  External-DarkSword
//
//  Created by Le Tien Dat on 8/25/26.
//

#import "RemoteWebViewOverlay.h"
#import "../../App/Configuration/Config.h"
#import "../../App/Configuration/Macros.h"
#import "OverlayWebSocketServer.h"

extern uint64_t remote_getClass(RemoteCall *process, const char *name);
extern uint64_t remote_sel(RemoteCall *process, const char *name);
extern uint64_t remote_msg(RemoteCall *process, uint64_t receiver,
                           uint64_t selector, uint64_t a0, uint64_t a1,
                           uint64_t a2, uint64_t a3);
extern uint64_t remote_NSString(RemoteCall *process, const char *str);
extern uint64_t remote_msg_on_main_thread(RemoteCall *proc, uint64_t target,
                                          uint64_t selector,
                                          const void *const *argData,
                                          const size_t *argSizes,
                                          size_t argCount);
extern CGRect remote_getCGRect(RemoteCall *proc, uint64_t obj, uint64_t sel);

static const CGFloat kOverlayFABSize = 45.0;
static const CGFloat kOverlayFABTrailingInset = 80.0;

static CGFloat OverlayClamp(CGFloat value, CGFloat lower, CGFloat upper) {
    return MIN(MAX(value, lower), upper);
}

#pragma mark - RemoteWebViewOverlay

@interface RemoteWebViewOverlay ()

@property(nonatomic, assign, readwrite) RemoteCall *remoteCall;
@property(nonatomic, assign, readwrite) BOOL isSpringBoard;
@property(nonatomic, assign, readwrite) RemoteObjectRef window;
@property(nonatomic, assign, readwrite) RemoteObjectRef parentView;
@property(nonatomic, assign, readwrite) RemoteObjectRef webView;
@property(nonatomic, assign) RemoteObjectRef menuWebView;
@property(nonatomic, assign) RemoteObjectRef floatButtonWebView;
@property(nonatomic, assign, readwrite) BOOL isOverlayReady;
@property(nonatomic, assign, readwrite) CGFloat cachedScreenWidth;
@property(nonatomic, assign, readwrite) CGFloat cachedScreenHeight;
@property(nonatomic, assign) BOOL menuVisible;
@property(nonatomic, assign) BOOL hasCustomFloatButtonPosition;
@property(nonatomic, assign) CGFloat floatButtonXRatio;
@property(nonatomic, assign) CGFloat floatButtonYRatio;

@end

@implementation RemoteWebViewOverlay

#pragma mark - Init

- (instancetype)initWithRemoteCall:(RemoteCall *)remoteCall {
    return [self initWithRemoteCall:remoteCall isSpringBoard:NO];
}

- (instancetype)initWithRemoteCall:(RemoteCall *)remoteCall
                     isSpringBoard:(BOOL)isSpringBoard {
    self = [super init];
    if (self) {
        _remoteCall = remoteCall;
        _isSpringBoard = isSpringBoard;
        _window = 0;
        _parentView = 0;
        _webView = 0;
        _menuWebView = 0;
        _floatButtonWebView = 0;
        _isOverlayReady = NO;
        _cachedScreenWidth = 0;
        _cachedScreenHeight = 0;
        _menuVisible = NO;
        _hasCustomFloatButtonPosition = NO;
        _floatButtonXRatio = 0;
        _floatButtonYRatio = 0;
    }
    return self;
}

#pragma mark - Remote runtime helpers

- (RemoteObjectRef)getClass:(const char *)name {
    return remote_getClass(self.remoteCall, name);
}

- (uint64_t)getSelector:(const char *)name {
    return remote_sel(self.remoteCall, name);
}

- (RemoteObjectRef)call:(RemoteObjectRef)receiver
               selector:(const char *)selector {
    if (!receiver)
        return 0;
    uint64_t sel = [self getSelector:selector];
    if (!sel)
        return 0;
    return remote_msg(self.remoteCall, receiver, sel, 0, 0, 0, 0);
}

- (RemoteObjectRef)call:(RemoteObjectRef)receiver
               selector:(const char *)selector
               argument:(uint64_t)argument {
    if (!receiver)
        return 0;
    uint64_t sel = [self getSelector:selector];
    if (!sel)
        return 0;
    return remote_msg(self.remoteCall, receiver, sel, argument, 0, 0, 0);
}

#pragma mark - Find UIWindow

- (BOOL)findTargetWindow {
    LOG(@"[RemoteWebViewOverlay] Finding target UIWindow...");

    RemoteObjectRef uiApplicationClass = [self getClass:"UIApplication"];
    if (!uiApplicationClass) {
        LOG(@"[RemoteWebViewOverlay] UIApplication class not found");
        return NO;
    }

    RemoteObjectRef application = [self call:uiApplicationClass
                                    selector:"sharedApplication"];
    if (!application) {
        LOG(@"[RemoteWebViewOverlay] UIApplication == NULL");
        return NO;
    }

    // Attempt 1: UIApplicationDelegate.window (standard in UnityAppController)
    RemoteObjectRef delegate = [self call:application selector:"delegate"];
    if (delegate) {
        RemoteObjectRef delegateWindow = [self call:delegate selector:"window"];
        if (delegateWindow) {
            RemoteObjectRef isHidden = [self call:delegateWindow selector:"isHidden"];
            if (!isHidden) {
                self.window = delegateWindow;
                LOG(@"[RemoteWebViewOverlay] FOUND UIWindow via delegate = 0x%llx", delegateWindow);
                return YES;
            }
        }
    }

    // Attempt 2: keyWindow
    RemoteObjectRef keyWindow = [self call:application selector:"keyWindow"];
    if (keyWindow) {
        RemoteObjectRef isHidden = [self call:keyWindow selector:"isHidden"];
        if (!isHidden) {
            self.window = keyWindow;
            LOG(@"[RemoteWebViewOverlay] FOUND UIWindow via keyWindow = 0x%llx", keyWindow);
            return YES;
        }
    }

    // Attempt 3: connectedScenes -> windows
    RemoteObjectRef connectedScenes = [self call:application
                                        selector:"connectedScenes"];
    if (!connectedScenes) {
        LOG(@"[RemoteWebViewOverlay] connectedScenes == NULL");
        return NO;
    }

    RemoteObjectRef scenes = [self call:connectedScenes selector:"allObjects"];
    if (!scenes) {
        LOG(@"[RemoteWebViewOverlay] scenes == NULL");
        return NO;
    }

    NSUInteger sceneCount = (NSUInteger)[self call:scenes selector:"count"];
    LOG(@"[RemoteWebViewOverlay] sceneCount = %lu", (unsigned long)sceneCount);

    uint64_t objectAtIndexSEL = [self getSelector:"objectAtIndex:"];
    if (!objectAtIndexSEL)
        return NO;

    for (NSUInteger i = 0; i < sceneCount; i++) {
        RemoteObjectRef scene =
            remote_msg(self.remoteCall, scenes, objectAtIndexSEL, i, 0, 0, 0);
        if (!scene)
            continue;

        RemoteObjectRef windows = [self call:scene selector:"windows"];
        if (!windows)
            continue;

        NSUInteger windowCount =
            (NSUInteger)[self call:windows selector:"count"];
        LOG(@"[RemoteWebViewOverlay] scene[%lu] windowCount = %lu",
            (unsigned long)i, (unsigned long)windowCount);

        for (NSUInteger j = 0; j < windowCount; j++) {
            RemoteObjectRef window = remote_msg(self.remoteCall, windows,
                                                objectAtIndexSEL, j, 0, 0, 0);
            if (!window)
                continue;

            RemoteObjectRef hidden = [self call:window selector:"isHidden"];
            LOG(@"[RemoteWebViewOverlay] window[%lu] = 0x%llx hidden=%llu",
                (unsigned long)j, window, hidden);

            if (hidden)
                continue;

            self.window = window;
            LOG(@"[RemoteWebViewOverlay] FOUND UIWindow = 0x%llx", window);
            return YES;
        }
    }

    LOG(@"[RemoteWebViewOverlay] No visible UIWindow found");
    return NO;
}

#pragma mark - Find parent view

- (BOOL)findParentView {
    if (!self.window) {
        LOG(@"[RemoteWebViewOverlay] window is NULL");
        return NO;
    }

    self.parentView = self.window;
    LOG(@"[RemoteWebViewOverlay] parentView = UIWindow 0x%llx", self.window);
    return YES;
}

#pragma mark - Load overlay HTML from bundle

- (NSString *)loadOverlayHTMLResource:(NSString *)resourceName {
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *path = [bundle pathForResource:resourceName ofType:@"html"];
    if (!path) {
        LOG(@"[RemoteWebViewOverlay] %@.html not found in bundle!",
            resourceName);
        return nil;
    }

    NSString *html = [NSString stringWithContentsOfFile:path
                                               encoding:NSUTF8StringEncoding
                                                  error:nil];
    if (html.length == 0) {
        LOG(@"[RemoteWebViewOverlay] %@.html is empty!", resourceName);
        return nil;
    }

    LOG(@"[RemoteWebViewOverlay] %@.html loaded from bundle (%lu bytes)",
        resourceName, (unsigned long)html.length);
    uint16_t port = [OverlayWebSocketServer sharedServer].port;
    return [html stringByReplacingOccurrencesOfString:@"%%OVERLAY_WS_PORT%%"
                                           withString:@(port).stringValue];
}

- (void)setView:(RemoteObjectRef)view
      boolValue:(BOOL)value
       selector:(const char *)selectorName {
    if (!view)
        return;

    uint64_t selector = [self getSelector:selectorName];
    if (!selector)
        return;

    const void *params[] = {&value};
    size_t sizes[] = {sizeof(value)};
    remote_msg_on_main_thread(self.remoteCall, view, selector, params, sizes,
                              1);
}

- (void)setFrame:(CGRect)frame forView:(RemoteObjectRef)view {
    if (!view)
        return;

    uint64_t selector = [self getSelector:"setFrame:"];
    if (!selector)
        return;

    const void *params[] = {&frame};
    size_t sizes[] = {sizeof(frame)};
    remote_msg_on_main_thread(self.remoteCall, view, selector, params, sizes,
                              1);
}

- (void)setAutoresizingForView:(RemoteObjectRef)view {
    if (!view)
        return;

    uint64_t selector = [self getSelector:"setAutoresizingMask:"];
    if (!selector)
        return;

    NSUInteger mask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    const void *params[] = {&mask};
    size_t sizes[] = {sizeof(mask)};
    remote_msg_on_main_thread(self.remoteCall, view, selector, params, sizes,
                              1);
}

- (void)makeWebViewTransparent:(RemoteObjectRef)view {
    RemoteObjectRef uiColorClass = [self getClass:"UIColor"];
    uint64_t clearSelector = [self getSelector:"clearColor"];
    if (uiColorClass && clearSelector) {
        RemoteObjectRef clearColor = remote_msg_on_main_thread(
            self.remoteCall, uiColorClass, clearSelector, NULL, NULL, 0);
        if (clearColor) {
            uint64_t backgroundSelector =
                [self getSelector:"setBackgroundColor:"];
            if (backgroundSelector) {
                const void *params[] = {&clearColor};
                size_t sizes[] = {sizeof(clearColor)};
                remote_msg_on_main_thread(self.remoteCall, view,
                                          backgroundSelector, params, sizes, 1);
            }
        }
    }
    [self setView:view boolValue:NO selector:"setOpaque:"];
}

- (RemoteObjectRef)createWebViewWithResource:(NSString *)resourceName
                                       frame:(CGRect)frame
                                 interactive:(BOOL)interactive
                                      hidden:(BOOL)hidden
                             autoresizesView:(BOOL)autoresizesView {
    RemoteObjectRef configClass = [self getClass:"WKWebViewConfiguration"];
    RemoteObjectRef webViewClass = [self getClass:"WKWebView"];
    if (!configClass || !webViewClass)
        return 0;

    RemoteObjectRef allocConfig = [self call:configClass selector:"alloc"];
    RemoteObjectRef config = allocConfig ? remote_msg_on_main_thread(
        self.remoteCall, allocConfig, [self getSelector:"init"], NULL, NULL, 0) : 0;
    if (!config)
        return 0;

    RemoteObjectRef view = [self call:webViewClass selector:"alloc"];
    if (!view)
        return 0;

    const void *initParams[] = {&frame, &config};
    size_t initSizes[] = {sizeof(frame), sizeof(config)};
    view = remote_msg_on_main_thread(
        self.remoteCall, view,
        [self getSelector:"initWithFrame:configuration:"], initParams,
        initSizes, 2);
    if (!view)
        return 0;

    [self makeWebViewTransparent:view];
    [self setView:view
        boolValue:interactive
         selector:"setUserInteractionEnabled:"];
    [self setView:view boolValue:hidden selector:"setHidden:"];
    if (autoresizesView)
        [self setAutoresizingForView:view];

    NSString *html = [self loadOverlayHTMLResource:resourceName];
    if (!html)
        return 0;

    RemoteObjectRef remoteHTML =
        remote_NSString(self.remoteCall, html.UTF8String);
    uint64_t loadSelector = [self getSelector:"loadHTMLString:baseURL:"];
    if (!remoteHTML || !loadSelector)
        return 0;

    uint64_t nilBaseURL = 0;
    const void *loadParams[] = {&remoteHTML, &nilBaseURL};
    size_t loadSizes[] = {sizeof(remoteHTML), sizeof(nilBaseURL)};
    remote_msg_on_main_thread(self.remoteCall, view, loadSelector, loadParams,
                              loadSizes, 2);

    uint64_t addSubviewSelector = [self getSelector:"addSubview:"];
    if (!addSubviewSelector)
        return 0;
    const void *addParams[] = {&view};
    size_t addSizes[] = {sizeof(view)};
    remote_msg_on_main_thread(self.remoteCall, self.parentView,
                              addSubviewSelector, addParams, addSizes, 1);
    return view;
}

- (BOOL)refreshWindowBounds {
    if (self.isSpringBoard) {
        self.cachedScreenWidth = MAX(kWidth, kHeight);
        self.cachedScreenHeight = MIN(kWidth, kHeight);
        return YES;
    }

    uint64_t selector = [self getSelector:"bounds"];
    if (!selector || !self.window) {
        self.cachedScreenWidth = MAX(kWidth, kHeight);
        self.cachedScreenHeight = MIN(kWidth, kHeight);
        return YES;
    }

    CGRect bounds = remote_getCGRect(self.remoteCall, self.window, selector);
    if (bounds.size.width > 0.0 && bounds.size.height > 0.0) {
        self.cachedScreenWidth = bounds.size.width;
        self.cachedScreenHeight = bounds.size.height;
    } else {
        self.cachedScreenWidth = MAX(kWidth, kHeight);
        self.cachedScreenHeight = MIN(kWidth, kHeight);
    }
    return YES;
}

- (BOOL)ensureWebKitLoaded {
    RemoteObjectRef wkConfigClass = [self getClass:"WKWebViewConfiguration"];
    if (wkConfigClass) {
        return YES;
    }

    LOG(@"[RemoteWebViewOverlay] WKWebViewConfiguration not found, loading WebKit.framework...");
    RemoteObjectRef bundleClass = [self getClass:"NSBundle"];
    if (bundleClass) {
        uint64_t bundlePath = remote_NSString(self.remoteCall, "/System/Library/Frameworks/WebKit.framework");
        if (bundlePath) {
            RemoteObjectRef bundle = [self call:bundleClass selector:"bundleWithPath:" argument:bundlePath];
            if (bundle) {
                [self call:bundle selector:"load"];
                wkConfigClass = [self getClass:"WKWebViewConfiguration"];
            }
        }
    }
    return wkConfigClass != 0;
}

- (BOOL)setupSpringBoardOverlayWindow {
    LOG(@"[RemoteWebViewOverlay] Setting up SpringBoard overlay window...");

    // Determine landscape screen dimensions
    CGFloat w = MAX(kWidth, kHeight);
    CGFloat h = MIN(kWidth, kHeight);

    RemoteObjectRef uiScreenClass = [self getClass:"UIScreen"];
    if (uiScreenClass) {
        RemoteObjectRef mainScreen = [self call:uiScreenClass selector:"mainScreen"];
        if (mainScreen) {
            uint64_t boundsSEL = [self getSelector:"bounds"];
            if (boundsSEL) {
                CGRect screenBounds = remote_getCGRect(self.remoteCall, mainScreen, boundsSEL);
                if (screenBounds.size.width > 0.0 && screenBounds.size.height > 0.0) {
                    w = MAX(screenBounds.size.width, screenBounds.size.height);
                    h = MIN(screenBounds.size.width, screenBounds.size.height);
                }
            }
        }
    }
    self.cachedScreenWidth = w;
    self.cachedScreenHeight = h;
    LOG(@"[RemoteWebViewOverlay] SpringBoard target bounds: %.0fx%.0f", w, h);

    // 1. Resolve mainWindowScene from SBMainWorkspace (standard in SpringBoard)
    RemoteObjectRef workspaceClass = [self getClass:"SBMainWorkspace"];
    RemoteObjectRef windowScene = 0;
    if (workspaceClass) {
        RemoteObjectRef workspace = [self call:workspaceClass selector:"sharedInstance"];
        if (workspace) {
            windowScene = [self call:workspace selector:"mainWindowScene"];
            LOG(@"[RemoteWebViewOverlay] SBMainWorkspace mainWindowScene = 0x%llx", windowScene);
        }
    }

    // Fallback: search connectedScenes
    if (!windowScene) {
        RemoteObjectRef uiAppClass = [self getClass:"UIApplication"];
        if (uiAppClass) {
            RemoteObjectRef app = [self call:uiAppClass selector:"sharedApplication"];
            if (app) {
                RemoteObjectRef connectedScenes = [self call:app selector:"connectedScenes"];
                if (connectedScenes) {
                    RemoteObjectRef scenes = [self call:connectedScenes selector:"allObjects"];
                    if (scenes) {
                        NSUInteger count = (NSUInteger)[self call:scenes selector:"count"];
                        uint64_t objectAtIndexSEL = [self getSelector:"objectAtIndex:"];
                        for (NSUInteger i = 0; i < count; i++) {
                            RemoteObjectRef s = remote_msg(self.remoteCall, scenes, objectAtIndexSEL, i, 0, 0, 0);
                            if (s) {
                                windowScene = s;
                                LOG(@"[RemoteWebViewOverlay] Found windowScene via connectedScenes = 0x%llx", s);
                                break;
                            }
                        }
                    }
                }
            }
        }
    }

    // 2. Resolve SBFTouchPassThroughWindow (or load SpringBoardFoundation.framework)
    RemoteObjectRef windowClass = [self getClass:"SBFTouchPassThroughWindow"];
    if (!windowClass) {
        RemoteObjectRef bundleClass = [self getClass:"NSBundle"];
        if (bundleClass) {
            uint64_t bundlePath = remote_NSString(self.remoteCall, "/System/Library/PrivateFrameworks/SpringBoardFoundation.framework");
            if (bundlePath) {
                RemoteObjectRef bundle = [self call:bundleClass selector:"bundleWithPath:" argument:bundlePath];
                if (bundle) {
                    [self call:bundle selector:"load"];
                    windowClass = [self getClass:"SBFTouchPassThroughWindow"];
                }
            }
        }
    }
    if (!windowClass) {
        LOG(@"[RemoteWebViewOverlay] SBFTouchPassThroughWindow not found; falling back to UIWindow");
        windowClass = [self getClass:"UIWindow"];
    }
    if (!windowClass) {
        LOG(@"[RemoteWebViewOverlay] No window class found in SpringBoard");
        return NO;
    }

    // 3. Allocate and initialize window
    RemoteObjectRef allocWindow = [self call:windowClass selector:"alloc"];
    if (!allocWindow) {
        LOG(@"[RemoteWebViewOverlay] Failed to alloc window in SpringBoard");
        return NO;
    }

    RemoteObjectRef window = remote_msg_on_main_thread(
        self.remoteCall, allocWindow, [self getSelector:"init"], NULL, NULL, 0);
    if (!window) {
        LOG(@"[RemoteWebViewOverlay] Failed to init window in SpringBoard");
        return NO;
    }

    // 4. Configure frame
    CGRect frame = CGRectMake(0, 0, self.cachedScreenWidth, self.cachedScreenHeight);
    const void *frameParams[] = {&frame};
    size_t frameSizes[] = {sizeof(frame)};
    remote_msg_on_main_thread(self.remoteCall, window, [self getSelector:"setFrame:"],
                              frameParams, frameSizes, 1);

    // 5. Attach to windowScene if available
    if (windowScene) {
        const void *sceneParams[] = {&windowScene};
        size_t sceneSizes[] = {sizeof(windowScene)};
        remote_msg_on_main_thread(self.remoteCall, window, [self getSelector:"setWindowScene:"],
                                  sceneParams, sceneSizes, 1);
    }

    // 6. Set windowLevel to 10000010.0 (high level above running apps & SpringBoard UI)
    CGFloat windowLevel = 10000010.0;
    const void *levelParams[] = {&windowLevel};
    size_t levelSizes[] = {sizeof(windowLevel)};
    remote_msg_on_main_thread(self.remoteCall, window, [self getSelector:"setWindowLevel:"],
                              levelParams, levelSizes, 1);

    // 7. Make transparent & non-opaque
    [self makeWebViewTransparent:window];

    // 8. Set userInteractionEnabled = YES (SBFTouchPassThroughWindow allows empty touches to pass through)
    [self setView:window boolValue:YES selector:"setUserInteractionEnabled:"];

    // 9. Make visible
    [self setView:window boolValue:NO selector:"setHidden:"];

    self.window = window;
    self.parentView = window;
    LOG(@"[RemoteWebViewOverlay] SpringBoard overlay window ready: 0x%llx (%.0fx%.0f, level=%.0f)",
        window, self.cachedScreenWidth, self.cachedScreenHeight, windowLevel);
    return YES;
}

- (CGRect)floatButtonFrame {
    CGFloat width = MAX(self.cachedScreenWidth, kOverlayFABSize);
    CGFloat height = MAX(self.cachedScreenHeight, kOverlayFABSize);
    CGFloat maxX = MAX(0.0, width - kOverlayFABSize);
    CGFloat maxY = MAX(0.0, height - kOverlayFABSize);
    CGFloat x = MAX(0.0, width - kOverlayFABTrailingInset - kOverlayFABSize);
    CGFloat y = maxY * 0.5;

    if (self.hasCustomFloatButtonPosition) {
        x = self.floatButtonXRatio * maxX;
        y = self.floatButtonYRatio * maxY;
    }

    return CGRectMake(OverlayClamp(x, 0.0, maxX), OverlayClamp(y, 0.0, maxY),
                      kOverlayFABSize, kOverlayFABSize);
}

- (void)broadcastOverlayLayout {
    if (!self.isOverlayReady)
        return;

    CGRect frame = [self floatButtonFrame];
    CGFloat centerX = (frame.origin.x + frame.size.width * 0.5) /
                      MAX(self.cachedScreenWidth, 1.0);
    CGFloat centerY = (frame.origin.y + frame.size.height * 0.5) /
                      MAX(self.cachedScreenHeight, 1.0);
    NSDictionary *layout = @{
        @"screenWidth" : @(self.cachedScreenWidth),
        @"screenHeight" : @(self.cachedScreenHeight),
        @"fabSize" : @(kOverlayFABSize),
        @"fabCenterX" : @(centerX),
        @"fabCenterY" : @(centerY),
        @"menuVisible" : @(self.menuVisible)
    };
    NSDictionary *payload = @{@"type" : @"overlayLayout", @"layout" : layout};
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload
                                                   options:0
                                                     error:nil];
    if (data.length > 0)
        [[OverlayWebSocketServer sharedServer] broadcastTextData:data];
}

#pragma mark - Setup base overlay

- (BOOL)setupBaseOverlay {
    if (self.isOverlayReady && self.webView) {
        return YES;
    }

    LOG(@"[RemoteWebViewOverlay] Setting up base overlay (%s)...",
        self.isSpringBoard ? "SpringBoard" : "Internal");

    if (self.isSpringBoard) {
        if (![self setupSpringBoardOverlayWindow]) {
            LOG(@"[RemoteWebViewOverlay] setupSpringBoardOverlayWindow failed");
            return NO;
        }
    } else {
        if (![self findTargetWindow]) {
            LOG(@"[RemoteWebViewOverlay] setupBaseOverlay: findTargetWindow failed");
            return NO;
        }

        if (![self findParentView]) {
            LOG(@"[RemoteWebViewOverlay] setupBaseOverlay: findParentView failed");
            return NO;
        }

        uint64_t boundsSEL = [self getSelector:"bounds"];
        if (boundsSEL && self.window) {
            CGRect gameBounds =
                remote_getCGRect(self.remoteCall, self.window, boundsSEL);
            self.cachedScreenWidth = (gameBounds.size.width > 0.0) ? gameBounds.size.width : MAX(kWidth, kHeight);
            self.cachedScreenHeight = (gameBounds.size.height > 0.0) ? gameBounds.size.height : MIN(kWidth, kHeight);
            LOG(@"[RemoteWebViewOverlay] Game UIWindow bounds: %.0fx%.0f",
                self.cachedScreenWidth, self.cachedScreenHeight);
        } else {
            self.cachedScreenWidth = MAX(kWidth, kHeight);
            self.cachedScreenHeight = MIN(kWidth, kHeight);
            LOG(@"[RemoteWebViewOverlay] Fallback UIScreen: %.0fx%.0f",
                self.cachedScreenWidth, self.cachedScreenHeight);
        }
    }

    if (![[OverlayWebSocketServer sharedServer] start]) {
        LOG(@"[RemoteWebViewOverlay] setupBaseOverlay: WebSocket start failed");
        return NO;
    }

    if (![self ensureWebKitLoaded]) {
        LOG(@"[RemoteWebViewOverlay] WKWebViewConfiguration class not found");
        return NO;
    }

    RemoteObjectRef wkConfigClass = [self getClass:"WKWebViewConfiguration"];
    RemoteObjectRef allocConfig = [self call:wkConfigClass selector:"alloc"];
    if (!allocConfig) {
        LOG(@"[RemoteWebViewOverlay] WKWebViewConfiguration alloc failed");
        return NO;
    }

    RemoteObjectRef config = remote_msg_on_main_thread(
        self.remoteCall, allocConfig, [self getSelector:"init"], NULL, NULL, 0);
    if (!config) {
        LOG(@"[RemoteWebViewOverlay] WKWebViewConfiguration init failed");
        return NO;
    }

    LOG(@"[RemoteWebViewOverlay] WKWebViewConfiguration = 0x%llx", config);

    RemoteObjectRef wkWebViewClass = [self getClass:"WKWebView"];
    if (!wkWebViewClass) {
        LOG(@"[RemoteWebViewOverlay] WKWebView class not found");
        return NO;
    }

    RemoteObjectRef webView = self.webView;
    if (!webView) {
        RemoteObjectRef allocWebView = [self call:wkWebViewClass selector:"alloc"];
        if (!allocWebView) {
            LOG(@"[RemoteWebViewOverlay] WKWebView alloc failed");
            return NO;
        }

        CGRect frame =
            CGRectMake(0, 0, self.cachedScreenWidth, self.cachedScreenHeight);
        const void *params[] = {&frame, &config};
        size_t sizes[] = {sizeof(frame), sizeof(config)};
        webView = remote_msg_on_main_thread(
            self.remoteCall, allocWebView,
            [self getSelector:"initWithFrame:configuration:"], params, sizes,
            2);

        if (!webView) {
            LOG(@"[RemoteWebViewOverlay] WKWebView initWithFrame:configuration: "
                @"failed");
            return NO;
        }
        self.webView = webView;
        LOG(@"[RemoteWebViewOverlay] WKWebView created = 0x%llx", webView);

        {
            RemoteObjectRef uiColorClass = [self getClass:"UIColor"];
            uint64_t clearSEL = [self getSelector:"clearColor"];
            if (uiColorClass && clearSEL) {
                RemoteObjectRef clearColor = remote_msg_on_main_thread(
                    self.remoteCall, uiColorClass, clearSEL, NULL, NULL, 0);
                if (clearColor) {
                    uint64_t bgSEL = [self getSelector:"setBackgroundColor:"];
                    if (bgSEL) {
                        const void *p[] = {&clearColor};
                        size_t s[] = {sizeof(clearColor)};
                        remote_msg_on_main_thread(self.remoteCall, webView, bgSEL,
                                                  p, s, 1);
                    }
                }
            }
        }

        {
            uint64_t sel = [self getSelector:"setUserInteractionEnabled:"];
            if (sel) {
                BOOL enabled = NO;
                const void *p[] = {&enabled};
                size_t s[] = {sizeof(enabled)};
                remote_msg_on_main_thread(self.remoteCall, webView, sel, p, s, 1);
            }
        }

        {
            uint64_t sel = [self getSelector:"setOpaque:"];
            if (sel) {
                BOOL opaque = NO;
                const void *p[] = {&opaque};
                size_t s[] = {sizeof(opaque)};
                remote_msg_on_main_thread(self.remoteCall, webView, sel, p, s, 1);
            }
        }

        [self setAutoresizingForView:webView];

        {
            uint64_t sel = [self getSelector:"setInspectable:"];
            if (sel) {
                BOOL inspectable = g_isDebug ? YES : NO;
                const void *p[] = {&inspectable};
                size_t s[] = {sizeof(inspectable)};
                remote_msg_on_main_thread(self.remoteCall, webView, sel, p, s, 1);
                LOG(@"[RemoteWebViewOverlay] WKWebView inspectable = %s",
                    inspectable ? "YES" : "NO");
            }
        }

        {
            NSString *html = [self loadOverlayHTMLResource:@"overlay_esp"];
            if (!html) {
                LOG(@"[RemoteWebViewOverlay] Failed to load overlay_esp.html");
                return NO;
            }

            uint64_t remoteHTML =
                remote_NSString(self.remoteCall, [html UTF8String]);
            if (!remoteHTML) {
                LOG(@"[RemoteWebViewOverlay] remote_NSString failed for HTML");
                return NO;
            }

            uint64_t loadSEL = [self getSelector:"loadHTMLString:baseURL:"];
            if (loadSEL) {
                uint64_t nilBaseURL = 0;
                const void *p[] = {&remoteHTML, &nilBaseURL};
                size_t s[] = {sizeof(remoteHTML), sizeof(nilBaseURL)};
                remote_msg_on_main_thread(self.remoteCall, webView, loadSEL, p, s,
                                          2);
            }
        }

        {
            uint64_t addSubviewSEL = [self getSelector:"addSubview:"];
            if (addSubviewSEL) {
                const void *p[] = {&webView};
                size_t s[] = {sizeof(webView)};
                remote_msg_on_main_thread(self.remoteCall, self.parentView,
                                          addSubviewSEL, p, s, 1);
            }
        }
    }

    if (!self.menuWebView) {
        CGRect fullScreenFrame =
            CGRectMake(0, 0, self.cachedScreenWidth, self.cachedScreenHeight);
        self.menuWebView = [self createWebViewWithResource:@"overlay_menu"
                                                     frame:fullScreenFrame
                                               interactive:YES
                                                    hidden:YES
                                           autoresizesView:YES];
        if (!self.menuWebView) {
            LOG(@"[RemoteWebViewOverlay] Failed to create menu WebView");
            return NO;
        }
    }

    if (!self.floatButtonWebView) {
        self.floatButtonWebView =
            [self createWebViewWithResource:@"overlay_fab"
                                      frame:[self floatButtonFrame]
                                interactive:YES
                                     hidden:NO
                            autoresizesView:NO];
        if (!self.floatButtonWebView) {
            LOG(@"[RemoteWebViewOverlay] Failed to create float button WebView");
            return NO;
        }
    }

    self.isOverlayReady = YES;

    [self broadcastOverlayLayout];

    LOG(@"[RemoteWebViewOverlay] Base overlay ready: esp=0x%llx menu=0x%llx "
        @"fab=0x%llx size=%.0fx%.0f",
        webView, self.menuWebView, self.floatButtonWebView,
        self.cachedScreenWidth, self.cachedScreenHeight);

    return YES;
}

#pragma mark - Overlay interaction and layout

- (void)setOverlayMenuVisible:(BOOL)visible {
    if (!self.isOverlayReady || !self.menuWebView)
        return;

    @synchronized(self) {
        [self setView:self.menuWebView
            boolValue:!visible
             selector:"setHidden:"];
        self.menuVisible = visible;
        [self broadcastOverlayLayout];
        LOG(@"[RemoteWebViewOverlay] Menu %@", visible ? @"shown" : @"hidden");
    }
}

- (void)toggleOverlayMenu {
    @synchronized(self) {
        [self setOverlayMenuVisible:!self.menuVisible];
    }
}

- (void)setOverlayFloatButtonPositionX:(CGFloat)xRatio y:(CGFloat)yRatio {
    if (!self.isOverlayReady || !self.floatButtonWebView)
        return;

    @synchronized(self) {
        [self refreshWindowBounds];

        CGFloat width = MAX(self.cachedScreenWidth, kOverlayFABSize);
        CGFloat height = MAX(self.cachedScreenHeight, kOverlayFABSize);
        CGFloat maxX = MAX(0.0, width - kOverlayFABSize);
        CGFloat maxY = MAX(0.0, height - kOverlayFABSize);
        CGFloat requestedCenterX = OverlayClamp(xRatio, 0.0, 1.0) * width;
        CGFloat requestedCenterY = OverlayClamp(yRatio, 0.0, 1.0) * height;
        CGFloat x =
            OverlayClamp(requestedCenterX - kOverlayFABSize * 0.5, 0.0, maxX);
        CGFloat y =
            OverlayClamp(requestedCenterY - kOverlayFABSize * 0.5, 0.0, maxY);

        self.hasCustomFloatButtonPosition = YES;
        self.floatButtonXRatio = maxX > 0.0 ? x / maxX : 0.0;
        self.floatButtonYRatio = maxY > 0.0 ? y / maxY : 0.0;
        [self setFrame:[self floatButtonFrame] forView:self.floatButtonWebView];
        [self broadcastOverlayLayout];
    }
}

- (void)refreshOverlayLayout {
    if (!self.isOverlayReady || !self.floatButtonWebView)
        return;

    @synchronized(self) {
        if (![self refreshWindowBounds])
            return;
        [self setFrame:[self floatButtonFrame] forView:self.floatButtonWebView];
        [self broadcastOverlayLayout];
    }
}

#pragma mark - Update overlay targets

- (BOOL)updateOverlayTargets:(NSArray<NSDictionary *> *)targets {
    if (!self.isOverlayReady || !self.webView) {
        return NO;
    }

    NSMutableArray<NSDictionary *> *jsonTargets =
        [NSMutableArray arrayWithCapacity:targets.count];

    for (NSUInteger i = 0; i < targets.count; i++) {
        NSDictionary *data = targets[i];

        NSMutableDictionary *target = [NSMutableDictionary dictionary];
        NSNumber *idVal = data[@"id"] ?: @0;
        target[@"id"] =
            [NSString stringWithFormat:@"0x%llx", idVal.unsignedLongLongValue];
        target[@"name"] = data[@"name"] ?: @"";
        target[@"sx"] = data[@"sx"] ?: @0;
        target[@"sy"] = data[@"sy"] ?: @0;
        target[@"headX"] = data[@"headX"] ?: @0;
        target[@"headY"] = data[@"headY"] ?: @0;
        target[@"footX"] = data[@"footX"] ?: @0;
        target[@"footY"] = data[@"footY"] ?: @0;
        target[@"distance"] = data[@"distance"] ?: @0;
        target[@"visible"] = data[@"visible"] ?: @NO;
        target[@"onScreen"] = data[@"onScreen"] ?: @NO;
        target[@"drawLine"] = data[@"drawLine"] ?: @NO;
        target[@"drawHealth"] = data[@"drawHealth"] ?: @NO;
        target[@"drawName"] = data[@"drawName"] ?: @NO;
        target[@"drawDistance"] = data[@"drawDistance"] ?: @YES;
        target[@"hp"] = data[@"hp"] ?: @0;
        target[@"maxHp"] = data[@"maxHp"] ?: @0;

        BOOL hasBox = [data[@"hasBox"] boolValue];
        CGFloat boxW = [data[@"boxW"] doubleValue];
        CGFloat boxH = [data[@"boxH"] doubleValue];
        if (hasBox && boxW > 0.0 && boxH > 0.0) {
            target[@"box"] = @{
                @"x" : data[@"boxX"] ?: @0,
                @"y" : data[@"boxY"] ?: @0,
                @"w" : data[@"boxW"] ?: @0,
                @"h" : data[@"boxH"] ?: @0
            };
        }

        [jsonTargets addObject:target];
    }

    NSError *jsonError = nil;
    NSDictionary *payload = @{@"type" : @"targets", @"targets" : jsonTargets};
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:payload
                                                       options:0
                                                         error:&jsonError];
    if (!jsonData) {
        LOG(@"[RemoteWebViewOverlay] JSON serialization failed: %@",
            jsonError.localizedDescription ?: @"unknown error");
        return NO;
    }

    NSString *json = [[NSString alloc] initWithData:jsonData
                                           encoding:NSUTF8StringEncoding];
    if (json.length == 0) {
        LOG(@"[RemoteWebViewOverlay] JSON string is empty");
        return NO;
    }

    static NSUInteger updateLogCounter = 0;
    if (g_isDebug && (updateLogCounter++ % 60 == 0)) {
        LOG(@"[RemoteWebViewOverlay] WS update (%lu entities, %lu bytes, "
            @"%lu clients)",
            (unsigned long)targets.count, (unsigned long)jsonData.length,
            (unsigned long)[OverlayWebSocketServer sharedServer].clientCount);
    }

    [[OverlayWebSocketServer sharedServer] broadcastTextData:jsonData];
    return YES;
}

#pragma mark - Clear targets

- (BOOL)clearTargets {
    if (!self.isOverlayReady || !self.webView)
        return NO;

    [[OverlayWebSocketServer sharedServer] broadcastText:@"[]"];
    LOG(@"[RemoteWebViewOverlay] Targets cleared");
    return YES;
}

#pragma mark - Teardown

- (void)teardownOverlay {
    if (!self.isOverlayReady || !self.remoteCall)
        return;

    LOG(@"[RemoteWebViewOverlay] Tearing down overlay (%s)...",
        self.isSpringBoard ? "SpringBoard" : "Internal");

    uint64_t removeSEL = [self getSelector:"removeFromSuperview"];
    if (removeSEL) {
        if (self.floatButtonWebView) {
            remote_msg_on_main_thread(self.remoteCall, self.floatButtonWebView,
                                      removeSEL, NULL, NULL, 0);
            self.floatButtonWebView = 0;
        }
        if (self.menuWebView) {
            remote_msg_on_main_thread(self.remoteCall, self.menuWebView,
                                      removeSEL, NULL, NULL, 0);
            self.menuWebView = 0;
        }
        if (self.webView) {
            remote_msg_on_main_thread(self.remoteCall, self.webView,
                                      removeSEL, NULL, NULL, 0);
            self.webView = 0;
        }
    }

    if (self.window) {
        if (self.isSpringBoard) {
            [self setView:self.window boolValue:YES selector:"setHidden:"];
        }
        self.window = 0;
        self.parentView = 0;
    }

    self.isOverlayReady = NO;
    self.menuVisible = NO;
}

@end
