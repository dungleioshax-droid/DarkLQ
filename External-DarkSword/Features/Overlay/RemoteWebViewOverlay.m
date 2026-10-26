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
@property(nonatomic, assign) RemoteObjectRef springBoardLabel;
@property(nonatomic, assign) RemoteObjectRef springBoardContainer;
@property(nonatomic, assign, readwrite) BOOL isOverlayReady;
@property(nonatomic, assign, readwrite) CGFloat cachedScreenWidth;
@property(nonatomic, assign, readwrite) CGFloat cachedScreenHeight;
@property(nonatomic, assign) BOOL menuVisible;
@property(nonatomic, assign) BOOL hasCustomFloatButtonPosition;
@property(nonatomic, assign) CGFloat floatButtonXRatio;
@property(nonatomic, assign) CGFloat floatButtonYRatio;

@end

#pragma mark - DarkSpeed SpringBoard Thread-Safe Helpers

static NSMutableDictionary<NSString *, NSNumber *> *g_sbClassCache = nil;
static NSMutableDictionary<NSString *, NSNumber *> *g_sbSelectorCache = nil;

static uint64_t ds_remote_class(RemoteCall *process, const char *name) {
    if (!process || !process.trojanMem || !name) return 0;
    if (!g_sbClassCache) g_sbClassCache = [NSMutableDictionary dictionary];
    NSString *key = [NSString stringWithUTF8String:name];
    if (!key) return 0;
    NSNumber *cached = g_sbClassCache[key];
    if (cached) return cached.unsignedLongLongValue;
    uint64_t value = remote_getClass(process, name);
    if (value) g_sbClassCache[key] = @(value);
    return value;
}

static uint64_t ds_remote_sel(RemoteCall *process, const char *name) {
    if (!process || !process.trojanMem || !name) return 0;
    if (!g_sbSelectorCache) g_sbSelectorCache = [NSMutableDictionary dictionary];
    NSString *key = [NSString stringWithUTF8String:name];
    if (!key) return 0;
    NSNumber *cached = g_sbSelectorCache[key];
    if (cached) return cached.unsignedLongLongValue;
    uint64_t value = remote_sel(process, name);
    if (value) g_sbSelectorCache[key] = @(value);
    return value;
}

static BOOL ds_perform_on_springboard_main(RemoteCall *process, uint64_t target,
                                           uint64_t selector, uint64_t argument,
                                           BOOL waitUntilDone) {
    if (!process || !process.trojanMem || !target || !selector) return NO;
    uint64_t perform = ds_remote_sel(process, "performSelectorOnMainThread:withObject:waitUntilDone:");
    if (!perform) return NO;
    // a0=selector, a1=object, a2=waitUntilDone (BOOL as uint64 on little-endian).
    remote_msg(process, target, perform, selector, argument, waitUntilDone ? 1 : 0, 0);
    return process.trojanMem != 0;
}

typedef struct {
    const void *bytes;
    uint64_t size;
} DSRemoteArg;

static BOOL ds_remote_invoke_on_main_result(RemoteCall *process, uint64_t target,
                                            uint64_t selector,
                                            const DSRemoteArg *arguments,
                                            NSUInteger argumentCount,
                                            void *result,
                                            NSUInteger resultSize) {
    if (!process || !target || !selector || !process.trojanMem) return NO;

    uint64_t poolClass = ds_remote_class(process, "NSAutoreleasePool");
    uint64_t allocSelector = ds_remote_sel(process, "alloc");
    uint64_t initSelector = ds_remote_sel(process, "init");
    uint64_t drainSelector = ds_remote_sel(process, "drain");
    uint64_t autoreleasePool = (poolClass && allocSelector && initSelector && drainSelector)
        ? remote_msg(process,
                     remote_msg(process, poolClass, allocSelector, 0, 0, 0, 0),
                     initSelector, 0, 0, 0, 0)
        : 0;
    if (!autoreleasePool) return NO;

    @try {
        uint64_t signature = remote_msg(process, target,
                                        ds_remote_sel(process, "methodSignatureForSelector:"),
                                        selector, 0, 0, 0);
        if (!process.trojanMem) return NO;
        uint64_t invocationClass = ds_remote_class(process, "NSInvocation");
        uint64_t invocation = (signature && invocationClass)
            ? remote_msg(process, invocationClass,
                         ds_remote_sel(process, "invocationWithMethodSignature:"),
                         signature, 0, 0, 0)
            : 0;
        if (!invocation || !process.trojanMem) return NO;

        remote_msg(process, invocation, ds_remote_sel(process, "setTarget:"), target, 0, 0, 0);
        if (!process.trojanMem) return NO;
        remote_msg(process, invocation, ds_remote_sel(process, "setSelector:"), selector, 0, 0, 0);
        if (!process.trojanMem) return NO;

        uint64_t scratch = process.trojanMem + 0x800;
        for (NSUInteger index = 0; index < argumentCount; index++) {
            if (!arguments[index].bytes || arguments[index].size == 0 ||
                ![process remote_write:scratch
                                  from:arguments[index].bytes
                                  size:arguments[index].size]) {
                return NO;
            }
            remote_msg(process, invocation, ds_remote_sel(process, "setArgument:atIndex:"),
                       scratch, index + 2, 0, 0);
            if (!process.trojanMem) return NO;
            scratch += (arguments[index].size + 15) & ~15ULL;
        }

        ds_perform_on_springboard_main(process, invocation,
                                       ds_remote_sel(process, "invoke"), 0, YES);
        if (!process.trojanMem) return NO;
        if (result && resultSize > 0) {
            uint64_t resultScratch = process.trojanMem + 0xC00;
            memset(result, 0, resultSize);
            if (![process remote_write:resultScratch from:result size:resultSize]) return NO;
            remote_msg(process, invocation, ds_remote_sel(process, "getReturnValue:"),
                       resultScratch, 0, 0, 0);
            if (!process.trojanMem) return NO;
            if (![process remoteRead:resultScratch to:result size:resultSize]) return NO;
        }
        return YES;
    } @finally {
        if (process.trojanMem) {
            remote_msg(process, autoreleasePool, drainSelector, 0, 0, 0, 0);
        }
    }
}

