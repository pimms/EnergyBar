/**
 * @file ControlWidget.m
 *
 * @copyright 2018 Bill Zissimopoulos
 */
/*
 * This file is part of EnergyBar.
 *
 * You can redistribute it and/or modify it under the terms of the GNU
 * General Public License version 3 as published by the Free Software
 * Foundation.
 */

#import "ControlWidget.h"
#import "AudioControl.h"
#import "Brightness.h"
#import "CBBlueLightClient.h"
#import "KeyEvent.h"
#import "NSTouchBar+SystemModal.h"
#import "NowPlaying.h"
#import "TouchBarController.h"

#define MaxPanDistance                  50.0

@interface ControlWidgetPopoverBarSlider : NSSlider
@end

@implementation ControlWidgetPopoverBarSlider
- (NSSize)intrinsicContentSize
{
    NSSize size = [super intrinsicContentSize];
    size.width = 250;
    return size;
}
@end

@interface ControlWidgetPopoverBarController : TouchBarController
@end

@implementation ControlWidgetPopoverBarController
+ (id)controllerWithNibNamed:(NSString *)name
{
    id controller = [[[[self class] alloc] init] autorelease];
    NSArray *objects = nil;

    if (![[NSBundle mainBundle]
        loadNibNamed:name owner:controller topLevelObjects:&objects])
        return nil;

    return controller;
}

- (IBAction)close:(id)sender
{
    [self dismiss];
}
@end

@interface ControlWidgetBrightnessBarController : ControlWidgetPopoverBarController
@property (retain) CBBlueLightClient *blueLightClient;
@property (retain) IBOutlet NSButton *nightShiftButton;
@end

@implementation ControlWidgetBrightnessBarController
+ (id)controller
{
    return [self controllerWithNibNamed:@"BrightnessBar"];
}

- (id)init
{
    self = [super init];
    if (nil == self)
        return nil;

    self.blueLightClient = [[[CBBlueLightClient alloc] init] autorelease];
    [self.blueLightClient setStatusNotificationBlock:^{
        [self performSelectorOnMainThread:@selector(resetNightShift) withObject:nil waitUntilDone:NO];
    }];

    return self;
}

- (void)dealloc
{
    self.blueLightClient = nil;
    self.nightShiftButton = nil;

    [super dealloc];
}

- (void)awakeFromNib
{
    NSSliderTouchBarItem *item;

    item = [self.touchBar itemForIdentifier:@"BrightnessSlider"];
    item.slider.minValue = 0;
    item.slider.maxValue = 1;
    item.slider.altIncrementValue = 1.0 / 16;
    item.minimumValueAccessory.behavior = NSSliderAccessoryBehavior.valueStepBehavior;
    item.maximumValueAccessory.behavior = NSSliderAccessoryBehavior.valueStepBehavior;

#if 0
    item = [self.touchBar itemForIdentifier:@"KeyboardBrightnessSlider"];
    item.slider.minValue = 0;
    item.slider.maxValue = 1;
    item.slider.altIncrementValue = 1.0 / 16;
    item.minimumValueAccessory.behavior = NSSliderAccessoryBehavior.valueStepBehavior;
    item.maximumValueAccessory.behavior = NSSliderAccessoryBehavior.valueStepBehavior;
#endif

    [super awakeFromNib];
}

- (BOOL)presentWithPlacement:(NSInteger)placement
{
    NSSliderTouchBarItem *item;
    double value;

    value = GetDisplayBrightness();
    if (isnan(value))
        value = 0.5;

    item = [self.touchBar itemForIdentifier:@"BrightnessSlider"];
    item.slider.doubleValue = value;

    [self resetNightShift];

#if 0
    value = GetKeyboardBrightness();
    if (isnan(value))
        value = 0.5;

    item = [self.touchBar itemForIdentifier:@"KeyboardBrightnessSlider"];
    item.slider.doubleValue = value;
#endif

    return [super presentWithPlacement:placement];
}

