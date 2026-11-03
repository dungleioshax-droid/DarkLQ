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

#pragma mark - DarkSpeed SpringBoard Thread-Safe Helpers

static NSMutableDictionary<NSString *, NSNumber *> *g_sbClassCache = nil;
static NSMutableDictionary<NSString *, NSNumber *> *g_sbSelectorCache = nil;
static NSMutableDictionary<NSString *, NSNumber *> *g_sbInvCache = nil;
static NSRecursiveLock *g_sbLock = nil;
static CFAbsoluteTime s_sbOverlayReadyAt = 0;
static RemoteObjectRef s_sbRedColor = 0;
static RemoteObjectRef s_sbYellowColor = 0;
static RemoteObjectRef s_sbGreenColor = 0;

static uint64_t ds_remote_class(RemoteCall *process, const char *name);
static uint64_t ds_remote_sel(RemoteCall *process, const char *name);

static void ds_sb_lock_init(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        g_sbLock = [[NSRecursiveLock alloc] init];
    });
}

static inline NSString *ds_inv_cache_key(uint64_t target, uint64_t selector) {
    return [NSString stringWithFormat:@"%llx_%llx", (unsigned long long)target, (unsigned long long)selector];
}

static uint64_t ds_inv_cache_get(RemoteCall *process, uint64_t target, uint64_t selector) {
    if (!process || !process.trojanMem || !target || !selector || !g_sbInvCache) return 0;
    NSNumber *hit = g_sbInvCache[ds_inv_cache_key(target, selector)];
    return hit ? hit.unsignedLongLongValue : 0;
}

static void ds_inv_cache_put(RemoteCall *process, uint64_t target, uint64_t selector, uint64_t invocation) {
    if (!process || !process.trojanMem || !target || !selector || !invocation) return;
    if (!g_sbInvCache) g_sbInvCache = [NSMutableDictionary dictionary];
    g_sbInvCache[ds_inv_cache_key(target, selector)] = @(invocation);
}

static void ds_inv_cache_clear(RemoteCall *process) {
    if (!g_sbInvCache) return;
    if (process && process.trojanMem) {
        uint64_t relSel = ds_remote_sel(process, "release");
        if (relSel) {
            for (NSNumber *num in g_sbInvCache.allValues) {
                uint64_t inv = num.unsignedLongLongValue;
                if (inv) remote_msg(process, inv, relSel, 0, 0, 0, 0);
            }
        }
    }
    [g_sbInvCache removeAllObjects];
}

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
                                            NSUInteger resultSize,
                                            BOOL retainResultObject) {
    if (!process || !target || !selector || !process.trojanMem) return NO;

    ds_sb_lock_init();
    [g_sbLock lock];
    @try {
        BOOL wantResult = (result && resultSize > 0);
        uint64_t cachedInv = wantResult ? 0 : ds_inv_cache_get(process, target, selector);

        uint64_t autoreleasePool = 0;
        uint64_t drainSelector = 0;
        if (!cachedInv) {
            uint64_t poolClass = ds_remote_class(process, "NSAutoreleasePool");
            uint64_t allocSelector = ds_remote_sel(process, "alloc");
            uint64_t initSelector = ds_remote_sel(process, "init");
            drainSelector = ds_remote_sel(process, "drain");
            autoreleasePool = (poolClass && allocSelector && initSelector && drainSelector)
                ? remote_msg(process,
                             remote_msg(process, poolClass, allocSelector, 0, 0, 0, 0),
                             initSelector, 0, 0, 0, 0)
                : 0;
            if (!autoreleasePool) return NO;
        }

        @try {
            uint64_t invocation = cachedInv;
            if (!invocation) {
                uint64_t signature = remote_msg(process, target,
                                                ds_remote_sel(process, "methodSignatureForSelector:"),
                                                selector, 0, 0, 0);
                if (!process.trojanMem) return NO;
                uint64_t invocationClass = ds_remote_class(process, "NSInvocation");
                invocation = (signature && invocationClass)
                    ? remote_msg(process, invocationClass,
                                 ds_remote_sel(process, "invocationWithMethodSignature:"),
                                 signature, 0, 0, 0)
                    : 0;
                if (!invocation || !process.trojanMem) return NO;

                remote_msg(process, invocation, ds_remote_sel(process, "setTarget:"), target, 0, 0, 0);
                if (!process.trojanMem) return NO;
                remote_msg(process, invocation, ds_remote_sel(process, "setSelector:"), selector, 0, 0, 0);
                if (!process.trojanMem) return NO;

                if (!wantResult) {
                    remote_msg(process, invocation, ds_remote_sel(process, "retain"), 0, 0, 0, 0);
                    if (process.trojanMem) {
                        ds_inv_cache_put(process, target, selector, invocation);
                    }
                }
            }

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
            if (wantResult) {
                uint64_t resultScratch = process.trojanMem + 0xC00;
                memset(result, 0, resultSize);
                if (![process remote_write:resultScratch from:result size:resultSize]) return NO;
                remote_msg(process, invocation, ds_remote_sel(process, "getReturnValue:"),
                           resultScratch, 0, 0, 0);
                if (!process.trojanMem) return NO;
                if (![process remoteRead:resultScratch to:result size:resultSize]) return NO;

                if (retainResultObject && resultSize == sizeof(uint64_t)) {
                    uint64_t obj = *(uint64_t *)result;
                    if (obj && process.trojanMem) {
                        remote_msg(process, obj, ds_remote_sel(process, "retain"), 0, 0, 0, 0);
                    }
                }
            }
            return YES;
        } @finally {
            if (autoreleasePool && process.trojanMem && drainSelector) {
                remote_msg(process, autoreleasePool, drainSelector, 0, 0, 0, 0);
            }
        }
    } @finally {
        [g_sbLock unlock];
    }
}

static BOOL ds_remote_invoke_noarg_on_main(RemoteCall *process, uint64_t target,
                                           const char *selectorName) {
    return ds_remote_invoke_on_main_result(process, target, ds_remote_sel(process, selectorName),
                                           NULL, 0, NULL, 0, NO);
}

static uint64_t ds_remote_get_object_on_main(RemoteCall *process, uint64_t target,
                                             const char *selectorName) {
    uint64_t result = 0;
    BOOL invoked = ds_remote_invoke_on_main_result(
        process, target, ds_remote_sel(process, selectorName), NULL, 0,
        &result, sizeof(result), NO);
    return invoked ? result : 0;
}

static uint64_t ds_remote_get_u64_on_main(RemoteCall *process, uint64_t target,
                                          const char *selectorName) {
    return ds_remote_get_object_on_main(process, target, selectorName);
}

static uint64_t ds_remote_get_retained_object_on_main(RemoteCall *process, uint64_t target,
                                                      const char *selectorName) {
    uint64_t result = 0;
    BOOL invoked = ds_remote_invoke_on_main_result(
        process, target, ds_remote_sel(process, selectorName), NULL, 0,
        &result, sizeof(result), YES);
    return invoked ? result : 0;
}