static BOOL ds_remote_invoke_noarg_on_main(RemoteCall *process, uint64_t target,
                                           const char *selectorName) {
    return ds_remote_invoke_on_main_result(process, target, ds_remote_sel(process, selectorName),
                                           NULL, 0, NULL, 0);
}

static uint64_t ds_remote_get_object_on_main(RemoteCall *process, uint64_t target,
                                             const char *selectorName) {
    uint64_t result = 0;
    BOOL invoked = ds_remote_invoke_on_main_result(
        process, target, ds_remote_sel(process, selectorName), NULL, 0,
        &result, sizeof(result));
    return invoked ? result : 0;
}

static BOOL ds_remote_set_u64_on_main(RemoteCall *process, uint64_t target,
                                      const char *selectorName, uint64_t value) {
    DSRemoteArg argument = { &value, sizeof(value) };
    return ds_remote_invoke_on_main_result(process, target, ds_remote_sel(process, selectorName),
                                           &argument, 1, NULL, 0);
}

static BOOL ds_remote_set_double_on_main(RemoteCall *process, uint64_t target,
                                         const char *selectorName, double value) {
    DSRemoteArg argument = { &value, sizeof(value) };
    return ds_remote_invoke_on_main_result(process, target, ds_remote_sel(process, selectorName),
                                           &argument, 1, NULL, 0);
}

static BOOL ds_remote_set_rect_on_main(RemoteCall *process, uint64_t target,
                                       const char *selectorName, CGRect value) {
    DSRemoteArg argument = { &value, sizeof(value) };
    return ds_remote_invoke_on_main_result(process, target, ds_remote_sel(process, selectorName),
                                           &argument, 1, NULL, 0);
}

static uint64_t ds_remote_create_string(RemoteCall *process, NSString *value) {
    if (!process || !process.trojanMem || !value) return 0;
    const char *utf8 = value.UTF8String;
    if (!utf8) return 0;
    size_t length = strlen(utf8) + 1;
    if (length > 0x800) return 0;

    uint64_t scratch = process.trojanMem + 0x1000;
    if (![process remote_write:scratch from:utf8 size:length]) return 0;

    uint64_t stringClass = ds_remote_class(process, "NSString");
    uint64_t alloc = ds_remote_sel(process, "alloc");
    uint64_t init = ds_remote_sel(process, "initWithUTF8String:");
    if (!stringClass || !alloc || !init) return 0;
    uint64_t object = remote_msg(process, stringClass, alloc, 0, 0, 0, 0);
    if (!object) return 0;
    uint64_t string = remote_msg(process, object, init, scratch, 0, 0, 0);
    if (!string) {
        uint64_t release = ds_remote_sel(process, "release");
        if (release) remote_msg(process, object, release, 0, 0, 0, 0);
    }
    return string;
}

