#import <UIKit/UIKit.h>
#import <AppList/AppList.h>
#import "../LTCommon.h"
#import "Tweak.h"

#define ICON_SIZE 59

static int ltInit = 0;
static int ltMode = 0;
static int ltSide = 0;
static int ltStyle = 0;
static int ltMaxApps = 3;
static float ltAnimationMultiplier = 1.0;
static bool ltFollowVertical = false;
static ALApplicationList* appList = [ALApplicationList sharedApplicationList];
static NSMutableArray* windows = [NSMutableArray new];
static LSApplicationWorkspace* workspace = [NSClassFromString(@"LSApplicationWorkspace") new];

void LTAppChanged() {
    NSString *bundle = [NSBundle mainBundle].bundleIdentifier;
    HBPreferences *preferences = [[HBPreferences alloc] initWithIdentifier:LTRecentFile];
    [preferences setDouble:[[NSDate date] timeIntervalSince1970] forKey:bundle];

    if (ltMode != LTModeDisabled) {
        for (UIWindow *window in windows) {
            if (window && window.ltView) {
                window.ltView.hidden = YES;
            }
        }
    }

}

void LTPreferencesChanged() {
    HBPreferences *preferences = [[HBPreferences alloc] initWithIdentifier:LTPreferencesIdentifier];
    ltMode = [([preferences objectForKey:LTEnabled] ?: @(2)) intValue];
    ltSide = [([preferences objectForKey:@"Side"] ?: @(0)) intValue];
    ltStyle = [([preferences objectForKey:@"Style"] ?: @(0)) intValue];
    ltMaxApps = [([preferences objectForKey:@"MaxIcons"] ?: @(3)) intValue];
    ltFollowVertical = [([preferences objectForKey:@"FollowVertical"] ?: @(NO)) boolValue];

    int speed = [([preferences objectForKey:@"AnimationSpeed"] ?: @(5)) intValue];
    ltAnimationMultiplier = (10.0-speed)*2.0/10.0;
    
    HBPreferences *disabled = [[HBPreferences alloc] initWithIdentifier:LTDisableFile];

    NSString *bundle = [NSBundle mainBundle].bundleIdentifier;
    if ([([disabled objectForKey:bundle] ?: @(0)) intValue] == 1) {
        ltMode = LTModeDisabled;
    }

    if (ltMode == LTModeDisabled) {
        for (UIWindow *window in windows) {
            if (window) {
                [window ltDisable];
            }
        }
    } else {
        for (UIWindow *window in windows) {
            if (window) {
                [window ltEnable];
            }
        }
    }
}

@implementation LTView

@synthesize upGestureRecognizer, downGestureRecognizer, swipeGestureRecognizer, gradientLayer, iconOffset, iconViews, originY, currentSide;

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    self.currentSide = -1;

    [self setUserInteractionEnabled:YES];
    self.hidden = YES;

    self.gradientLayer = [CAGradientLayer layer];
    self.gradientLayer.frame = self.bounds;
    self.gradientLayer.colors = @[(id)[UIColor clearColor].CGColor, (id)[UIColor blackColor].CGColor];
    self.gradientLayer.startPoint = CGPointMake(0.2, 0);
    self.gradientLayer.endPoint = CGPointMake(2.0, 0);
    [self.layer insertSublayer:self.gradientLayer atIndex:0];

    UITapGestureRecognizer *singleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap)];
    singleTap.numberOfTapsRequired = 1;
    [self addGestureRecognizer:singleTap];

    self.swipeGestureRecognizer = [[UISwipeGestureRecognizer alloc]initWithTarget:self action:@selector(gestureRecognized:)];
    self.swipeGestureRecognizer.numberOfTouchesRequired = 1;
    [self addGestureRecognizer:self.swipeGestureRecognizer];

    self.upGestureRecognizer = [[UISwipeGestureRecognizer alloc]initWithTarget:self action:@selector(gestureRecognized:)];
    self.upGestureRecognizer.direction = UISwipeGestureRecognizerDirectionUp;
    self.upGestureRecognizer.numberOfTouchesRequired = 1;
    [self addGestureRecognizer:self.upGestureRecognizer];

    self.downGestureRecognizer = [[UISwipeGestureRecognizer alloc]initWithTarget:self action:@selector(gestureRecognized:)];
    self.downGestureRecognizer.direction = UISwipeGestureRecognizerDirectionDown;
    self.downGestureRecognizer.numberOfTouchesRequired = 1;
    [self addGestureRecognizer:self.downGestureRecognizer];

    return self;
}