static BOOL ds_remote_set_u64_on_main(RemoteCall *process, uint64_t target,
                                      const char *selectorName, uint64_t value) {
    DSRemoteArg argument = { &value, sizeof(value) };
    return ds_remote_invoke_on_main_result(process, target, ds_remote_sel(process, selectorName),
                                           &argument, 1, NULL, 0, NO);
}

static BOOL ds_remote_set_double_on_main(RemoteCall *process, uint64_t target,
                                         const char *selectorName, double value) {
    DSRemoteArg argument = { &value, sizeof(value) };
    return ds_remote_invoke_on_main_result(process, target, ds_remote_sel(process, selectorName),
                                           &argument, 1, NULL, 0, NO);
}

static BOOL ds_remote_set_rect_on_main(RemoteCall *process, uint64_t target,
                                       const char *selectorName, CGRect value) {
    if (!isfinite(value.origin.x) || !isfinite(value.origin.y) ||
        !isfinite(value.size.width) || !isfinite(value.size.height) ||
        value.size.width < 0 || value.size.height < 0 ||
        value.size.width > 50000 || value.size.height > 50000) {
        return NO;
    }
    DSRemoteArg argument = { &value, sizeof(value) };
    return ds_remote_invoke_on_main_result(process, target, ds_remote_sel(process, selectorName),
                                           &argument, 1, NULL, 0, NO);
}

static BOOL ds_remote_set_point_on_main(RemoteCall *process, uint64_t target,
                                       const char *selectorName, CGPoint value) {
    if (!isfinite(value.x) || !isfinite(value.y) ||
        fabs(value.x) > 50000.0 || fabs(value.y) > 50000.0) {
        return NO;
    }
    DSRemoteArg argument = { &value, sizeof(value) };
    return ds_remote_invoke_on_main_result(process, target, ds_remote_sel(process, selectorName),
                                           &argument, 1, NULL, 0, NO);
}

static BOOL ds_remote_set_transform_on_main(RemoteCall *process, uint64_t target,
                                           const char *selectorName, CGAffineTransform value) {
    if (!isfinite(value.a) || !isfinite(value.b) ||
        !isfinite(value.c) || !isfinite(value.d) ||
        !isfinite(value.tx) || !isfinite(value.ty)) {
        return NO;
    }
    DSRemoteArg argument = { &value, sizeof(value) };
    return ds_remote_invoke_on_main_result(process, target, ds_remote_sel(process, selectorName),
                                           &argument, 1, NULL, 0, NO);
}