- (IBAction)nightShiftButtonClick:(id)sender
{
    switch ([sender state])
    {
    case NSControlStateValueOn:
        [self.blueLightClient setEnabled:YES];
        break;
    case NSControlStateValueOff:
        [self.blueLightClient setEnabled:NO];
        break;
    default:
        NSLog(@"nightShiftButtonClick: %d", (int)[sender state]);
        break;
    }
}

- (IBAction)brightnessSliderAction:(id)sender
{
    NSSliderTouchBarItem *item = [self.touchBar itemForIdentifier:@"BrightnessSlider"];
    SetDisplayBrightness(item.slider.doubleValue);
}

- (void)resetNightShift
{
    CBBlueLightStatus status;
    if ([self.blueLightClient getBlueLightStatus:&status])
        self.nightShiftButton.state = status.enabled ? NSControlStateValueOn : NSControlStateValueOff;
}

#if 0
- (IBAction)keyboardBrightnessSliderAction:(id)sender
{
    NSSliderTouchBarItem *item = [self.touchBar itemForIdentifier:@"KeyboardBrightnessSlider"];
    SetKeyboardBrightness(item.slider.doubleValue);
}
#endif
@end

@interface ControlWidgetVolumeBarController : ControlWidgetPopoverBarController
@end

@implementation ControlWidgetVolumeBarController
+ (id)controller
{
    return [self controllerWithNibNamed:@"VolumeBar"];
}

- (void)awakeFromNib
{
    NSSliderTouchBarItem *item = [self.touchBar itemForIdentifier:@"VolumeSlider"];
    item.slider.minValue = 0;
    item.slider.maxValue = 1;
    item.slider.altIncrementValue = 1.0 / 16;
    item.minimumValueAccessory.behavior = NSSliderAccessoryBehavior.valueStepBehavior;
    item.maximumValueAccessory.behavior = NSSliderAccessoryBehavior.valueStepBehavior;

    [super awakeFromNib];
}

- (BOOL)presentWithPlacement:(NSInteger)placement
{
    double value = [AudioControl sharedInstance].volume;
    if (isnan(value))
        value = 0.5;

    NSSliderTouchBarItem *item = [self.touchBar itemForIdentifier:@"VolumeSlider"];
    item.slider.doubleValue = value;

    return [super presentWithPlacement:placement];
}

- (IBAction)volumeSliderAction:(id)sender
{
    NSSliderTouchBarItem *item = [self.touchBar itemForIdentifier:@"VolumeSlider"];
    [AudioControl sharedInstance].volume = item.slider.doubleValue;
    [AudioControl sharedInstance].mute = item.slider.doubleValue < 1.0 / (16 * 4);
}
@end

@interface ControlWidgetLevelView : NSView
@property (getter=value, setter=setValue:) double value;
@property (getter=indicatorWidth, setter=setIndicatorWidth:) CGFloat indicatorWidth;
@property (assign) CGFloat inset;
@property (retain) NSColor *backgroundColor;
@property (retain) NSColor *foregroundColor;
@end

@implementation ControlWidgetLevelView
{
    double _value;
    CGFloat _indicatorWidth;
    NSInteger _tag;
}

- (void)dealloc
{
    self.backgroundColor = nil;
    self.foregroundColor = nil;

    [super dealloc];
}