-(CGRect)getEndingFrameForIcon:(LTIconView *)icon {
    int index = [self.iconViews indexOfObject:icon];
    int count = [self.iconViews count];
    CGFloat piVal = (ltStyle == 1) ? M_PI * 2 : M_PI;
    CGFloat alignOffset = 0;

    if ((count % 2 == 0 || ltStyle == 1) && !(count % 2 == 0 && ltStyle == 1)) {
        alignOffset = -0.5;
    }

    if (count == 1) {
        alignOffset = 0;
    }

    CGFloat angle = (piVal/count) * (index) + (-piVal/count) * (floor(count/2) + alignOffset + self.iconOffset);
    if (self.currentSide == 0) angle += M_PI;

    int radius = self.frame.size.width;
    CGFloat x = radius*cos(angle);
    CGFloat y = radius*sin(angle);

    if (ltFollowVertical) {
        y += self.originY;
    } else {
        y += self.frame.size.height/2;
    }

    if (self.currentSide == 0) {
        x += self.frame.size.width;
    } else {
        x -= ICON_SIZE;
    }

    return CGRectMake(x, y, ICON_SIZE, ICON_SIZE);
}

-(CGRect)getStartingFrameForIcon:(LTIconView *)icon {
    if (self.currentSide == 0) {
        return CGRectMake(self.frame.size.width + ICON_SIZE, self.frame.size.height/2 - ICON_SIZE/2, ICON_SIZE, ICON_SIZE);
    } else {
        return CGRectMake(-ICON_SIZE, self.frame.size.height/2 - ICON_SIZE/2, ICON_SIZE, ICON_SIZE);
    }
}

-(void)updateIcons {
    NSArray *apps;

    if (ltMode == LTModeRecent) {
        HBPreferences *preferences = [[HBPreferences alloc] initWithIdentifier:LTRecentFile];
        NSDictionary *prefDict = [preferences dictionaryRepresentation];
        apps = [[prefDict allKeys] sortedArrayUsingComparator:^NSComparisonResult(NSString*  _Nonnull obj1, NSString*  _Nonnull obj2) {
            return [prefDict[obj1] doubleValue] < [prefDict[obj2] doubleValue];
        }];
    } else if (ltMode == LTModeSelect) {
        NSMutableArray *temp = [NSMutableArray new];

        HBPreferences *preferences = [[HBPreferences alloc] initWithIdentifier:LTSelectFile];
        NSDictionary *prefDict = [preferences dictionaryRepresentation];

        for (NSString *bundle in [prefDict allKeys]) {
            if ([prefDict[bundle] boolValue]) {
                [temp addObject:bundle];
            }
        }

        apps = temp;
    }

    if (self.iconViews) {
        for (LTIconView *icon in self.iconViews) {
            [icon removeFromSuperview];
        }
    }

    NSMutableArray *icons = [NSMutableArray new];

    int i = 0;
    for (NSString *bundle in apps) {
        if (ltMode == LTModeRecent) {
            if (i == 0) {
                i = 1;
                continue;
            }
            if (i == (ltMaxApps + 1)) break;
            i++;
        }
        LTIconView *icon = [LTIconView iconWithBundleIdentifier:bundle];
        if (icon) {
            [self addSubview:icon];
            [icons addObject:icon];
        }
    }

    self.iconViews = icons;

    for (LTIconView *icon in self.iconViews) {
        icon.frame = [self getStartingFrameForIcon:icon];
    }
}

