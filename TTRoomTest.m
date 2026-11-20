#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <stdarg.h>

static BOOL gAntiMute = NO;
static BOOL gAntiClear = NO;
static BOOL gAudio192 = NO;
static BOOL gSkin = NO;
static BOOL gAntiKick = NO;
static BOOL gUpMic = NO;
static BOOL gIsland = NO;
static unsigned int gSkinDressId = 0;
static NSMutableDictionary *gOrigImps = nil;
static NSMutableArray *gLogLines = nil;
static dispatch_queue_t gLogQueue = NULL;
static NSFileHandle *gLogHandle = nil;
static UIButton *gFloatBtn = nil;
static UIView *gPanel = nil;
static UITextView *gLogView = nil;
static UITextField *gDressField = nil;

static void YTLog(NSString *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    [df setDateFormat:@"HH:mm:ss.SSS"];
    NSString *line = [NSString stringWithFormat:@"%@ %@", [df stringFromDate:[NSDate date]], msg];
    NSLog(@"[TTRoomTest] %@", line);
    dispatch_async(gLogQueue, ^{
        if (!gLogLines) gLogLines = [[NSMutableArray alloc] init];
        [gLogLines addObject:line];
        while ([gLogLines count] > 200) [gLogLines removeObjectAtIndex:0];
        if (gLogHandle) {
            @try { [gLogHandle writeData:[[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]]; } @catch (NSException *e) {}
        }
        NSString *joined = [gLogLines componentsJoinedByString:@"\n"];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (gLogView) {
                gLogView.text = joined;
                NSRange r = NSMakeRange([gLogView.text length], 0);
                [gLogView scrollRangeToVisible:r];
            }
        });
    });
}

static NSString *YTKey(Class cls, SEL sel) {
    return [NSString stringWithFormat:@"%@|%@", NSStringFromClass(cls), NSStringFromSelector(sel)];
}

static IMP YTOrig(Class cls, SEL sel) {
    return (IMP)[[gOrigImps objectForKey:YTKey(cls, sel)] pointerValue];
}

static void YTSwizzle(Class cls, SEL sel, IMP repl) {
    if (!cls) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) { YTLog(@"MISS %@ %@", NSStringFromClass(cls), NSStringFromSelector(sel)); return; }
    IMP orig = method_getImplementation(m);
    const char *types = method_getTypeEncoding(m);
    BOOL added = class_addMethod(cls, sel, repl, types);
    if (added) {
        [gOrigImps setObject:[NSValue valueWithPointer:(void *)orig] forKey:YTKey(cls, sel)];
    } else {
        IMP old = method_setImplementation(m, repl);
        [gOrigImps setObject:[NSValue valueWithPointer:(void *)old] forKey:YTKey(cls, sel)];
    }
    YTLog(@"HOOK %@ %@ orig=%p", NSStringFromClass(cls), NSStringFromSelector(sel), orig);
}

static NSString *YTDesc(id obj) {
    if (!obj) return @"nil";
    NSString *s = nil;
    @try { s = [obj description]; } @catch (NSException *e) { s = @"<desc err>"; }
    if ([s length] > 160) s = [s substringToIndex:160];
    return [NSString stringWithFormat:@"%@:%@", NSStringFromClass([obj class]), s];
}

static void yt_onMuteMicAction4(id self, SEL _cmd, BOOL mute, id tips, id muteToast, id unmuteToast) {
    YTLog(@"onMuteMicAction mute=%d tips=%@ self=%@", mute, YTDesc(tips), NSStringFromClass([self class]));
    if (gAntiMute && mute) { YTLog(@"AntiMute BLOCK mute"); return; }
    IMP orig = YTOrig([self class], _cmd);
    if (orig) ((void (*)(id, SEL, BOOL, id, id, id))orig)(self, _cmd, mute, tips, muteToast, unmuteToast);
}