- (void)drawRect:(NSRect)rect
{
    NSColor *backgroundColor = self.backgroundColor;
    NSColor *foregroundColor = self.foregroundColor;

    if (nil == backgroundColor)
        backgroundColor = [NSColor clearColor];
    if (nil == foregroundColor)
        foregroundColor = [NSColor systemBlueColor];

    rect = self.bounds;

    [backgroundColor setFill];
    NSRectFillUsingOperation(rect, NSCompositingOperationSourceOver);

    CGFloat inset = self.inset;
    rect = NSInsetRect(rect, inset, inset);

    CGFloat indicatorWidth = self.indicatorWidth;
    if (0 > indicatorWidth)
    {
        CGFloat maxX = NSMaxX(rect);
        indicatorWidth = -indicatorWidth;
        rect.size.width = MIN(indicatorWidth, rect.size.width);
        rect.origin.x = maxX - rect.size.width;
    }
    else if (0 < indicatorWidth)
        rect.size.width = MIN(indicatorWidth, rect.size.width);

    [foregroundColor set];
    CGFloat level = self.value;
    CGFloat x = rect.origin.x + level * rect.size.width;
    CGFloat y = rect.origin.y + level * rect.size.height;
    NSBezierPath *path = [NSBezierPath bezierPath];
    [path moveToPoint:rect.origin];
    [path lineToPoint:NSMakePoint(x, NSMinY(rect))];
    [path lineToPoint:NSMakePoint(x, y)];
    [path closePath];
    [path fill];
}

- (double)value
{
    return _value;
}

- (void)setValue:(double)value
{
    if (_value == value)
        return;

    _value = value;
    [self setNeedsDisplay:YES];
}

- (CGFloat)indicatorWidth
{
    return _indicatorWidth;
}

- (void)setIndicatorWidth:(CGFloat)value
{
    if (_indicatorWidth == value)
        return;

    _indicatorWidth = value;
    [self setNeedsDisplay:YES];
}

- (NSInteger)tag
{
    return _tag;
}

- (void)setTag:(NSInteger)value
{
    _tag = value;
}
@end

@interface ControlWidgetView : NSView
@end

@implementation ControlWidgetView
- (NSSize)intrinsicContentSize
{
    return [[self.subviews firstObject] intrinsicContentSize];
}

- (void)resizeSubviewsWithOldSize:(NSSize)size
{
    NSView *view = [self.subviews lastObject];
    NSRect rect = view.frame;
    rect.origin.y = (self.bounds.size.height - rect.size.height) / 2;
    view.frame = rect;
}
@end

@interface ControlWidget ()
@property (retain) ControlWidgetBrightnessBarController *brightnessBarController;
@property (retain) ControlWidgetVolumeBarController *volumeBarController;
@end

@implementation ControlWidget
{
    NSInteger _pressKind;
    CGFloat _xmin, _xmax;
}

- (void)commonInit
{
    self.brightnessBarController = [ControlWidgetBrightnessBarController controller];
    self.volumeBarController = [ControlWidgetVolumeBarController controller];

    NSPressGestureRecognizer *shortPress = [[[NSPressGestureRecognizer alloc]
        initWithTarget:self action:@selector(shortPressAction:)] autorelease];
    shortPress.allowedTouchTypes = NSTouchTypeMaskDirect;
    shortPress.minimumPressDuration = ShortPressDuration;

    NSSegmentedControl *control = [NSSegmentedControl
        segmentedControlWithImages:[NSArray arrayWithObjects:
            [self playPauseImage],
            [NSImage imageNamed:@"BrightnessUp"],
            [NSImage imageNamed:NSImageNameTouchBarAudioOutputVolumeHighTemplate],
            [self volumeMuteImage],
            nil]
        trackingMode:NSSegmentSwitchTrackingMomentary
        target:self
        action:@selector(click:)];
    control.translatesAutoresizingMaskIntoConstraints = NO;
    control.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    control.tag = 'ctrl';

    ControlWidgetLevelView *level = [[[ControlWidgetLevelView alloc]
        initWithFrame:NSMakeRect(0, 0, MaxPanDistance, 20)] autorelease];
    level.wantsLayer = YES;
    level.layer.cornerRadius = 4.0;
    level.layer.borderWidth = 1.0;
    level.layer.borderColor = [[NSColor systemGrayColor] CGColor];
    level.translatesAutoresizingMaskIntoConstraints = NO;
    level.autoresizingMask = NSViewNotSizable;
    level.value = 0.5;
    level.inset = 4;
    level.tag = 'levl';
    level.hidden = YES;

    NSView *view = [[[ControlWidgetView alloc] initWithFrame:NSZeroRect] autorelease];
    [view addGestureRecognizer:shortPress];
    [view addSubview:control];
    [view addSubview:level];

    self.customizationLabel = @"Control";
    self.view = view;

    [[NSNotificationCenter defaultCenter]
        addObserver:self
        selector:@selector(nowPlayingNotification:)
        name:NowPlayingStateNotification
        object:nil];
    [NowPlaying sharedInstance];

    [[NSNotificationCenter defaultCenter]
        addObserver:self
        selector:@selector(audioControlNotification:)
        name:AudioControlNotification
        object:nil];
    [AudioControl sharedInstance];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter]
        removeObserver:self];

    self.brightnessBarController = nil;
    self.volumeBarController = nil;

    [super dealloc];
}

