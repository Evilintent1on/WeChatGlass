// WeChatGlass v0.2 - Liquid Glass for WeChat (needs Xcode 26 SDK to build, iOS 26+ to run)
// Based on class-dump headers: MMInputToolView, MMGrowTextView, MMUIButton, MMTabBar, MMUINavigationBar.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// Base glass style: 0 = Regular, 1 = Clear (more transparent; better on plain backgrounds)
#define WC_GLASS_CLEAR 1

#pragma mark - Minimal declarations (the dumped headers don't compile as-is)

@interface MMUIButton : UIButton @end
@interface MMGrowTextView : UIView @end

@interface MMInputToolView : UIView
@property (nonatomic, strong) UIView *toolView;
@property (nonatomic, strong) MMGrowTextView *textView;
@property (nonatomic, strong) MMUIButton *attachmentButton;
@property (nonatomic, strong) MMUIButton *expressionButton;
@property (nonatomic, strong) MMUIButton *inputModeChangeButton;
@end

@interface MMTabBar : UITabBar
@property (nonatomic, strong) UIView *backgroundView;
- (id)findBlurEffectView:(id)view;
- (id)findShadowView:(id)view;
- (void)configureClearBackground;
- (long long)tabBarItemCount;
- (BOOL)targetIndexIsSelected:(long long)index;
- (UIView *)tabBarItemViewAtIndex:(long long)index;
- (void)wc_updateLensAnimated:(BOOL)animated;   // added by us (%new)
@end

@interface MMUINavigationBar : UINavigationBar
@property (nonatomic, strong) UIView *effectSubview;
@end

#pragma mark - Glass view

static const NSInteger kWCGlassTag = 0x474C;
static const NSInteger kWCLensTag  = 0x4C4E;

@interface WCGlassView : UIVisualEffectView
@property (nonatomic) BOOL capsule;
@property (nonatomic) CGFloat fixedRadius;
@end

@implementation WCGlassView
- (void)layoutSubviews {
    [super layoutSubviews];
    // Prefer iOS 26 corner configuration: rounds the glass WITHOUT clipping
    // (clipping flattens highlights/refraction into a plain fill).
    if (self.capsule) {
        Class cfg = NSClassFromString(@"UICornerConfiguration");
        SEL capsuleSel = NSSelectorFromString(@"capsuleConfiguration");
        SEL setSel = NSSelectorFromString(@"setCornerConfiguration:");
        if (cfg && [cfg respondsToSelector:capsuleSel] && [self respondsToSelector:setSel]) {
            id c = ((id (*)(Class, SEL))objc_msgSend)(cfg, capsuleSel);
            ((void (*)(id, SEL, id))objc_msgSend)(self, setSel, c);
            return;
        }
    }
    CGFloat r = self.capsule ? MIN(self.bounds.size.width, self.bounds.size.height) / 2.0
                             : self.fixedRadius;
    self.layer.cornerRadius = r;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.clipsToBounds = YES;   // fallback only
}
@end

static BOOL WCGlassAvailable(void) {
    if (@available(iOS 26.0, *)) return YES;
    return NO;
}

static WCGlassView *WCFindGlass(UIView *host, NSInteger tag) {
    for (UIView *v in host.subviews) {
        if (v.tag == tag && [v isKindOfClass:WCGlassView.class]) return (WCGlassView *)v;
    }
    return nil;
}

static WCGlassView *WCMakeGlass(UIView *host, NSInteger tag, BOOL regular, CGFloat radius, UIColor *tint, NSInteger index) {
    WCGlassView *g = WCFindGlass(host, tag);
    if (g) return g;
    if (@available(iOS 26.0, *)) {
        UIGlassEffectStyle style = (regular || !WC_GLASS_CLEAR) ? UIGlassEffectStyleRegular
                                                                : UIGlassEffectStyleClear;
        UIGlassEffect *e = [UIGlassEffect effectWithStyle:style];
        e.tintColor = tint;
        e.interactive = YES;
        g = [[WCGlassView alloc] initWithEffect:e];
        g.tag = tag;
        g.capsule = radius < 0;
        g.fixedRadius = radius;
        g.userInteractionEnabled = NO;     // touches stay with the real control
        g.frame = host.bounds;
        g.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [host insertSubview:g atIndex:index];
        return g;
    }
    return nil;
}

// Spring "squish" while pressed, bounce back on release.
static void WCAnimatePress(UIView *glass, BOOL pressed) {
    [UIView animateWithDuration:pressed ? 0.22 : 0.5
                          delay:0
         usingSpringWithDamping:pressed ? 0.7 : 0.45
          initialSpringVelocity:0.6
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        glass.transform = pressed ? CGAffineTransformMakeScale(1.22, 1.22) : CGAffineTransformIdentity;
    } completion:nil];
}