static BOOL yt_shouldIgnoreMuteMic(id self, SEL _cmd, id arg) {
    BOOL origVal = NO;
    IMP orig = YTOrig([self class], _cmd);
    if (orig) origVal = ((BOOL (*)(id, SEL, id))orig)(self, _cmd, arg);
    YTLog(@"shouldIgnoreMuteMic arg=%@ orig=%d antiMute=%d", YTDesc(arg), origVal, gAntiMute);
    if (gAntiMute) return YES;
    return origVal;
}

static void yt_onKicked(id self, SEL _cmd, id msg) {
    YTLog(@"KICK %@ msg=%@ self=%@", NSStringFromSelector(_cmd), YTDesc(msg), NSStringFromClass([self class]));
    if (gAntiKick) { YTLog(@"AntiKick BLOCK %@", NSStringFromSelector(_cmd)); return; }
    IMP orig = YTOrig([self class], _cmd);
    if (orig) ((void (*)(id, SEL, id))orig)(self, _cmd, msg);
}

static void yt_clearData(id self, SEL _cmd) {
    YTLog(@"CLEAR %@ self=%@", NSStringFromSelector(_cmd), NSStringFromClass([self class]));
    if (gAntiClear) { YTLog(@"AntiClear BLOCK %@", NSStringFromSelector(_cmd)); return; }
    IMP orig = YTOrig([self class], _cmd);
    if (orig) ((void (*)(id, SEL))orig)(self, _cmd);
}

static id yt_jsUiClear(id self, SEL _cmd, id arg, id callback) {
    YTLog(@"jsUi_clearChatBoxChannel arg=%@ cb=%@ self=%@", YTDesc(arg), YTDesc(callback), NSStringFromClass([self class]));
    if (gAntiClear) { YTLog(@"AntiClear BLOCK jsUi_clear"); return nil; }
    IMP orig = YTOrig([self class], _cmd);
    if (orig) return ((id (*)(id, SEL, id, id))orig)(self, _cmd, arg, callback);
    return nil;
}

static void yt_updateAudioBitRate(id self, SEL _cmd, id arg) {
    YTLog(@"updateAudioBitRate arg=%@ self=%@ audio192=%d", YTDesc(arg), NSStringFromClass([self class]), gAudio192);
    IMP orig = YTOrig([self class], _cmd);
    if (!orig) return;
    if (gAudio192 && [arg isKindOfClass:[NSNumber class]]) {
        YTLog(@"Audio192 REPLACE %@ -> 192000", arg);
        ((void (*)(id, SEL, id))orig)(self, _cmd, @(192000));
        return;
    }
    ((void (*)(id, SEL, id))orig)(self, _cmd, arg);
}

static void yt_onChannelAudioBitRateChanged(id self, SEL _cmd, unsigned int channelId, id arg) {
    YTLog(@"onChannelId:audioBitRateChanged channel=%u arg=%@", channelId, YTDesc(arg));
    IMP orig = YTOrig([self class], _cmd);
    if (orig) ((void (*)(id, SEL, unsigned int, id))orig)(self, _cmd, channelId, arg);
}

static void yt_onRoomSuitDressIdUpdatedTo(id self, SEL _cmd, unsigned int dressId) {
    YTLog(@"onRoomSuitDressIdUpdatedTo dressId=%u skin=%d override=%u", dressId, gSkin, gSkinDressId);
    IMP orig = YTOrig([self class], _cmd);
    if (!orig) return;
    if (gSkin && gSkinDressId > 0) {
        ((void (*)(id, SEL, unsigned int))orig)(self, _cmd, gSkinDressId);
        return;
    }
    ((void (*)(id, SEL, unsigned int))orig)(self, _cmd, dressId);
}

static BOOL yt_supportChangemic(id self, SEL _cmd, id micSpace, id *tip) {
    BOOL origVal = NO;
    IMP orig = YTOrig([self class], _cmd);
    if (orig) origVal = ((BOOL (*)(id, SEL, id, id *))orig)(self, _cmd, micSpace, tip);
    YTLog(@"supportChangemic micSpace=%@ orig=%d upMic=%d self=%@", YTDesc(micSpace), origVal, gUpMic, NSStringFromClass([self class]));
    if (gUpMic) return YES;
    return origVal;
}