- (NSImage *)playPauseImage
{
    BOOL playing = [NowPlaying sharedInstance].playing;
    return [NSImage imageNamed:playing ?
        NSImageNameTouchBarPauseTemplate : NSImageNameTouchBarPlayTemplate];
}

- (NSImage *)volumeMuteImage
{
    BOOL mute = [AudioControl sharedInstance].mute;
    return [NSImage imageNamed:mute ? @"VolumeMuteOn" : @"VolumeMuteOff"];
}

- (void)nowPlayingNotification:(NSNotification *)notification
{
    NSSegmentedControl *control = [self.view viewWithTag:'ctrl'];
    [control setImage:[self playPauseImage] forSegment:0];
}

- (void)audioControlNotification:(NSNotification *)notification
{
    NSSegmentedControl *control = [self.view viewWithTag:'ctrl'];
    [control setImage:[self volumeMuteImage] forSegment:3];
}

- (void)click:(id)sender
{
    NSSegmentedControl *control = sender;
    switch (control.selectedSegment)
    {
    case 0:
        PostAuxKeyPress(NX_KEYTYPE_PLAY);
        break;
    case 1:
        [self.brightnessBarController present];
        break;
    case 2:
        [self.volumeBarController present];
        break;
    case 3:
        [AudioControl sharedInstance].mute = ![AudioControl sharedInstance].mute;
        break;
    }
}

- (void)shortPressAction:(NSGestureRecognizer *)recognizer
{
    switch (recognizer.state)
    {
    case NSGestureRecognizerStateBegan:
        [self shortPressBegan:recognizer];
        break;
    case NSGestureRecognizerStateChanged:
        [self shortPressChanged:recognizer];
        break;
    case NSGestureRecognizerStateEnded:
    case NSGestureRecognizerStateCancelled:
        [self shortPressEnded:recognizer];
        break;
    default:
        return;
    }
}

- (void)shortPressBegan:(NSGestureRecognizer *)recognizer
{
    if (0 != _pressKind)
        return;

    NSSegmentedControl *control = [self.view viewWithTag:'ctrl'];
    ControlWidgetLevelView *level = [self.view viewWithTag:'levl'];
    NSPoint point = [recognizer locationInView:control];
    NSInteger segment = [self segmentForX:point.x];
    double value;

    switch (segment)
    {
    case 0:
        _pressKind = 'play';
        value = 0.5;
        break;
    case 1:
        _pressKind = 'brgt';
        value = GetDisplayBrightness();
        break;
    case 2:
        _pressKind = 'audi';
        value = [AudioControl sharedInstance].volume;
        break;
    default:
        return;
    }

    if (isnan(value))
        value = 0.5;
    _xmin = point.x - MaxPanDistance * value;
    _xmax = _xmin + MaxPanDistance;

    if ('play' == _pressKind)
        return;

    control.hidden = YES;
    level.hidden = NO;
    level.value = value;
}

