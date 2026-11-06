// WeChatGlass - Liquid Glass for WeChat (iOS 26+ SDK required to build)
// Hooks are based on the class-dump headers: MMInputToolView, MMGrowTextView,
// MMUIButton, MMTabBar, MMUINavigationBar.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

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
@end

@interface MMUINavigationBar : UINavigationBar
@property (nonatomic, strong) UIView *effectSubview;
@end

#pragma mark - Glass helper

static const NSInteger kWCGlassTag = 0x474C;

@interface WCGlassView : UIVisualEffectView
@property (nonatomic) BOOL capsule;       // radius = min(w,h)/2
@property (nonatomic) CGFloat fixedRadius; // used when capsule == NO
@end

@implementation WCGlassView
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat r = self.capsule ? MIN(self.bounds.size.width, self.bounds.size.height) / 2.0
                             : self.fixedRadius;
    self.layer.cornerRadius = r;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.clipsToBounds = YES;
}
@end

// Adds (once) a glass layer at the bottom of `host`. radius < 0 => capsule.
static WCGlassView *WCApplyGlass(UIView *host, CGFloat radius, UIColor *tint, BOOL interactive) {
    if (!host) return nil;
    for (UIView *v in host.subviews) {
        if (v.tag == kWCGlassTag && [v isKindOfClass:WCGlassView.class]) return (WCGlassView *)v;
    }
    if (@available(iOS 26.0, *)) {
        UIGlassEffect *e = [UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular];
        e.tintColor = tint;
        e.interactive = interactive;
        WCGlassView *g = [[WCGlassView alloc] initWithEffect:e];
        g.tag = kWCGlassTag;
        g.capsule = radius < 0;
        g.fixedRadius = radius;
        g.userInteractionEnabled = NO;
        g.frame = host.bounds;
        g.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [host insertSubview:g atIndex:0];
        return g;
    }
    return nil;
}

static BOOL WCGlassAvailable(void) {
    if (@available(iOS 26.0, *)) return YES;
    return NO;
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
    // Only touch the grow text view that lives inside the chat input bar.
    UIView *p = self.superview;
    while (p && ![p isKindOfClass:%c(MMInputToolView)]) p = p.superview;
    if (!p || !WCGlassAvailable()) return;

    UIView *bg = WCIvar(self, "_backgroundView");   // the original bubble-image background
    bg.hidden = YES;
    WCApplyGlass(self, -1, nil, NO);
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

    WCApplyGlass(self.inputModeChangeButton, -1, nil, YES);   // voice/keyboard toggle (circle)
    WCApplyGlass(self.expressionButton,      -1, nil, YES);   // emoji
    WCApplyGlass(self.attachmentButton,      -1, nil, YES);   // plus
}
%end

#pragma mark - Tab bar (floating capsule)

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

    WCGlassView *g = WCApplyGlass(self, -1, nil, NO);
    if (g) {
        g.autoresizingMask = UIViewAutoresizingNone;
        CGFloat bottom = self.safeAreaInsets.bottom;
        CGFloat h = MAX(self.bounds.size.height - bottom - 8, 40);
        g.frame = CGRectMake(12, 4, self.bounds.size.width - 24, h);
        [self sendSubviewToBack:g];
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