// Glass behind a button, with press feedback driven by the button's own touch events.
static void WCGlassifyButton(UIButton *btn) {
    if (!btn || !WCGlassAvailable()) return;
    BOOL isNew = (WCFindGlass(btn, kWCGlassTag) == nil);
    WCGlassView *g = WCMakeGlass(btn, kWCGlassTag, NO, -1, nil, 0);
    if (!g || !isNew) return;
    __weak WCGlassView *wg = g;
    UIAction *down = [UIAction actionWithHandler:^(UIAction *a) { if (wg) WCAnimatePress(wg, YES); }];
    UIAction *up   = [UIAction actionWithHandler:^(UIAction *a) { if (wg) WCAnimatePress(wg, NO); }];
    [btn addAction:down forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [btn addAction:up forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside |
                                       UIControlEventTouchCancel | UIControlEventTouchDragExit];
}

// Read an ivar without KVC exceptions.
static id WCIvar(id obj, const char *name) {
    Ivar iv = class_getInstanceVariable([obj class], name);
    return iv ? object_getIvar(obj, iv) : nil;
}

#pragma mark - Chat input bar

%hook MMGrowTextView
- (void)layoutSubviews {
    %orig;
    UIView *p = self.superview;
    while (p && ![p isKindOfClass:%c(MMInputToolView)]) p = p.superview;
    if (!p || !WCGlassAvailable()) return;

    UIView *bg = WCIvar(self, "_backgroundView");   // original bubble-image background
    bg.hidden = YES;
    WCMakeGlass(self, kWCGlassTag, NO, -1, nil, 0);
}
%end

%hook MMInputToolView
- (void)layoutSubviews {
    %orig;
    if (!WCGlassAvailable()) return;

    self.backgroundColor = UIColor.clearColor;
    self.toolView.backgroundColor = UIColor.clearColor;
    UIView *kbBg = WCIvar(self, "m_keyboardBackgroundView");
    kbBg.hidden = YES;

    WCGlassifyButton(self.inputModeChangeButton);   // voice/keyboard toggle
    WCGlassifyButton(self.expressionButton);        // emoji
    WCGlassifyButton(self.attachmentButton);        // plus
}
%end

#pragma mark - Tab bar: floating glass capsule + sliding glass "lens" on the selected tab

static const void *kWCDraggingKey = &kWCDraggingKey;

%hook MMTabBar

- (void)layoutSubviews {
    %orig;
    if (!WCGlassAvailable()) return;

    [self configureClearBackground];
    self.backgroundView.hidden = YES;
    UIView *blur = [self findBlurEffectView:self];
    blur.hidden = YES;
    UIView *shadow = [self findShadowView:self];
    shadow.hidden = YES;

    WCGlassView *base = WCMakeGlass(self, kWCGlassTag, NO, -1, nil, 0);
    if (base) {
        base.autoresizingMask = UIViewAutoresizingNone;
        CGFloat bottom = self.safeAreaInsets.bottom;
        CGFloat h = MAX(self.bounds.size.height - bottom - 8, 40);
        base.frame = CGRectMake(12, 4, self.bounds.size.width - 24, h);
        [self sendSubviewToBack:base];
    }

    // Lens (selected-tab glass), sits just above the base glass, below the item views.
    WCGlassView *lens = WCMakeGlass(self, kWCLensTag, YES, -1, nil, 1);
    if (lens) {
        lens.autoresizingMask = UIViewAutoresizingNone;
        if (base) [self insertSubview:lens aboveSubview:base];
        if (![objc_getAssociatedObject(self, kWCDraggingKey) boolValue]) {
            [self wc_updateLensAnimated:NO];
        }
    }
}

%new
- (void)wc_updateLensAnimated:(BOOL)animated {
    WCGlassView *base = WCFindGlass(self, kWCGlassTag);
    WCGlassView *lens = WCFindGlass(self, kWCLensTag);
    if (!base || !lens) return;

    long long count = [self tabBarItemCount];
    for (long long i = 0; i < count; i++) {
        if (![self targetIndexIsSelected:i]) continue;
        UIView *item = [self tabBarItemViewAtIndex:i];
        if (!item) return;
        CGRect r = [self convertRect:item.bounds fromView:item];
        CGRect target = CGRectMake(r.origin.x + 4, base.frame.origin.y + 4,
                                   r.size.width - 8, base.frame.size.height - 8);
        void (^apply)(void) = ^{ lens.frame = target; lens.transform = CGAffineTransformIdentity; };
        if (animated) {
            [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.72 initialSpringVelocity:0.4
                                options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                             animations:apply completion:nil];
        } else {
            apply();
        }
        return;
    }
}

- (void)selectIndex:(long long)index {
    %orig;
    if (!WCGlassAvailable()) return;
    [self wc_updateLensAnimated:YES];   // lens slides to the newly selected tab
}

// WeChat already has a pan handler on the tab bar; make the lens follow the finger.
- (void)handleTabBarPanGesture:(UIPanGestureRecognizer *)g {
    %orig;
    if (!WCGlassAvailable()) return;
    WCGlassView *base = WCFindGlass(self, kWCGlassTag);
    WCGlassView *lens = WCFindGlass(self, kWCLensTag);
    if (!base || !lens) return;

    switch (g.state) {
        case UIGestureRecognizerStateBegan:
        case UIGestureRecognizerStateChanged: {
            objc_setAssociatedObject(self, kWCDraggingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            CGFloat halfW = lens.bounds.size.width / 2.0;
            CGFloat x = [g locationInView:self].x;
            x = MAX(CGRectGetMinX(base.frame) + halfW, MIN(CGRectGetMaxX(base.frame) - halfW, x));
            [UIView animateWithDuration:0.12 delay:0
                                options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                             animations:^{
                lens.center = CGPointMake(x, lens.center.y);
                lens.transform = CGAffineTransformMakeScale(1.15, 1.15);
            } completion:nil];
            break;
        }
        default:
            objc_setAssociatedObject(self, kWCDraggingKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [self wc_updateLensAnimated:YES];
            break;
    }
}

%end

#pragma mark - Navigation bar (remove the opaque/blur backdrop)

%hook MMUINavigationBar
- (void)layoutSubviews {
    %orig;
    if (!WCGlassAvailable()) return;
    self.effectSubview.hidden = YES;
    self.shadowImage = [UIImage new];
}
%end