static CGPoint ClampRayToScreen(CGPoint start, CGPoint target, CGFloat sw, CGFloat sh, CGFloat margin) {
    if (!isfinite(target.x) || !isfinite(target.y)) {
        return start;
    }
    if (sw <= 100.0 || sh <= 100.0) {
        return target;
    }

    CGFloat minX = margin;
    CGFloat maxX = MAX(sw - margin, minX + 1.0);
    CGFloat minY = margin;
    CGFloat maxY = MAX(sh - margin, minY + 1.0);

    CGFloat dx = target.x - start.x;
    CGFloat dy = target.y - start.y;

    if (fabs(dx) < 0.001 && fabs(dy) < 0.001) {
        return target;
    }

    CGFloat t = 1.0;

    if (dx > 0.001) {
        CGFloat tx = (maxX - start.x) / dx;
        if (tx < t) t = tx;
    } else if (dx < -0.001) {
        CGFloat tx = (minX - start.x) / dx;
        if (tx < t) t = tx;
    }

    if (dy > 0.001) {
        CGFloat ty = (maxY - start.y) / dy;
        if (ty < t) t = ty;
    } else if (dy < -0.001) {
        CGFloat ty = (minY - start.y) / dy;
        if (ty < t) t = ty;
    }

    if (t < 0.0) t = 0.0;
    if (t > 1.0) t = 1.0;

    CGFloat cx = start.x + t * dx;
    CGFloat cy = start.y + t * dy;

    cx = OverlayClamp(cx, minX, maxX);
    cy = OverlayClamp(cy, minY, maxY);

    return CGPointMake(cx, cy);
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

static const NSUInteger kMaxOverlaySlots = 10;
static const NSUInteger kMaxSpringBoardSlots = kMaxOverlaySlots;

typedef struct {
    RemoteObjectRef boxView;
    RemoteObjectRef hpBgView;
    RemoteObjectRef hpFillView;
    RemoteObjectRef distLabel;
    RemoteObjectRef nameLabel;
    RemoteObjectRef lineView;
    RemoteObjectRef lineDotView;

    CGRect lastBoxFrame;
    CGRect lastHpBgFrame;
    CGRect lastHpFillFrame;
    CGRect lastDistFrame;
    CGRect lastNameFrame;
    CGFloat lastLineLength;
    CGFloat lastLineAngle;
    CGPoint lastLineCenter;
    CGPoint lastDotCenter;

    BOOL isBoxVisible;
    BOOL isHpVisible;
    BOOL isDistVisible;
    BOOL isNameVisible;
    BOOL isLineVisible;
    BOOL isDotVisible;

    int lastHpColorState; // 1 = red, 2 = yellow, 3 = green
    char lastNameBuf[64];
    int lastDistance;
    CFAbsoluteTime lastDistUpdate;
} SpringBoardESPSlot;

static inline BOOL IsFrameSignificantlyDifferent(CGRect a, CGRect b) {
    return fabs(a.origin.x - b.origin.x) > 0.05 ||
           fabs(a.origin.y - b.origin.y) > 0.05 ||
           fabs(a.size.width - b.size.width) > 0.05 ||
           fabs(a.size.height - b.size.height) > 0.05;
}

static inline BOOL IsLineSignificantlyDifferent(CGFloat lenA, CGFloat lenB,
                                                CGFloat angleA, CGFloat angleB,
                                                CGPoint centerA, CGPoint centerB) {
    return fabs(lenA - lenB) > 0.05 ||
           fabs(angleA - angleB) > 0.001 ||
           fabs(centerA.x - centerB.x) > 0.05 ||
           fabs(centerA.y - centerB.y) > 0.05;
}

@implementation RemoteWebViewOverlay {
    SpringBoardESPSlot _espSlots[kMaxSpringBoardSlots];
}

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
        memset(_espSlots, 0, sizeof(_espSlots));
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
        self.cachedScreenWidth = MAX(bounds.size.width, bounds.size.height);
        self.cachedScreenHeight = MIN(bounds.size.width, bounds.size.height);
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

- (void)setupESPSlotsOnParentView:(uint64_t)parentView
                        viewClass:(uint64_t)viewClass
                       labelClass:(uint64_t)labelClass
                         allocSEL:(uint64_t)allocSEL
                       clearColor:(uint64_t)clearColor
                       whiteColor:(uint64_t)whiteColor
                       greenColor:(uint64_t)greenColor
                      yellowColor:(uint64_t)yellowColor
                       blackColor:(uint64_t)blackColor
                     whiteCGColor:(uint64_t)whiteCGColor
                         distFont:(uint64_t)distFont
                         nameFont:(uint64_t)nameFont {
    uint64_t addSubSEL = ds_remote_sel(self.remoteCall, "addSubview:");
    for (NSUInteger i = 0; i < kMaxOverlaySlots; i++) {
        SpringBoardESPSlot *slot = &_espSlots[i];
        memset(slot, 0, sizeof(SpringBoardESPSlot));

        // 1. Box view (exact internal style: white 0.70 alpha, width 1.25, cornerRadius 0)
        uint64_t box = remote_msg(self.remoteCall, viewClass, allocSEL, 0, 0, 0, 0);
        if (box && ds_remote_invoke_noarg_on_main(self.remoteCall, box, "init")) {
            ds_perform_on_springboard_main(self.remoteCall, box, ds_remote_sel(self.remoteCall, "setBackgroundColor:"), clearColor, YES);
            ds_remote_set_double_on_main(self.remoteCall, box, "setAlpha:", 0.70);
            ds_remote_set_u64_on_main(self.remoteCall, box, "setUserInteractionEnabled:", 0);
            ds_remote_set_u64_on_main(self.remoteCall, box, "setHidden:", 1);

            uint64_t boxLayer = ds_remote_get_object_on_main(self.remoteCall, box, "layer");
            if (boxLayer) {
                if (whiteCGColor) {
                    ds_remote_set_u64_on_main(self.remoteCall, boxLayer, "setBorderColor:", whiteCGColor);
                }
                ds_remote_set_double_on_main(self.remoteCall, boxLayer, "setBorderWidth:", 1.25);
                ds_remote_set_double_on_main(self.remoteCall, boxLayer, "setCornerRadius:", 0.0);
                ds_remote_set_double_on_main(self.remoteCall, boxLayer, "setSpeed:", 999.0);
            }
            ds_perform_on_springboard_main(self.remoteCall, parentView, addSubSEL, box, YES);
            slot->boxView = box;
        }

        // 2. HP background view (exact internal style: black 0.55 alpha, height 5.0, cornerRadius 1.0)
        uint64_t hpBg = remote_msg(self.remoteCall, viewClass, allocSEL, 0, 0, 0, 0);
        if (hpBg && ds_remote_invoke_noarg_on_main(self.remoteCall, hpBg, "init")) {
            ds_perform_on_springboard_main(self.remoteCall, hpBg, ds_remote_sel(self.remoteCall, "setBackgroundColor:"), blackColor, YES);
            ds_remote_set_double_on_main(self.remoteCall, hpBg, "setAlpha:", 0.55);
            ds_remote_set_u64_on_main(self.remoteCall, hpBg, "setUserInteractionEnabled:", 0);
            ds_remote_set_u64_on_main(self.remoteCall, hpBg, "setHidden:", 1);

            uint64_t hpBgLayer = ds_remote_get_object_on_main(self.remoteCall, hpBg, "layer");
            if (hpBgLayer) {
                ds_remote_set_double_on_main(self.remoteCall, hpBgLayer, "setCornerRadius:", 1.0);
                ds_remote_set_u64_on_main(self.remoteCall, hpBgLayer, "setMasksToBounds:", 1);
                ds_remote_set_double_on_main(self.remoteCall, hpBgLayer, "setSpeed:", 999.0);
            }
            ds_perform_on_springboard_main(self.remoteCall, parentView, addSubSEL, hpBg, YES);
            slot->hpBgView = hpBg;

            // 3. HP fill view (added to hpBg, dynamic Green/Yellow/Red, height 4.0)
            uint64_t hpFill = remote_msg(self.remoteCall, viewClass, allocSEL, 0, 0, 0, 0);
            if (hpFill && ds_remote_invoke_noarg_on_main(self.remoteCall, hpFill, "init")) {
                ds_perform_on_springboard_main(self.remoteCall, hpFill, ds_remote_sel(self.remoteCall, "setBackgroundColor:"), greenColor, YES);
                ds_remote_set_u64_on_main(self.remoteCall, hpFill, "setUserInteractionEnabled:", 0);
                uint64_t hpFillLayer = ds_remote_get_object_on_main(self.remoteCall, hpFill, "layer");
                if (hpFillLayer) {
                    ds_remote_set_double_on_main(self.remoteCall, hpFillLayer, "setSpeed:", 999.0);
                }
                ds_perform_on_springboard_main(self.remoteCall, hpBg, addSubSEL, hpFill, YES);
                slot->hpFillView = hpFill;
            }
        }

        // 4. Distance label (exact internal style: [ 15m ] in Yellow, bold 11px, centered below feet)
        uint64_t distLbl = remote_msg(self.remoteCall, labelClass, allocSEL, 0, 0, 0, 0);
        if (distLbl && ds_remote_invoke_noarg_on_main(self.remoteCall, distLbl, "init")) {
            ds_perform_on_springboard_main(self.remoteCall, distLbl, ds_remote_sel(self.remoteCall, "setBackgroundColor:"), clearColor, YES);
            ds_perform_on_springboard_main(self.remoteCall, distLbl, ds_remote_sel(self.remoteCall, "setTextColor:"), yellowColor, YES);
            ds_remote_set_u64_on_main(self.remoteCall, distLbl, "setTextAlignment:", (uint64_t)NSTextAlignmentCenter);
            ds_remote_set_u64_on_main(self.remoteCall, distLbl, "setUserInteractionEnabled:", 0);
            ds_remote_set_u64_on_main(self.remoteCall, distLbl, "setHidden:", 1);

            uint64_t dLayer = ds_remote_get_object_on_main(self.remoteCall, distLbl, "layer");
            if (dLayer) {
                ds_remote_set_double_on_main(self.remoteCall, dLayer, "setSpeed:", 999.0);
            }
            if (distFont) {
                ds_perform_on_springboard_main(self.remoteCall, distLbl, ds_remote_sel(self.remoteCall, "setFont:"), distFont, YES);
            }
            ds_perform_on_springboard_main(self.remoteCall, parentView, addSubSEL, distLbl, YES);
            slot->distLabel = distLbl;
        }

        // 5. Hero Name label (exact internal style: Hero Name in White, bold 14px, centered below distance)
        uint64_t nameLbl = remote_msg(self.remoteCall, labelClass, allocSEL, 0, 0, 0, 0);
        if (nameLbl && ds_remote_invoke_noarg_on_main(self.remoteCall, nameLbl, "init")) {
            ds_perform_on_springboard_main(self.remoteCall, nameLbl, ds_remote_sel(self.remoteCall, "setBackgroundColor:"), clearColor, YES);
            ds_perform_on_springboard_main(self.remoteCall, nameLbl, ds_remote_sel(self.remoteCall, "setTextColor:"), whiteColor, YES);
            ds_remote_set_u64_on_main(self.remoteCall, nameLbl, "setTextAlignment:", (uint64_t)NSTextAlignmentCenter);
            ds_remote_set_u64_on_main(self.remoteCall, nameLbl, "setUserInteractionEnabled:", 0);
            ds_remote_set_u64_on_main(self.remoteCall, nameLbl, "setHidden:", 1);

            uint64_t nLayer = ds_remote_get_object_on_main(self.remoteCall, nameLbl, "layer");
            if (nLayer) {
                ds_remote_set_double_on_main(self.remoteCall, nLayer, "setSpeed:", 999.0);
            }
            if (nameFont) {
                ds_perform_on_springboard_main(self.remoteCall, nameLbl, ds_remote_sel(self.remoteCall, "setFont:"), nameFont, YES);
            }
            ds_perform_on_springboard_main(self.remoteCall, parentView, addSubSEL, nameLbl, YES);
            slot->nameLabel = nameLbl;
        }

        // 6. Snapline view (exact internal style: white 0.70 alpha, width 1.2)
        uint64_t line = remote_msg(self.remoteCall, viewClass, allocSEL, 0, 0, 0, 0);
        if (line && ds_remote_invoke_noarg_on_main(self.remoteCall, line, "init")) {
            ds_perform_on_springboard_main(self.remoteCall, line, ds_remote_sel(self.remoteCall, "setBackgroundColor:"), whiteColor, YES);
            ds_remote_set_double_on_main(self.remoteCall, line, "setAlpha:", 0.70);
            ds_remote_set_u64_on_main(self.remoteCall, line, "setUserInteractionEnabled:", 0);
            ds_remote_set_u64_on_main(self.remoteCall, line, "setHidden:", 1);
            uint64_t lineLayer = ds_remote_get_object_on_main(self.remoteCall, line, "layer");
            if (lineLayer) {
                ds_remote_set_double_on_main(self.remoteCall, lineLayer, "setSpeed:", 999.0);
            }
            ds_perform_on_springboard_main(self.remoteCall, parentView, addSubSEL, line, YES);
            slot->lineView = line;
        }

        // 7. Snapline tip Green Dot view (exact internal style: green circle radius 3.0 at line end)
        uint64_t dot = remote_msg(self.remoteCall, viewClass, allocSEL, 0, 0, 0, 0);
        if (dot && ds_remote_invoke_noarg_on_main(self.remoteCall, dot, "init")) {
            ds_perform_on_springboard_main(self.remoteCall, dot, ds_remote_sel(self.remoteCall, "setBackgroundColor:"), greenColor, YES);
            ds_remote_set_u64_on_main(self.remoteCall, dot, "setUserInteractionEnabled:", 0);
            ds_remote_set_u64_on_main(self.remoteCall, dot, "setHidden:", 1);
            uint64_t dotLayer = ds_remote_get_object_on_main(self.remoteCall, dot, "layer");
            if (dotLayer) {
                ds_remote_set_double_on_main(self.remoteCall, dotLayer, "setCornerRadius:", 3.0);
                ds_remote_set_u64_on_main(self.remoteCall, dotLayer, "setMasksToBounds:", 1);
                ds_remote_set_double_on_main(self.remoteCall, dotLayer, "setSpeed:", 999.0);
            }
            ds_remote_set_rect_on_main(self.remoteCall, dot, "setBounds:", CGRectMake(0, 0, 6.0, 6.0));
            ds_perform_on_springboard_main(self.remoteCall, parentView, addSubSEL, dot, YES);
            slot->lineDotView = dot;
        }
    }
}

- (BOOL)setupSpringBoardOverlayWindow {
    LOG(@"[RemoteWebViewOverlay] Setting up SpringBoard overlay window (DarkSpeed style with %lu-slot ESP)...",
        (unsigned long)kMaxOverlaySlots);

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

    if (!window) {
        LOG(@"[RemoteWebViewOverlay] Failed to alloc SpringBoard window");
        return NO;
    }

    if (!ds_remote_invoke_noarg_on_main(self.remoteCall, window, "init")) {
        LOG(@"[RemoteWebViewOverlay] Failed to init SpringBoard window on main thread");
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

    uint64_t winLayer = ds_remote_get_object_on_main(self.remoteCall, window, "layer");
    if (winLayer) {
        ds_remote_set_double_on_main(self.remoteCall, winLayer, "setSpeed:", 999.0);
    }

    uint64_t clearColor = ds_remote_get_retained_object_on_main(self.remoteCall, colorClass, "clearColor");
    uint64_t whiteColor = ds_remote_get_retained_object_on_main(self.remoteCall, colorClass, "whiteColor");
    uint64_t redColor = ds_remote_get_retained_object_on_main(self.remoteCall, colorClass, "redColor");
    uint64_t greenColor = ds_remote_get_retained_object_on_main(self.remoteCall, colorClass, "greenColor");
    uint64_t yellowColor = ds_remote_get_retained_object_on_main(self.remoteCall, colorClass, "yellowColor");
    uint64_t blackColor = ds_remote_get_retained_object_on_main(self.remoteCall, colorClass, "blackColor");
    uint64_t whiteCGColor = whiteColor ? ds_remote_get_object_on_main(self.remoteCall, whiteColor, "CGColor") : 0;

    s_sbRedColor = redColor;
    s_sbYellowColor = yellowColor;
    s_sbGreenColor = greenColor;

    if (clearColor) {
        ds_perform_on_springboard_main(self.remoteCall, window, ds_remote_sel(self.remoteCall, "setBackgroundColor:"), clearColor, YES);
    }

    uint64_t fontClass = ds_remote_class(self.remoteCall, "UIFont");
    uint64_t distFont = 0;
    uint64_t nameFont = 0;
    if (fontClass) {
        double fontSize11 = 11.0;
        DSRemoteArg fontArg11 = { &fontSize11, sizeof(fontSize11) };
        ds_remote_invoke_on_main_result(self.remoteCall, fontClass, ds_remote_sel(self.remoteCall, "boldSystemFontOfSize:"), &fontArg11, 1, &distFont, sizeof(distFont), YES);

        double fontSize14 = 14.0;
        DSRemoteArg fontArg14 = { &fontSize14, sizeof(fontSize14) };
        ds_remote_invoke_on_main_result(self.remoteCall, fontClass, ds_remote_sel(self.remoteCall, "boldSystemFontOfSize:"), &fontArg14, 1, &nameFont, sizeof(nameFont), YES);
    }

    [self setupESPSlotsOnParentView:window
                         viewClass:viewClass
                        labelClass:labelClass
                          allocSEL:allocSEL
                        clearColor:clearColor
                        whiteColor:whiteColor
                        greenColor:greenColor
                       yellowColor:yellowColor
                        blackColor:blackColor
                      whiteCGColor:whiteCGColor
                          distFont:distFont
                          nameFont:nameFont];

    ds_remote_set_u64_on_main(self.remoteCall, window, "setHidden:", 0);

    self.window = window;
    self.parentView = window;
    self.isOverlayReady = YES;
    s_sbOverlayReadyAt = CFAbsoluteTimeGetCurrent();

    LOG(@"[RemoteWebViewOverlay] SpringBoard overlay window ready with %lu ESP slots (window=0x%llx)",
        (unsigned long)kMaxOverlaySlots, window);
    return YES;
}

- (BOOL)setupInternalOverlayWindow {
    LOG(@"[RemoteWebViewOverlay] Setting up Internal overlay window (Pure UIKit %lu-slot ESP)...",
        (unsigned long)kMaxOverlaySlots);

    uint64_t windowClass = ds_remote_class(self.remoteCall, "UIWindow");
    uint64_t viewClass = ds_remote_class(self.remoteCall, "UIView");
    uint64_t labelClass = ds_remote_class(self.remoteCall, "UILabel");
    uint64_t colorClass = ds_remote_class(self.remoteCall, "UIColor");

    if (!windowClass || !viewClass || !labelClass || !colorClass) {
        LOG(@"[RemoteWebViewOverlay] Required UIKit classes not found for internal overlay");
        return NO;
    }

    // 1. Resolve active game window and windowScene
    uint64_t gameWindow = 0;
    if ([self findTargetWindow]) {
        gameWindow = self.window;
    }

    uint64_t scene = 0;
    if (gameWindow) {
        scene = ds_remote_get_object_on_main(self.remoteCall, gameWindow, "windowScene");
    }

    if (!scene) {
        uint64_t uiAppClass = ds_remote_class(self.remoteCall, "UIApplication");
        if (uiAppClass) {
            uint64_t app = ds_remote_get_object_on_main(self.remoteCall, uiAppClass, "sharedApplication");
            if (app) {
                uint64_t connectedScenes = ds_remote_get_object_on_main(self.remoteCall, app, "connectedScenes");
                if (connectedScenes) {
                    uint64_t scenes = ds_remote_get_object_on_main(self.remoteCall, connectedScenes, "allObjects");
                    if (scenes) {
                        uint64_t sceneCount = ds_remote_get_u64_on_main(self.remoteCall, scenes, "count");
                        if (sceneCount > 0) {
                            scene = remote_msg(self.remoteCall, scenes, ds_remote_sel(self.remoteCall, "objectAtIndex:"), 0, 0, 0, 0);
                        }
                    }
                }
            }
        }
    }
    LOG(@"[RemoteWebViewOverlay] Internal UIWindowScene = 0x%llx (gameWindow=0x%llx)", scene, gameWindow);

    // 2. Resolve screen bounds
    CGFloat screenW = MAX(kWidth, kHeight);
    CGFloat screenH = MIN(kWidth, kHeight);
    if (gameWindow) {
        uint64_t boundsSEL = ds_remote_sel(self.remoteCall, "bounds");
        if (boundsSEL) {
            CGRect gameBounds = remote_getCGRect(self.remoteCall, gameWindow, boundsSEL);
            if (gameBounds.size.width > 0.0 && gameBounds.size.height > 0.0) {
                screenW = MAX(gameBounds.size.width, gameBounds.size.height);
                screenH = MIN(gameBounds.size.width, gameBounds.size.height);
            }
        }
    }
    self.cachedScreenWidth = screenW;
    self.cachedScreenHeight = screenH;
    LOG(@"[RemoteWebViewOverlay] Internal screen bounds: %.0fx%.0f", screenW, screenH);

    // 3. Resolve Colors
    uint64_t clearColor = ds_remote_get_retained_object_on_main(self.remoteCall, colorClass, "clearColor");
    uint64_t whiteColor = ds_remote_get_retained_object_on_main(self.remoteCall, colorClass, "whiteColor");
    uint64_t redColor = ds_remote_get_retained_object_on_main(self.remoteCall, colorClass, "redColor");
    uint64_t greenColor = ds_remote_get_retained_object_on_main(self.remoteCall, colorClass, "greenColor");
    uint64_t yellowColor = ds_remote_get_retained_object_on_main(self.remoteCall, colorClass, "yellowColor");
    uint64_t blackColor = ds_remote_get_retained_object_on_main(self.remoteCall, colorClass, "blackColor");
    uint64_t whiteCGColor = whiteColor ? ds_remote_get_object_on_main(self.remoteCall, whiteColor, "CGColor") : 0;

    s_sbRedColor = redColor;
    s_sbYellowColor = yellowColor;
    s_sbGreenColor = greenColor;

    // 4. Resolve Fonts (11pt Bold for distance, 14pt Bold for name)
    uint64_t fontClass = ds_remote_class(self.remoteCall, "UIFont");
    uint64_t distFont = 0;
    uint64_t nameFont = 0;
    if (fontClass) {
        double fontSize11 = 11.0;
        DSRemoteArg fontArg11 = { &fontSize11, sizeof(fontSize11) };
        ds_remote_invoke_on_main_result(self.remoteCall, fontClass, ds_remote_sel(self.remoteCall, "boldSystemFontOfSize:"), &fontArg11, 1, &distFont, sizeof(distFont), YES);

        double fontSize14 = 14.0;
        DSRemoteArg fontArg14 = { &fontSize14, sizeof(fontSize14) };
        ds_remote_invoke_on_main_result(self.remoteCall, fontClass, ds_remote_sel(self.remoteCall, "boldSystemFontOfSize:"), &fontArg14, 1, &nameFont, sizeof(nameFont), YES);
    }

    // 5. Create dedicated overlay UIWindow (with windowLevel = 10000010.0, userInteractionEnabled = 0)
    uint64_t allocSEL = ds_remote_sel(self.remoteCall, "alloc");
    uint64_t overlayWindow = remote_msg(self.remoteCall, windowClass, allocSEL, 0, 0, 0, 0);
    uint64_t parentView = 0;

    if (overlayWindow && ds_remote_invoke_noarg_on_main(self.remoteCall, overlayWindow, "init")) {
        CGRect fullFrame = CGRectMake(0, 0, screenW, screenH);
        ds_remote_set_rect_on_main(self.remoteCall, overlayWindow, "setFrame:", fullFrame);
        if (scene) {
            ds_perform_on_springboard_main(self.remoteCall, overlayWindow, ds_remote_sel(self.remoteCall, "setWindowScene:"), scene, YES);
        }
        ds_remote_set_double_on_main(self.remoteCall, overlayWindow, "setWindowLevel:", 10000010.0);
        ds_remote_set_u64_on_main(self.remoteCall, overlayWindow, "setUserInteractionEnabled:", 0);
        ds_remote_set_u64_on_main(self.remoteCall, overlayWindow, "setOpaque:", 0);

        uint64_t winLayer = ds_remote_get_object_on_main(self.remoteCall, overlayWindow, "layer");
        if (winLayer) {
            ds_remote_set_double_on_main(self.remoteCall, winLayer, "setSpeed:", 999.0);
        }
        if (clearColor) {
            ds_perform_on_springboard_main(self.remoteCall, overlayWindow, ds_remote_sel(self.remoteCall, "setBackgroundColor:"), clearColor, YES);
        }

        // Set transparent UIViewController as rootViewController for proper landscape rotation handling
        uint64_t vcClass = ds_remote_class(self.remoteCall, "UIViewController");
        if (vcClass) {
            uint64_t vc = remote_msg(self.remoteCall, vcClass, allocSEL, 0, 0, 0, 0);
            if (vc && ds_remote_invoke_noarg_on_main(self.remoteCall, vc, "init")) {
                uint64_t vcView = ds_remote_get_object_on_main(self.remoteCall, vc, "view");
                if (vcView) {
                    ds_remote_set_u64_on_main(self.remoteCall, vcView, "setUserInteractionEnabled:", 0);
                    ds_remote_set_u64_on_main(self.remoteCall, vcView, "setOpaque:", 0);
                    if (clearColor) {
                        ds_perform_on_springboard_main(self.remoteCall, vcView, ds_remote_sel(self.remoteCall, "setBackgroundColor:"), clearColor, YES);
                    }
                }
                ds_perform_on_springboard_main(self.remoteCall, overlayWindow, ds_remote_sel(self.remoteCall, "setRootViewController:"), vc, YES);
            }
        }

        ds_remote_set_u64_on_main(self.remoteCall, overlayWindow, "setHidden:", 0);
        self.window = overlayWindow;
        parentView = overlayWindow;
        LOG(@"[RemoteWebViewOverlay] Internal overlay window created = 0x%llx", overlayWindow);
    } else {
        // Fallback: attach slots to gameWindow
        if (!gameWindow) {
            LOG(@"[RemoteWebViewOverlay] Failed to create overlay window and no gameWindow found");
            return NO;
        }
        self.window = gameWindow;
        parentView = gameWindow;
        LOG(@"[RemoteWebViewOverlay] Internal fallback to game window = 0x%llx", gameWindow);
    }

    self.parentView = parentView;

    // 6. Setup ESP slots on parentView
    [self setupESPSlotsOnParentView:parentView
                         viewClass:viewClass
                        labelClass:labelClass
                          allocSEL:allocSEL
                        clearColor:clearColor
                        whiteColor:whiteColor
                        greenColor:greenColor
                       yellowColor:yellowColor
                        blackColor:blackColor
                      whiteCGColor:whiteCGColor
                          distFont:distFont
                          nameFont:nameFont];

    self.isOverlayReady = YES;
    s_sbOverlayReadyAt = CFAbsoluteTimeGetCurrent();

    LOG(@"[RemoteWebViewOverlay] Internal overlay window ready with %lu ESP slots (window=0x%llx, parentView=0x%llx)",
        (unsigned long)kMaxOverlaySlots, self.window, self.parentView);
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
    if (self.isOverlayReady && self.window) {
        return YES;
    }

    LOG(@"[RemoteWebViewOverlay] Setting up base overlay (%s)...",
        self.isSpringBoard ? "SpringBoard" : "Internal");

    [[OverlayWebSocketServer sharedServer] start];

    if (self.isSpringBoard) {
        if (![self setupSpringBoardOverlayWindow]) {
            LOG(@"[RemoteWebViewOverlay] setupSpringBoardOverlayWindow failed");
            return NO;
        }
    } else {
        if (![self setupInternalOverlayWindow]) {
            LOG(@"[RemoteWebViewOverlay] setupInternalOverlayWindow failed");
            return NO;
        }
    }

    self.isOverlayReady = YES;
    [self broadcastOverlayLayout];
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

    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (s_sbOverlayReadyAt > 0 && now - s_sbOverlayReadyAt < 0.5) {
        return YES; // Settle delay: give overlay 0.5s to attach window scene before frame updates
    }

    static CFAbsoluteTime lastESPUpdate = 0;
    if (now - lastESPUpdate < 0.016) { // 60 FPS cap to eliminate main-thread watchdog respring
        return YES;
    }
    lastESPUpdate = now;

    CGFloat sw = self.cachedScreenWidth > 0 ? self.cachedScreenWidth : MAX(kWidth, kHeight);
    CGPoint startPoint = CGPointMake(sw * 0.5, 38.0); // Exact internal style: top-center below notch (x=mid, y=38)

    NSUInteger targetCount = targets.count;
    for (NSUInteger i = 0; i < kMaxOverlaySlots; i++) {
        SpringBoardESPSlot *slot = &_espSlots[i];
        if (i < targetCount) {
            NSDictionary *target = targets[i];
            BOOL onScreen = [target[@"onScreen"] boolValue];
            BOOL visible = [target[@"visible"] boolValue];
            CGFloat sx = [target[@"sx"] doubleValue];
            CGFloat sy = [target[@"sy"] doubleValue];
            CGFloat hx = [target[@"headX"] doubleValue];
            CGFloat hy = [target[@"headY"] doubleValue];

            if (visible && onScreen) {
                // 1. Box (exact internal style: white 0.70 alpha, width 1.25)
                BOOL hasBox = [target[@"hasBox"] boolValue];
                CGFloat bx = [target[@"boxX"] doubleValue];
                CGFloat by = [target[@"boxY"] doubleValue];
                CGFloat bw = [target[@"boxW"] doubleValue];
                CGFloat bh = [target[@"boxH"] doubleValue];

                if (hasBox && bw > 5.0 && bh > 5.0 && slot->boxView) {
                    CGRect newBox = CGRectMake(bx, by, bw, bh);
                    if (!slot->isBoxVisible) {
                        ds_remote_set_u64_on_main(self.remoteCall, slot->boxView, "setHidden:", 0);
                        slot->isBoxVisible = YES;
                    }
                    if (IsFrameSignificantlyDifferent(slot->lastBoxFrame, newBox)) {
                        ds_remote_set_rect_on_main(self.remoteCall, slot->boxView, "setFrame:", newBox);
                        slot->lastBoxFrame = newBox;
                    }
                } else if (slot->isBoxVisible && slot->boxView) {
                    ds_remote_set_u64_on_main(self.remoteCall, slot->boxView, "setHidden:", 1);
                    slot->isBoxVisible = NO;
                }

                // 2. Health Bar (exact internal style: barY = box.y - 7, height 5, fill height 4, dynamic colors)
                BOOL drawHealth = [target[@"drawHealth"] boolValue];
                int hp = [target[@"hp"] intValue];
                int maxHp = MAX([target[@"maxHp"] intValue], 1);
                if (drawHealth && hasBox && bw > 5.0 && slot->hpBgView && slot->hpFillView) {
                    CGFloat hpRatio = OverlayClamp((CGFloat)hp / (CGFloat)maxHp, 0.0, 1.0);
                    CGRect newHpBg = CGRectMake(bx - 0.5, by - 7.0, bw + 1.0, 5.0);
                    CGRect newHpFill = CGRectMake(0, 0.5, bw * hpRatio, 4.0);

                    if (!slot->isHpVisible) {
                        ds_remote_set_u64_on_main(self.remoteCall, slot->hpBgView, "setHidden:", 0);
                        slot->isHpVisible = YES;
                    }
                    if (IsFrameSignificantlyDifferent(slot->lastHpBgFrame, newHpBg)) {
                        ds_remote_set_rect_on_main(self.remoteCall, slot->hpBgView, "setFrame:", newHpBg);
                        slot->lastHpBgFrame = newHpBg;
                    }
                    if (IsFrameSignificantlyDifferent(slot->lastHpFillFrame, newHpFill)) {
                        ds_remote_set_rect_on_main(self.remoteCall, slot->hpFillView, "setFrame:", newHpFill);
                        slot->lastHpFillFrame = newHpFill;
                    }

                    // Dynamic Health Color (< 30%: Red, <= 60%: Yellow, > 60%: Green)
                    int colorState = (hpRatio < 0.3) ? 1 : ((hpRatio <= 0.6) ? 2 : 3);
                    if (colorState != slot->lastHpColorState) {
                        uint64_t targetColor = (colorState == 1) ? s_sbRedColor : ((colorState == 2) ? s_sbYellowColor : s_sbGreenColor);
                        if (targetColor) {
                            ds_perform_on_springboard_main(self.remoteCall, slot->hpFillView, ds_remote_sel(self.remoteCall, "setBackgroundColor:"), targetColor, YES);
                        }
                        slot->lastHpColorState = colorState;
                    }
                } else if (slot->isHpVisible && slot->hpBgView) {
                    ds_remote_set_u64_on_main(self.remoteCall, slot->hpBgView, "setHidden:", 1);
                    slot->isHpVisible = NO;
                }

                // 3. Distance Label (exact internal style: [ 15m ] in Yellow, below hero feet)
                BOOL drawDist = [target[@"drawDistance"] boolValue];
                int dist = [target[@"distance"] intValue];
                CGFloat footY = hasBox ? (by + bh) : sy;
                if (drawDist && slot->distLabel) {
                    CGFloat distW = 80.0;
                    CGRect newDistFrame = CGRectMake(sx - distW * 0.5, footY + 4.0, distW, 14.0);
                    if (!slot->isDistVisible) {
                        ds_remote_set_u64_on_main(self.remoteCall, slot->distLabel, "setHidden:", 0);
                        slot->isDistVisible = YES;
                    }
                    if (IsFrameSignificantlyDifferent(slot->lastDistFrame, newDistFrame)) {
                        ds_remote_set_rect_on_main(self.remoteCall, slot->distLabel, "setFrame:", newDistFrame);
                        slot->lastDistFrame = newDistFrame;
                    }
                    if ((dist != slot->lastDistance && (now - slot->lastDistUpdate >= 0.35)) || slot->lastDistUpdate == 0) {
                        slot->lastDistance = dist;
                        slot->lastDistUpdate = now;
                        NSString *distText = [NSString stringWithFormat:@"[ %dm ]", dist];
                        ds_remote_set_text_on_main(self.remoteCall, slot->distLabel, distText);
                    }
                } else if (slot->isDistVisible && slot->distLabel) {
                    ds_remote_set_u64_on_main(self.remoteCall, slot->distLabel, "setHidden:", 1);
                    slot->isDistVisible = NO;
                }

                // 4. Hero Name Label (exact internal style: White bold text below distance)
                BOOL drawName = [target[@"drawName"] boolValue];
                NSString *name = target[@"name"] ?: @"";
                if (drawName && name.length > 0 && slot->nameLabel) {
                    CGFloat nameW = 120.0;
                    CGFloat nameY = drawDist ? (footY + 18.0) : (footY + 6.0);
                    CGRect newNameFrame = CGRectMake(sx - nameW * 0.5, nameY, nameW, 17.0);
                    if (!slot->isNameVisible) {
                        ds_remote_set_u64_on_main(self.remoteCall, slot->nameLabel, "setHidden:", 0);
                        slot->isNameVisible = YES;
                    }
                    if (IsFrameSignificantlyDifferent(slot->lastNameFrame, newNameFrame)) {
                        ds_remote_set_rect_on_main(self.remoteCall, slot->nameLabel, "setFrame:", newNameFrame);
                        slot->lastNameFrame = newNameFrame;
                    }
                    if (strncmp(slot->lastNameBuf, name.UTF8String, sizeof(slot->lastNameBuf)) != 0) {
                        strncpy(slot->lastNameBuf, name.UTF8String, sizeof(slot->lastNameBuf) - 1);
                        slot->lastNameBuf[sizeof(slot->lastNameBuf) - 1] = '\0';
                        ds_remote_set_text_on_main(self.remoteCall, slot->nameLabel, name);
                    }
                } else if (slot->isNameVisible && slot->nameLabel) {
                    ds_remote_set_u64_on_main(self.remoteCall, slot->nameLabel, "setHidden:", 1);
                    slot->isNameVisible = NO;
                }

                // 5. Snapline (exact internal style: white 0.70 alpha, width 1.2 from (sw/2, 38) straight to top-center of box / head)
                BOOL drawLine = [target[@"drawLine"] boolValue];
                CGFloat topCenterX = hasBox ? (bx + bw * 0.5) : (hx > 0.0 ? hx : sx);
                CGFloat topCenterY = (hasBox && by > 0.0) ? (by - 6.0) : (hy > 0.0 ? hy : (sy - 15.0));
                CGPoint endPoint = CGPointMake(topCenterX, topCenterY);

                CGFloat dx = endPoint.x - startPoint.x;
                CGFloat dy = endPoint.y - startPoint.y;
                CGFloat lineLen = hypot(dx, dy);

                if (drawLine && lineLen > 5.0 && isfinite(lineLen) && slot->lineView) {
                    CGFloat angle = atan2(dy, dx);
                    CGPoint midPoint = CGPointMake((startPoint.x + endPoint.x) * 0.5,
                                                   (startPoint.y + endPoint.y) * 0.5);

                    if (!slot->isLineVisible) {
                        ds_remote_set_u64_on_main(self.remoteCall, slot->lineView, "setHidden:", 0);
                        slot->isLineVisible = YES;
                    }
                    if (IsLineSignificantlyDifferent(slot->lastLineLength, lineLen,
                                                     slot->lastLineAngle, angle,
                                                     slot->lastLineCenter, midPoint)) {
                        ds_remote_set_rect_on_main(self.remoteCall, slot->lineView, "setBounds:",
                                                   CGRectMake(0, 0, lineLen, 1.2));
                        ds_remote_set_point_on_main(self.remoteCall, slot->lineView, "setCenter:", midPoint);
                        ds_remote_set_transform_on_main(self.remoteCall, slot->lineView, "setTransform:",
                                                        CGAffineTransformMakeRotation(angle));
                        slot->lastLineLength = lineLen;
                        slot->lastLineAngle = angle;
                        slot->lastLineCenter = midPoint;
                    }

                    // 6. Snapline tip Green Dot (exact internal style: arc in green at endPoint)
                    if (slot->lineDotView) {
                        if (!slot->isDotVisible) {
                            ds_remote_set_u64_on_main(self.remoteCall, slot->lineDotView, "setHidden:", 0);
                            slot->isDotVisible = YES;
                        }
                        if (fabs(slot->lastDotCenter.x - endPoint.x) > 0.05 || fabs(slot->lastDotCenter.y - endPoint.y) > 0.05) {
                            ds_remote_set_point_on_main(self.remoteCall, slot->lineDotView, "setCenter:", endPoint);
                            slot->lastDotCenter = endPoint;
                        }
                    }
                } else {
                    if (slot->isLineVisible && slot->lineView) {
                        ds_remote_set_u64_on_main(self.remoteCall, slot->lineView, "setHidden:", 1);
                        slot->isLineVisible = NO;
                        slot->lastLineLength = 0;
                        slot->lastLineAngle = 0;
                        slot->lastLineCenter = CGPointZero;
                    }
                    if (slot->isDotVisible && slot->lineDotView) {
                        ds_remote_set_u64_on_main(self.remoteCall, slot->lineDotView, "setHidden:", 1);
                        slot->isDotVisible = NO;
                        slot->lastDotCenter = CGPointZero;
                    }
                }
                continue;
            }
        }

        // Target not on screen or slot index >= targetCount -> Hide all
        if (slot->isBoxVisible && slot->boxView) {
            ds_remote_set_u64_on_main(self.remoteCall, slot->boxView, "setHidden:", 1);
            slot->isBoxVisible = NO;
            slot->lastBoxFrame = CGRectZero;
        }
        if (slot->isHpVisible && slot->hpBgView) {
            ds_remote_set_u64_on_main(self.remoteCall, slot->hpBgView, "setHidden:", 1);
            slot->isHpVisible = NO;
            slot->lastHpBgFrame = CGRectZero;
            slot->lastHpFillFrame = CGRectZero;
            slot->lastHpColorState = 0;
        }
        if (slot->isDistVisible && slot->distLabel) {
            ds_remote_set_u64_on_main(self.remoteCall, slot->distLabel, "setHidden:", 1);
            slot->isDistVisible = NO;
            slot->lastDistFrame = CGRectZero;
            slot->lastDistance = -1;
            slot->lastDistUpdate = 0;
        }
        if (slot->isNameVisible && slot->nameLabel) {
            ds_remote_set_u64_on_main(self.remoteCall, slot->nameLabel, "setHidden:", 1);
            slot->isNameVisible = NO;
            slot->lastNameFrame = CGRectZero;
            slot->lastNameBuf[0] = '\0';
        }
        if (slot->isLineVisible && slot->lineView) {
            ds_remote_set_u64_on_main(self.remoteCall, slot->lineView, "setHidden:", 1);
            slot->isLineVisible = NO;
            slot->lastLineLength = 0;
            slot->lastLineAngle = 0;
            slot->lastLineCenter = CGPointZero;
        }
        if (slot->isDotVisible && slot->lineDotView) {
            ds_remote_set_u64_on_main(self.remoteCall, slot->lineDotView, "setHidden:", 1);
            slot->isDotVisible = NO;
            slot->lastDotCenter = CGPointZero;
        }
    }

    if ([OverlayWebSocketServer sharedServer].clientCount > 0) {
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
        if (jsonData.length > 0) {
            [[OverlayWebSocketServer sharedServer] broadcastTargetsData:jsonData];
        }
    }

    return YES;
}

#pragma mark - Clear targets

- (BOOL)clearTargets {
    if (!self.isOverlayReady)
        return NO;

    for (NSUInteger i = 0; i < kMaxOverlaySlots; i++) {
        SpringBoardESPSlot *slot = &_espSlots[i];
        if (slot->isBoxVisible && slot->boxView) {
            ds_remote_set_u64_on_main(self.remoteCall, slot->boxView, "setHidden:", 1);
            slot->isBoxVisible = NO;
        }
        if (slot->isHpVisible && slot->hpBgView) {
            ds_remote_set_u64_on_main(self.remoteCall, slot->hpBgView, "setHidden:", 1);
            slot->isHpVisible = NO;
        }
        if (slot->isDistVisible && slot->distLabel) {
            ds_remote_set_u64_on_main(self.remoteCall, slot->distLabel, "setHidden:", 1);
            slot->isDistVisible = NO;
        }
        if (slot->isNameVisible && slot->nameLabel) {
            ds_remote_set_u64_on_main(self.remoteCall, slot->nameLabel, "setHidden:", 1);
            slot->isNameVisible = NO;
        }
        if (slot->isLineVisible && slot->lineView) {
            ds_remote_set_u64_on_main(self.remoteCall, slot->lineView, "setHidden:", 1);
            slot->isLineVisible = NO;
        }
        if (slot->isDotVisible && slot->lineDotView) {
            ds_remote_set_u64_on_main(self.remoteCall, slot->lineDotView, "setHidden:", 1);
            slot->isDotVisible = NO;
        }
        slot->lastBoxFrame = CGRectZero;
        slot->lastHpBgFrame = CGRectZero;
        slot->lastHpFillFrame = CGRectZero;
        slot->lastDistFrame = CGRectZero;
        slot->lastNameFrame = CGRectZero;
        slot->lastDotCenter = CGPointZero;
        slot->lastLineLength = 0;
        slot->lastLineAngle = 0;
        slot->lastLineCenter = CGPointZero;
        slot->lastNameBuf[0] = '\0';
        slot->lastDistance = -1;
        slot->lastDistUpdate = 0;
        slot->lastHpColorState = 0;
    }

    if ([OverlayWebSocketServer sharedServer].clientCount > 0) {
        NSData *emptyPayload = [@"{\"type\":\"targets\",\"targets\":[]}" dataUsingEncoding:NSUTF8StringEncoding];
        [[OverlayWebSocketServer sharedServer] broadcastTargetsData:emptyPayload];
    }
    LOG(@"[RemoteWebViewOverlay] Targets cleared");
    return YES;
}

#pragma mark - Teardown

- (void)teardownOverlay {
    if (!self.isOverlayReady || !self.remoteCall)
        return;

    LOG(@"[RemoteWebViewOverlay] Tearing down overlay (%s)...",
        self.isSpringBoard ? "SpringBoard" : "Internal");

    ds_inv_cache_clear(self.remoteCall);
    s_sbOverlayReadyAt = 0;
    uint64_t removeSEL = ds_remote_sel(self.remoteCall, "removeFromSuperview");
    if (removeSEL) {
        for (NSUInteger i = 0; i < kMaxOverlaySlots; i++) {
            SpringBoardESPSlot *slot = &_espSlots[i];
            if (slot->boxView) ds_perform_on_springboard_main(self.remoteCall, slot->boxView, removeSEL, 0, YES);
            if (slot->hpBgView) ds_perform_on_springboard_main(self.remoteCall, slot->hpBgView, removeSEL, 0, YES);
            if (slot->distLabel) ds_perform_on_springboard_main(self.remoteCall, slot->distLabel, removeSEL, 0, YES);
            if (slot->nameLabel) ds_perform_on_springboard_main(self.remoteCall, slot->nameLabel, removeSEL, 0, YES);
            if (slot->lineView) ds_perform_on_springboard_main(self.remoteCall, slot->lineView, removeSEL, 0, YES);
            if (slot->lineDotView) ds_perform_on_springboard_main(self.remoteCall, slot->lineDotView, removeSEL, 0, YES);
            memset(slot, 0, sizeof(SpringBoardESPSlot));
        }
    }
    s_sbRedColor = 0;
    s_sbYellowColor = 0;
    s_sbGreenColor = 0;

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
        ds_remote_set_u64_on_main(self.remoteCall, self.window, "setHidden:", 1);
        self.window = 0;
        self.parentView = 0;
    }

    self.isOverlayReady = NO;
    self.menuVisible = NO;
}

@end