-(void)setSide:(int)side {
    if (self.currentSide == side) return;
    self.currentSide = side;
    self.alpha = 0.0;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    if (side == 0) {
        self.swipeGestureRecognizer.direction = UISwipeGestureRecognizerDirectionRight;
        self.gradientLayer.transform = CATransform3DMakeScale(1, 1, 1);
    } else {
        self.swipeGestureRecognizer.direction = UISwipeGestureRecognizerDirectionLeft;
        self.gradientLayer.transform = CATransform3DMakeScale(-1, 1, 1);
    }
    
    [CATransaction commit];

    for (LTIconView *icon in self.iconViews) {
        icon.frame = [self getStartingFrameForIcon:icon];
    }
}

-(void)handleTap {
    [self setVisibility:false];
}

-(void)gestureRecognized:(id)gesture {
    bool animateIcons = false;

    if (gesture == self.swipeGestureRecognizer) {
        [self setVisibility:false];
    } else if (gesture == self.upGestureRecognizer) {
        if (self.currentSide == 0) self.iconOffset--;
        else self.iconOffset++;

        animateIcons = true;
    } else if (gesture == self.downGestureRecognizer) {
        if (self.currentSide != 0) self.iconOffset--;
        else self.iconOffset++;

        animateIcons = true;
    }

    if (animateIcons) {
        [UIView animateWithDuration:(0.2*ltAnimationMultiplier) delay:0.0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
            for (LTIconView *icon in self.iconViews) {
                icon.frame = [self getEndingFrameForIcon:icon];
            }
        } completion:NULL];
    }
}

-(void)setVisibility:(bool)state {
    if (state) {
        self.iconOffset = 0;
        self.hidden = NO;
        if (self.alpha != 1.0) self.alpha = 0.0;
        [self.superview bringSubviewToFront:self];

        [UIView animateWithDuration:(0.3*ltAnimationMultiplier) delay:0.0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
            self.alpha = 1.0;
            for (LTIconView *icon in self.iconViews) {
                icon.frame = [self getEndingFrameForIcon:icon];
            }
        } completion:NULL];
    } else {
        self.alpha = 1.0;
        [self.superview bringSubviewToFront:self];

        [UIView animateWithDuration:(0.3*ltAnimationMultiplier) delay:0.0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
            self.alpha = 0.0;
            for (LTIconView *icon in self.iconViews) {
                icon.frame = [self getStartingFrameForIcon:icon];
            }
        } completion:NULL];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (0.3*ltAnimationMultiplier) * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            self.hidden = YES;
        });
    }
}

@end

@implementation LTIconView

@synthesize bundleIdentifier;

+(LTIconView *)iconWithBundleIdentifier:(NSString *)bundle {
    UIImage *image = [appList iconOfSize:ALApplicationIconSizeLarge forDisplayIdentifier:bundle];
    if (!image) return nil;

    LTIconView *icon = [[LTIconView alloc] initWithImage:image];
    icon.bundleIdentifier = bundle;

    UITapGestureRecognizer *singleTap = [[UITapGestureRecognizer alloc] initWithTarget:icon action:@selector(handleTap)];
    singleTap.numberOfTapsRequired = 1;
    [icon setUserInteractionEnabled:YES];
    [icon addGestureRecognizer:singleTap];

    return icon;
}

-(void)handleTap {
    if (self.superview) {
        [(LTView*)self.superview setVisibility:false];
    }

    [workspace openApplicationWithBundleID:self.bundleIdentifier];
}

@end

%group Launchtron

%hook UIWindow

%property (nonatomic, retain) UIScreenEdgePanGestureRecognizer* ltLeftGestureRecognizer;
%property (nonatomic, retain) UIScreenEdgePanGestureRecognizer* ltRightGestureRecognizer;
%property (nonatomic, retain) LTView* ltView;

-(void)layoutSubviews {
    %orig;
    
    if (ltInit == 0) {
        LTAppChanged();
        LTPreferencesChanged();

        CFNotificationCenterAddObserver(CFNotificationCenterGetLocalCenter(), NULL, (CFNotificationCallback)LTAppChanged, (CFStringRef)UIApplicationDidBecomeActiveNotification, NULL, kNilOptions);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)LTPreferencesChanged, (CFStringRef)LTNotification, NULL, kNilOptions);
        ltInit = 1;
    }
    
    if (self.ltView) {
        self.ltView.iconOffset = 0;
    }
    
    if (![windows containsObject:self]) {
        [windows addObject:self];
    }

    [self ltAddView];
    [self ltAddGestureRecognizer];

    if (ltMode != LTModeDisabled) {
        [self ltEnable];
    } else {
        [self ltDisable];
    }
}