static BOOL yt_supportChangemicCb(id self, SEL _cmd, id micSpace, id *tip, id callback) {
    BOOL origVal = NO;
    IMP orig = YTOrig([self class], _cmd);
    if (orig) origVal = ((BOOL (*)(id, SEL, id, id *, id))orig)(self, _cmd, micSpace, tip, callback);
    YTLog(@"supportChangemic:tip:callback micSpace=%@ orig=%d upMic=%d self=%@", YTDesc(micSpace), origVal, gUpMic, NSStringFromClass([self class]));
    if (gUpMic) return YES;
    return origVal;
}

static BOOL yt_isCanChangeMeToMic(id self, SEL _cmd, id arg, BOOL isMeOnMic, id *reason, id callback) {
    BOOL origVal = NO;
    IMP orig = YTOrig([self class], _cmd);
    if (orig) origVal = ((BOOL (*)(id, SEL, id, BOOL, id *, id))orig)(self, _cmd, arg, isMeOnMic, reason, callback);
    YTLog(@"isCanChangeMeToMic arg=%@ isMeOnMic=%d orig=%d upMic=%d self=%@", YTDesc(arg), isMeOnMic, origVal, gUpMic, NSStringFromClass([self class]));
    if (gUpMic) return YES;
    return origVal;
}

static id yt_getChannelLiveActivityContainerView(id self, SEL _cmd) {
    IMP orig = YTOrig([self class], _cmd);
    id v = nil;
    if (orig) v = ((id (*)(id, SEL))orig)(self, _cmd);
    YTLog(@"getChannelLiveActivityContainerView -> %@ island=%d", YTDesc(v), gIsland);
    return v;
}

static void yt_registerLiveActivity(id self, SEL _cmd, id a, id b, long long seq) {
    YTLog(@"registerLiveActivity %@ a=%@ b=%@ seq=%lld self=%@", NSStringFromSelector(_cmd), YTDesc(a), YTDesc(b), seq, NSStringFromClass([self class]));
    IMP orig = YTOrig([self class], _cmd);
    if (orig) ((void (*)(id, SEL, id, id, long long))orig)(self, _cmd, a, b, seq);
}

@interface TTRoomPanel : NSObject
+ (void)togglePanel;
+ (void)switchChanged:(UISwitch *)sw;
+ (void)dressChanged:(UITextField *)tf;
@end

@implementation TTRoomPanel
+ (void)switchChanged:(UISwitch *)sw {
    BOOL on = sw.on;
    switch (sw.tag) {
        case 1: gAntiMute = on; break;
        case 2: gAntiClear = on; break;
        case 3: gAudio192 = on; break;
        case 4: gSkin = on; break;
        case 5: gAntiKick = on; break;
        case 6: gUpMic = on; break;
        case 7: gIsland = on; break;
        default: break;
    }
    YTLog(@"SWITCH tag=%ld on=%d mute=%d clear=%d audio=%d skin=%d kick=%d upMic=%d island=%d", (long)sw.tag, on, gAntiMute, gAntiClear, gAudio192, gSkin, gAntiKick, gUpMic, gIsland);
}
+ (void)dressChanged:(UITextField *)tf {
    gSkinDressId = (unsigned int)[tf.text intValue];
    YTLog(@"SkinDressId=%u", gSkinDressId);
}
+ (void)togglePanel {
    if (!gPanel) return;
    gPanel.hidden = !gPanel.hidden;
}
@end

static UILabel *YTLabel(NSString *text, CGFloat y) {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(16, y, 200, 28)];
    l.text = text;
    l.textColor = [UIColor whiteColor];
    l.font = [UIFont systemFontOfSize:15];
    return l;
}