static BOOL ds_remote_set_text_on_main(RemoteCall *process, uint64_t label,
                                       NSString *text) {
    uint64_t remoteText = ds_remote_create_string(process, text);
    if (!remoteText) return NO;
    BOOL sent = ds_perform_on_springboard_main(
        process, label, ds_remote_sel(process, "setText:"), remoteText, YES);
    uint64_t release = ds_remote_sel(process, "release");
    if (release && process.trojanMem) {
        remote_msg(process, remoteText, release, 0, 0, 0, 0);
    }
    return sent;
}

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
        _springBoardLabel = 0;
        _springBoardContainer = 0;
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
    LOG(@"[RemoteWebViewOverlay] Setting up SpringBoard overlay window (DarkSpeed style)...");

    uint64_t workspaceClass = ds_remote_class(self.remoteCall, "SBMainWorkspace");
    uint64_t windowClass = ds_remote_class(self.remoteCall, "UIWindow");
    uint64_t viewClass = ds_remote_class(self.remoteCall, "UIView");
    uint64_t labelClass = ds_remote_class(self.remoteCall, "UILabel");
    uint64_t colorClass = ds_remote_class(self.remoteCall, "UIColor");

    if (!workspaceClass || !windowClass || !viewClass || !labelClass || !colorClass) {
        LOG(@"[RemoteWebViewOverlay] Required SpringBoard classes not found");
        return NO;
    }

    uint64_t workspace = ds_remote_get_object_on_main(self.remoteCall, workspaceClass, "sharedInstance");
    uint64_t scene = workspace ? ds_remote_get_object_on_main(self.remoteCall, workspace, "mainWindowScene") : 0;
    if (!scene) {
        LOG(@"[RemoteWebViewOverlay] SBMainWorkspace mainWindowScene not found");
        return NO;
    }

    uint64_t allocSEL = ds_remote_sel(self.remoteCall, "alloc");
    uint64_t window = remote_msg(self.remoteCall, windowClass, allocSEL, 0, 0, 0, 0);
    uint64_t container = remote_msg(self.remoteCall, viewClass, allocSEL, 0, 0, 0, 0);
    uint64_t label = remote_msg(self.remoteCall, labelClass, allocSEL, 0, 0, 0, 0);

    if (!window || !container || !label) {
        LOG(@"[RemoteWebViewOverlay] Failed to alloc SpringBoard window/container/label");
        return NO;
    }

    if (!ds_remote_invoke_noarg_on_main(self.remoteCall, window, "init") ||
        !ds_remote_invoke_noarg_on_main(self.remoteCall, container, "init") ||
        !ds_remote_invoke_noarg_on_main(self.remoteCall, label, "init")) {
        LOG(@"[RemoteWebViewOverlay] Failed to init SpringBoard window/container/label on main thread");
        return NO;
    }

    CGFloat screenW = MAX(kWidth, kHeight);
    CGFloat screenH = MIN(kWidth, kHeight);
    self.cachedScreenWidth = screenW;
    self.cachedScreenHeight = screenH;

    CGRect fullFrame = CGRectMake(0, 0, screenW, screenH);
    ds_remote_set_rect_on_main(self.remoteCall, window, "setFrame:", fullFrame);
    ds_perform_on_springboard_main(self.remoteCall, window, ds_remote_sel(self.remoteCall, "setWindowScene:"), scene, YES);
    ds_remote_set_double_on_main(self.remoteCall, window, "setWindowLevel:", 10000010.0);
    ds_remote_set_u64_on_main(self.remoteCall, window, "setUserInteractionEnabled:", 0);
    ds_remote_set_u64_on_main(self.remoteCall, window, "setOpaque:", 0);

    // Position HUD container at top center
    CGFloat hudW = 340.0;
    CGFloat hudH = 30.0;
    CGRect hudFrame = CGRectMake(MAX(0.0, (screenW - hudW) * 0.5), 10.0, hudW, hudH);
    ds_remote_set_rect_on_main(self.remoteCall, container, "setFrame:", hudFrame);
    ds_remote_set_rect_on_main(self.remoteCall, label, "setFrame:", CGRectMake(0, 0, hudW, hudH));

    uint64_t clearColor = ds_remote_get_object_on_main(self.remoteCall, colorClass, "clearColor");
    uint64_t whiteColor = ds_remote_get_object_on_main(self.remoteCall, colorClass, "whiteColor");
    uint64_t darkBgColor = ds_remote_get_object_on_main(self.remoteCall, colorClass, "darkGrayColor");

    if (clearColor) {
        ds_perform_on_springboard_main(self.remoteCall, window, ds_remote_sel(self.remoteCall, "setBackgroundColor:"), clearColor, YES);
        ds_perform_on_springboard_main(self.remoteCall, label, ds_remote_sel(self.remoteCall, "setBackgroundColor:"), clearColor, YES);
    }
    if (darkBgColor) {
        ds_perform_on_springboard_main(self.remoteCall, container, ds_remote_sel(self.remoteCall, "setBackgroundColor:"), darkBgColor, YES);
    }
    if (whiteColor) {
        ds_perform_on_springboard_main(self.remoteCall, label, ds_remote_sel(self.remoteCall, "setTextColor:"), whiteColor, YES);
    }

    ds_remote_set_u64_on_main(self.remoteCall, label, "setTextAlignment:", (uint64_t)NSTextAlignmentCenter);
    ds_remote_set_double_on_main(self.remoteCall, container, "setAlpha:", 0.85);

    uint64_t containerLayer = ds_remote_get_object_on_main(self.remoteCall, container, "layer");
    if (containerLayer) {
        ds_remote_set_double_on_main(self.remoteCall, containerLayer, "setCornerRadius:", 6.0);
        ds_remote_set_u64_on_main(self.remoteCall, containerLayer, "setMasksToBounds:", 1);
    }

    ds_remote_set_text_on_main(self.remoteCall, label, @"DarkSword AoV Overlay: Ready");

    ds_perform_on_springboard_main(self.remoteCall, container, ds_remote_sel(self.remoteCall, "addSubview:"), label, YES);
    ds_perform_on_springboard_main(self.remoteCall, window, ds_remote_sel(self.remoteCall, "addSubview:"), container, YES);
    ds_remote_set_u64_on_main(self.remoteCall, window, "setHidden:", 0);

    self.window = window;
    self.parentView = window;
    self.springBoardLabel = label;
    self.springBoardContainer = container;
    self.isOverlayReady = YES;

    LOG(@"[RemoteWebViewOverlay] SpringBoard overlay window ready (window=0x%llx, scene=0x%llx)", window, scene);
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
    if (self.isOverlayReady && (self.webView || self.isSpringBoard)) {
        return YES;
    }

    LOG(@"[RemoteWebViewOverlay] Setting up base overlay (%s)...",
        self.isSpringBoard ? "SpringBoard" : "Internal");

    if (self.isSpringBoard) {
        if (![self setupSpringBoardOverlayWindow]) {
            LOG(@"[RemoteWebViewOverlay] setupSpringBoardOverlayWindow failed");
            return NO;
        }
        self.isOverlayReady = YES;
        return YES;
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
    if (!self.isOverlayReady) {
        return NO;
    }

    if (self.isSpringBoard) {
        if (self.springBoardLabel) {
            static CFAbsoluteTime lastLabelUpdate = 0;
            CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
            if (now - lastLabelUpdate >= 0.25) { // Throttle to 4 updates per sec for SpringBoard
                lastLabelUpdate = now;
                NSString *hudText = nil;
                if (targets.count == 0) {
                    hudText = @"[AoV] Khong co dich gan";
                } else {
                    NSDictionary *nearest = targets.firstObject;
                    NSString *name = nearest[@"name"] ?: @"Dich";
                    NSNumber *hp = nearest[@"hp"] ?: @0;
                    NSNumber *maxHp = nearest[@"maxHp"] ?: @1;
                    NSNumber *dist = nearest[@"distance"] ?: @0;
                    int percent = (maxHp.intValue > 0) ? (int)((hp.floatValue / maxHp.floatValue) * 100.0) : 0;
                    hudText = [NSString stringWithFormat:@"[AoV] Dich: %lu | Gan nhat: %@ (%dm - %d%%)",
                               (unsigned long)targets.count, name, dist.intValue, percent];
                }
                ds_remote_set_text_on_main(self.remoteCall, self.springBoardLabel, hudText);
            }
        }
        return YES;
    }

    if (!self.webView) {
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
    if (!self.isOverlayReady)
        return NO;

    if (self.isSpringBoard) {
        if (self.springBoardLabel) {
            ds_remote_set_text_on_main(self.remoteCall, self.springBoardLabel, @"[AoV] Dang quet...");
        }
        return YES;
    }

    if (!self.webView)
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

    if (self.isSpringBoard) {
        if (self.springBoardContainer) {
            uint64_t removeSEL = ds_remote_sel(self.remoteCall, "removeFromSuperview");
            if (removeSEL) {
                ds_perform_on_springboard_main(self.remoteCall, self.springBoardContainer, removeSEL, 0, YES);
            }
            self.springBoardContainer = 0;
            self.springBoardLabel = 0;
        }
        if (self.window) {
            ds_remote_set_u64_on_main(self.remoteCall, self.window, "setHidden:", 1);
            self.window = 0;
            self.parentView = 0;
        }
        self.isOverlayReady = NO;
        self.menuVisible = NO;
        return;
    }

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
        self.window = 0;
        self.parentView = 0;
    }

    self.isOverlayReady = NO;
    self.menuVisible = NO;
}

@end