- (void)shortPressChanged:(NSGestureRecognizer *)recognizer
{
    if (0 == _pressKind)
        return;

    NSSegmentedControl *control = [self.view viewWithTag:'ctrl'];
    ControlWidgetLevelView *level = [self.view viewWithTag:'levl'];
    NSPoint point = [recognizer locationInView:self.view];
    point.x = MAX(point.x, _xmin);
    point.x = MIN(point.x, _xmax);
    double value = (point.x - _xmin) / MaxPanDistance;

    switch (_pressKind)
    {
    case 'play':
        if (0.25 > value)
            [control setImage:[NSImage imageNamed:NSImageNameTouchBarSkipBackTemplate] forSegment:0];
        else if (0.25 <= value && value <= 0.75)
            [control setImage:[self playPauseImage] forSegment:0];
        else
            [control setImage:[NSImage imageNamed:NSImageNameTouchBarSkipAheadTemplate] forSegment:0];
        break;
    case 'brgt':
        level.value = isnan(value) ? 0.5 : value;
        SetDisplayBrightness(value);
        break;
    case 'audi':
        level.value = isnan(value) ? 0.5 : value;
        [AudioControl sharedInstance].volume = value;
        [AudioControl sharedInstance].mute = value < 1.0 / (16 * 4);
        break;
    }
}

- (void)shortPressEnded:(NSGestureRecognizer *)recognizer
{
    if (0 == _pressKind)
        return;

    NSSegmentedControl *control = [self.view viewWithTag:'ctrl'];
    ControlWidgetLevelView *level = [self.view viewWithTag:'levl'];
    NSPoint point = [recognizer locationInView:self.view];
    point.x = MAX(point.x, _xmin);
    point.x = MIN(point.x, _xmax);
    double value = (point.x - _xmin) / MaxPanDistance;

    switch (_pressKind)
    {
    case 'play':
        if (0.25 > value)
            PostAuxKeyPress(NX_KEYTYPE_PREVIOUS);
        else if (0.25 <= value && value <= 0.75)
            ;
        else
            PostAuxKeyPress(NX_KEYTYPE_NEXT);
        [control setImage:[self playPauseImage] forSegment:0];
        break;
    default:
        control.hidden = NO;
        level.hidden = YES;
        break;
    }

    _pressKind = 0;
}

- (NSInteger)segmentForX:(CGFloat)x
{
    /* HACK:
     * There does not appear to be a direct way to determine the segment from a point.
     *
     * One would think that the -[NSSegmentedControl widthForSegment:] method on the
     * first segment (which happens to be the Play/Pause button) would do the trick.
     * Unfortunately this method returns 0 for automatically sized segments. Arrrrr!
     *
     * So I am adapting here some code that I wrote a long time for "DarwinKit"...
     */
    NSSegmentedControl *control = [self.view viewWithTag:'ctrl'];
    NSRect rect = control.bounds;
    CGFloat widths[16] = { 0 }, totalWidth = 0;
    NSInteger count = control.segmentCount, zeroWidthCells = 0;
    for (NSInteger i = 0; count > i; i++)
    {
        widths[i] = [control widthForSegment:i];
        if (0 == widths[i])
            zeroWidthCells++;
        else
            totalWidth += widths[i];
    }
    if (0 < zeroWidthCells)
    {
        totalWidth = rect.size.width - totalWidth;
        for (NSInteger i = 0; count > i; i++)
            if (0 == widths[i])
                widths[i] = totalWidth / zeroWidthCells;
    }
    else
    {
        if (2 <= count)
        {
            CGFloat remWidth = rect.size.width - totalWidth;
            widths[0] += remWidth / 2;
            widths[count - 1] += remWidth / 2;
        }
        else if (1 <= count)
        {
            CGFloat remWidth = rect.size.width - totalWidth;
            widths[0] += remWidth;
        }
    }

    /* now that we have the widths go ahead and figure out which segment has X */
    totalWidth = 0;
    for (NSInteger i = 0; count > i; i++)
    {
        if (totalWidth <= x && x < totalWidth + widths[i])
            return i;

        totalWidth += widths[i];
    }

    return -1;
}
@end