static UISwitch *YTSwitch(NSInteger tag, CGFloat y) {
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(260, y, 60, 28)];
    sw.tag = tag;
    sw.on = NO;
    [sw addTarget:[TTRoomPanel class] action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    return sw;
}

static void YTBuildUI(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *win = nil;
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (w.isKeyWindow) { win = w; break; }
        }
        if (!win) win = [[UIApplication sharedApplication].windows firstObject];
        if (!win) { YTLog(@"UI no window"); return; }
        gFloatBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        gFloatBtn.frame = CGRectMake(win.bounds.size.width - 76, 120, 60, 36);
        [gFloatBtn setTitle:@"房测" forState:UIControlStateNormal];
        gFloatBtn.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.75];
        [gFloatBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        gFloatBtn.layer.cornerRadius = 8;
        [gFloatBtn addTarget:[TTRoomPanel class] action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
        [win addSubview:gFloatBtn];
        CGFloat pw = 340;
        CGFloat ph = 520;
        gPanel = [[UIView alloc] initWithFrame:CGRectMake((win.bounds.size.width - pw) / 2, 90, pw, ph)];
        gPanel.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.96];
        gPanel.layer.cornerRadius = 12;
        gPanel.hidden = YES;
        UILabel *title = YTLabel(@"房间测试 v2", 10);
        title.font = [UIFont boldSystemFontOfSize:17];
        [gPanel addSubview:title];
        NSArray *names = @[@"防闭麦", @"防清屏", @"192k 音质", @"皮肤 DressId", @"防踢", @"万能上麦", @"灵动岛记录"];
        for (NSInteger i = 0; i < [names count]; i++) {
            CGFloat y = 48 + i * 38;
            [gPanel addSubview:YTLabel(names[i], y)];
            [gPanel addSubview:YTSwitch(i + 1, y)];
        }
        gDressField = [[UITextField alloc] initWithFrame:CGRectMake(16, 320, 200, 32)];
        gDressField.placeholder = @"DressId (0=只记录)";
        gDressField.textColor = [UIColor whiteColor];
        gDressField.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1];
        gDressField.keyboardType = UIKeyboardTypeNumberPad;
        [gDressField addTarget:[TTRoomPanel class] action:@selector(dressChanged:) forControlEvents:UIControlEventEditingChanged];
        [gPanel addSubview:gDressField];
        gLogView = [[UITextView alloc] initWithFrame:CGRectMake(16, 362, pw - 32, 140)];
        gLogView.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1];
        gLogView.textColor = [UIColor greenColor];
        gLogView.font = [UIFont systemFontOfSize:10];
        gLogView.editable = NO;
        [gPanel addSubview:gLogView];
        [win addSubview:gPanel];
        YTLog(@"UI built");
    });
}