%new;
-(void)ltDisable {
    if (!self.ltView) return;

    [self.ltView removeFromSuperview];
    [self removeGestureRecognizer:self.ltLeftGestureRecognizer];
    [self removeGestureRecognizer:self.ltRightGestureRecognizer];
}

%new;
-(void)ltEnable {
    if (!self.ltView) return;

    self.ltView.iconOffset = 0;
    [self ltSetSide:ltSide];
    [self.ltView updateIcons];
    [self addSubview:self.ltView];
    [self addGestureRecognizer:self.ltLeftGestureRecognizer];
    [self addGestureRecognizer:self.ltRightGestureRecognizer];
}

%new;
-(void)ltAddGestureRecognizer {
    if (self.ltLeftGestureRecognizer) return;

    self.ltLeftGestureRecognizer = [[UIScreenEdgePanGestureRecognizer alloc]initWithTarget:self action:@selector(ltGestureRecognized:)];
    self.ltLeftGestureRecognizer.edges = UIRectEdgeLeft;

    self.ltRightGestureRecognizer = [[UIScreenEdgePanGestureRecognizer alloc]initWithTarget:self action:@selector(ltGestureRecognized:)];
    self.ltRightGestureRecognizer.edges = UIRectEdgeRight;
}

%new;
-(void)ltSetSide:(int)side {
    if (!self.ltView) return;

    if (side == 2) side = 0;

    if (side == 0) {
        self.ltView.frame = CGRectMake(self.frame.size.width/2, self.frame.origin.y, self.frame.size.width/2, self.frame.size.height);
    } else {
        self.ltView.frame = CGRectMake(0, self.frame.origin.y, self.frame.size.width/2, self.frame.size.height);
    }

    [self.ltView setSide:side];
}

%new;
-(void)ltAddView {
    if (self.ltView) return;

    self.ltView = [[LTView alloc] initWithFrame:CGRectMake(self.frame.size.width/2, self.frame.origin.y, self.frame.size.width/2, self.frame.size.height)];
}

%new;
-(void)ltGestureRecognized:(id)gesture {
    if (!self.ltView) return;

    if (ltSide == 2) {
        if (gesture == self.ltLeftGestureRecognizer) {
            [self ltSetSide:1];
        } else if (gesture == self.ltRightGestureRecognizer) {
            [self ltSetSide:0];
        }
    } else {
        if (gesture == self.ltLeftGestureRecognizer && ltSide != 1) return;
        if (gesture == self.ltRightGestureRecognizer && ltSide != 0) return;
    }

    CGPoint location = [gesture locationInView:self];
    self.ltView.originY = location.y;
    [self.ltView setVisibility:true];
}

%end

%end

%ctor {
    // Someone smarter than me invented this.
    // https://www.reddit.com/r/jailbreak/comments/4yz5v5/questionremote_messages_not_enabling/d6rlh88/
    bool shouldLoad = NO;
    NSArray *args = [[NSClassFromString(@"NSProcessInfo") processInfo] arguments];
    NSUInteger count = args.count;
    if (count != 0) {
        NSString *executablePath = args[0];
        if (executablePath) {
            NSString *processName = [executablePath lastPathComponent];
            BOOL isApplication = [executablePath rangeOfString:@"/Application/"].location != NSNotFound || [executablePath rangeOfString:@"/Applications/"].location != NSNotFound;
            BOOL isFileProvider = [[processName lowercaseString] rangeOfString:@"fileprovider"].location != NSNotFound;
            BOOL skip = [processName isEqualToString:@"AdSheet"]
                        || [processName isEqualToString:@"CoreAuthUI"]
                        || [processName isEqualToString:@"InCallService"]
                        || [processName isEqualToString:@"MessagesNotificationViewService"]
                        || [executablePath rangeOfString:@".appex/"].location != NSNotFound;
            if (!isFileProvider && isApplication && !skip) {
                shouldLoad = YES;
            }
        }
    }

    if (shouldLoad) {
        %init(Launchtron);
    }
}