static void YTInstallHooks(void) {
    YTSwizzle(NSClassFromString(@"CommonRealTimeVoiceRoomViewController"), @selector(onMuteMicAction:tipsInView:muteToast:unmuteToast:), (IMP)yt_onMuteMicAction4);
    YTSwizzle(NSClassFromString(@"RealTimeMicControl"), @selector(shouldIgnoreMuteMic:), (IMP)yt_shouldIgnoreMuteMic);
    YTSwizzle(NSClassFromString(@"CommonRealTimeVoiceRoomViewController"), @selector(onChannelMsgKicked:), (IMP)yt_onKicked);
    YTSwizzle(NSClassFromString(@"CommonRealTimeVoiceRoomViewController"), @selector(onChannelMsgKickedMic:), (IMP)yt_onKicked);
    YTSwizzle(NSClassFromString(@"CommonRealTimeVoiceRoomViewController"), @selector(onChannelMsgPushTimeOutKickedSelf:), (IMP)yt_onKicked);
    YTSwizzle(NSClassFromString(@"RealTimeMicControl"), @selector(onMicKicked:), (IMP)yt_onKicked);
    YTSwizzle(NSClassFromString(@"CommonChannelServiceCache"), @selector(clearChannelMessageData), (IMP)yt_clearData);
    YTSwizzle(NSClassFromString(@"CommonChannelServiceCache"), @selector(clearChannelMessageDataWithoutGiftMessage), (IMP)yt_clearData);
    YTSwizzle(NSClassFromString(@"RealTimeMicGameControl"), @selector(jsUi_clearChatBoxChannel:callback:), (IMP)yt_jsUiClear);
    YTSwizzle(NSClassFromString(@"RealTimeAVLiveRoom"), @selector(updateAudioBitRate:), (IMP)yt_updateAudioBitRate);
    YTSwizzle(NSClassFromString(@"RealTimeAVRoom"), @selector(updateAudioBitRate:), (IMP)yt_updateAudioBitRate);
    YTSwizzle(NSClassFromString(@"RealTimeMicControl"), @selector(onChannelId:audioBitRateChanged:), (IMP)yt_onChannelAudioBitRateChanged);
    YTSwizzle(NSClassFromString(@"CommonRealTimeVoiceRoomViewController"), @selector(onRoomSuitDressIdUpdatedTo:), (IMP)yt_onRoomSuitDressIdUpdatedTo);
    NSArray *supportClasses = @[@"RealTimeMicControl", @"RealTimeDramaticPgcMicControl", @"RealTimeDramaticUgcMicControl", @"RealTimeMicGameControl", @"RealTimeMicTempGameControl", @"WeddingMicControl", @"RealTimeSingPlayTempMicControl", @"RealTimeSingPlayUGCMicControl", @"RealTimeUGCBandMicControl"];
    for (NSString *cn in supportClasses) {
        YTSwizzle(NSClassFromString(cn), @selector(supportChangemic:tip:), (IMP)yt_supportChangemic);
    }
    NSArray *supportCbClasses = @[@"RealTimeMicControl", @"WeddingMicControl"];
    for (NSString *cn in supportCbClasses) {
        YTSwizzle(NSClassFromString(cn), @selector(supportChangemic:tip:callback:), (IMP)yt_supportChangemicCb);
    }
    NSArray *canChangeClasses = @[@"RealTimeMicControl", @"PGCDefaultMicControl", @"WeddingMicControl", @"RealTimeUGCBandMicControl", @"RealTimeMicGameControl"];
    for (NSString *cn in canChangeClasses) {
        YTSwizzle(NSClassFromString(cn), @selector(isCanChangeMeToMic:isMeOnMic:reason:callback:), (IMP)yt_isCanChangeMeToMic);
    }
    YTSwizzle(NSClassFromString(@"CommonRealTimeVoiceRoomViewController"), @selector(getChannelLiveActivityContainerView), (IMP)yt_getChannelLiveActivityContainerView);
    YTSwizzle(NSClassFromString(@"GtSdkManager"), @selector(registerLiveActivity:activityToken:sequenceNum:), (IMP)yt_registerLiveActivity);
    YTSwizzle(NSClassFromString(@"GXLiveManager"), @selector(registerLiveActivity:activityToken:sequenceNum:), (IMP)yt_registerLiveActivity);
}

__attribute__((constructor)) static void TTRoomTestInit(void) {
    gLogQueue = dispatch_queue_create("ttroomtest.log", DISPATCH_QUEUE_SERIAL);
    gOrigImps = [[NSMutableDictionary alloc] init];
    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *logPath = [docs stringByAppendingPathComponent:@"TTRoomTest.log"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:logPath]) {
        [[NSFileManager defaultManager] createFileAtPath:logPath contents:nil attributes:nil];
    }
    gLogHandle = [NSFileHandle fileHandleForWritingAtPath:logPath];
    [gLogHandle seekToEndOfFile];
    YTLog(@"TTRoomTest v2 loaded");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        YTInstallHooks();
        YTBuildUI();
        YTLog(@"hooks installed");
    });
}
