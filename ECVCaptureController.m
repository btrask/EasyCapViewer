/* Copyright (c) 2009, Ben Trask
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY BEN TRASK ''AS IS'' AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL BEN TRASK BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. */
#import "ECVCaptureController.h"

// Models
#import "ECVController.h"
#import "ECVCaptureDevice.h"
#import "ECVVideoStorage.h"
#import "ECVVideoFrame.h"
#import "ECVMovieRecorder.h"
#import "ECVFrameRateConverter.h"

// Views
#import "MPLWindow.h"
#import "ECVVideoView.h"
#import "ECVPlayButtonCell.h"
#import "ECVCropCell.h"

// Controllers
#import "ECVConfigController.h"

// Other Sources
#import "ECVAppKitAdditions.h"
#import "ECVFoundationAdditions.h"

// External
#import "BTUserDefaults.h"

static NSString *const ECVAspectRatio2Key = @"ECVAspectRatio2";
static NSString *const ECVVsyncKey = @"ECVVsync";
static NSString *const ECVMagFilterKey = @"ECVMagFilter";
static NSString *const ECVShowDroppedFramesKey = @"ECVShowDroppedFrames";
static NSString *const ECVVideoCodecKey = @"ECVVideoCodec";
static NSString *const ECVVideoQualityKey = @"ECVVideoQuality";
static NSString *const ECVCropRectKey = @"ECVCropRect";
static NSString *const ECVCropSourceAspectRatioKey = @"ECVCropSourceAspectRatio";
static NSString *const ECVCropBorderKey = @"ECVCropBorder";

static NSImage *ECVTemplateImageForInput(NSUInteger input)
{
	NSRect const r = (NSRect){NSZeroPoint, {32, 32}};
	NSImage *const result = [[[NSImage alloc] initWithSize:r.size] autorelease];
	[result lockFocus];

	NSMutableAttributedString *const str = [[[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"%lu", (unsigned long)input]] autorelease];
	[str setAttributes:[NSDictionary dictionaryWithObjectsAndKeys:
		[NSFont boldSystemFontOfSize:28.0], NSFontAttributeName,
		[NSColor blackColor], NSForegroundColorAttributeName,
		nil] range:NSMakeRange(0, [str length])];
	NSSize const s = [str size];
	[str drawAtPoint:NSMakePoint(NSMidX(r) - s.width / 2.0, NSMidY(r) - s.height / 2.0)];

	[result unlockFocus];
	return result;
}
static NSImage *ECVImageForRecording(BOOL flag)
{
	NSRect const r = (NSRect){NSZeroPoint, {32, 32}};
	NSImage *const result = [[[NSImage alloc] initWithSize:r.size] autorelease];
	[result lockFocus];
	[NSGraphicsContext saveGraphicsState];
	NSShadow *const shadow = [[[NSShadow alloc] init] autorelease];
	[shadow setShadowColor:[NSColor colorWithDeviceWhite:1.0 alpha:0.67]];
	[shadow setShadowOffset:NSMakeSize(0, -1)];
	[shadow setShadowBlurRadius:1.0];
	[shadow set];
	CGContextRef const context = [[NSGraphicsContext currentContext] graphicsPort];
	CGContextBeginTransparencyLayer(context, NULL);

	if(flag) [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(6.0, 6.0, 20.0, 20.0)] ECV_fillWithGradientFromColor:[NSColor colorWithDeviceHue:0.0 saturation:0.6 brightness:1.0 alpha:1.0] atPoint:NSMakePoint(0, NSMaxY(r)) toColor:[NSColor colorWithDeviceHue:0.0 saturation:1.0 brightness:0.9 alpha:1.0] atPoint:NSMakePoint(0, NSMinY(r))];
	else [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(6.0, 6.0, 20.0, 20.0)] ECV_fillWithGradientFromColor:[NSColor colorWithDeviceWhite:0.35 alpha:1.0] atPoint:NSMakePoint(0, NSMaxY(r)) toColor:[NSColor colorWithDeviceWhite:0.1 alpha:1.0] atPoint:NSMakePoint(0, NSMinY(r))];

	CGContextEndTransparencyLayer(context);
	[NSGraphicsContext restoreGraphicsState];
	[result unlockFocus];
	return result;
}
static NSImage *ECVGearTemplateImage()
{
	NSRect const r = (NSRect){NSZeroPoint, {32, 32}};
	NSImage *const result = [[[NSImage alloc] initWithSize:r.size] autorelease];
	[result lockFocus];

	[[NSColor blackColor] set];

	NSUInteger const teeth = 12;
	CGFloat const revolution = 360.0;
	CGFloat const pitch = revolution / teeth;
	CGFloat const top = pitch / 3.0;
	CGFloat const bottom = pitch / 3.0;
	CGFloat const face = (pitch - (top + bottom)) / 2.0;
	CGFloat const outsideRadius = 12.0;
	CGFloat const rootRadius = 10.0;
	NSPoint const center = NSMakePoint(NSMidX(r), NSMidY(r));

	NSUInteger tooth;
	NSBezierPath *const path = [NSBezierPath bezierPath];
	for(tooth = 0; tooth < teeth; ++tooth) {
		CGFloat const start = pitch * tooth - top / 2.0;
		[path ECV_appendArcWithCenter:center radius:outsideRadius start:start end:start + top clockwise:YES];
		[path ECV_appendArcWithCenter:center radius:rootRadius start:start + top + face end:start + top + face + bottom clockwise:YES];
	}
	[path closePath];
	[path appendBezierPathWithArcWithCenter:center radius:5.0 startAngle:0.0 endAngle:revolution clockwise:NO];
	[path setWindingRule:NSEvenOddWindingRule];
	[path fill];

	[result unlockFocus];
	return result;
}
static NSImage *ECVToolbarImageFromTemplate(NSImage *templateImage)
{
	if(!templateImage) return nil;
	NSRect const r = (NSRect){NSZeroPoint, {32, 32}};
	NSImage *const result = [[[NSImage alloc] initWithSize:r.size] autorelease];
	[result lockFocus];
	[NSGraphicsContext saveGraphicsState];
	NSShadow *const shadow = [[[NSShadow alloc] init] autorelease];
	[shadow setShadowColor:[NSColor colorWithDeviceWhite:1.0 alpha:0.67]];
	[shadow setShadowOffset:NSMakeSize(0, -1)];
	[shadow setShadowBlurRadius:1.0];
	[shadow set];
	CGContextRef const context = [[NSGraphicsContext currentContext] graphicsPort];
	CGContextBeginTransparencyLayer(context, NULL);

	[[NSBezierPath bezierPathWithRect:r] ECV_fillWithGradientFromColor:[NSColor colorWithDeviceWhite:0.35 alpha:1.0] atPoint:NSMakePoint(0, NSMaxY(r)) toColor:[NSColor colorWithDeviceWhite:0.1 alpha:1.0] atPoint:NSMakePoint(0, NSMinY(r))];
	[templateImage drawInRect:r fromRect:NSZeroRect operation:NSCompositeDestinationIn fraction:1.0];

	CGContextEndTransparencyLayer(context);
	[NSGraphicsContext restoreGraphicsState];
	[result unlockFocus];
	return result;
}

@interface ECVCaptureController(Private)

- (void)_hideMenuBar;
- (void)_updateCropRect;
- (void)_rebuildAudioInputMenuForPopUpButton:(NSPopUpButton *)popup;

@end

@implementation ECVCaptureController

#pragma mark -ECVCaptureController

- (IBAction)cloneViewer:(id)sender
{
	ECVCaptureController *const controller = [[[[self class] alloc] init] autorelease];
	[[self document] addWindowController:controller];
	[controller showWindow:sender];
	if([[self document] isPlaying]) [controller startPlaying];
}

#pragma mark -

- (IBAction)play:(id)sender
{
	[[self document] setPlaying:YES];
}
- (IBAction)pause:(id)sender
{
	[[self document] setPlaying:NO];
}
- (IBAction)togglePlaying:(id)sender
{
	[[self document] togglePlaying];
}

#pragma mark -

- (IBAction)startRecording:(id)sender
{
#if __LP64__
	NSAlert *const alert = [[[NSAlert alloc] init] autorelease];
	[alert setMessageText:NSLocalizedString(@"Recording is not supported in 64-bit mode.", nil)];
	[alert setInformativeText:NSLocalizedString(@"Relaunch RTC ToolView in 32-bit mode to record.", nil)];
	[alert addButtonWithTitle:NSLocalizedString(@"OK", nil)];
	[alert runModal];
#else
	if(_movieRecorder) return;

	NSSavePanel *const savePanel = [NSSavePanel savePanel];
	[savePanel setAllowedFileTypes:[NSArray arrayWithObject:@"mov"]];
	[savePanel setCanCreateDirectories:YES];
	[savePanel setCanSelectHiddenExtension:YES];
	[savePanel setPrompt:NSLocalizedString(@"Record", nil)];
	[savePanel setAccessoryView:exportAccessoryView];

	[videoCodecPopUp removeAllItems];
	NSArray *const videoCodecs = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"ECVVideoCodecs"];
	NSDictionary *const infoByVideoCodec = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"ECVInfoByVideoCodec"];
	for(NSString *const codec in videoCodecs) {
		NSDictionary *const codecInfo = [infoByVideoCodec objectForKey:codec];
		if(!codecInfo) continue;
		NSMenuItem *const item = [[[NSMenuItem alloc] initWithTitle:[codecInfo objectForKey:@"ECVCodecLabel"] action:NULL keyEquivalent:@""] autorelease];
		[item setTag:(NSInteger)NSHFSTypeCodeFromFileType(codec)];
		[[videoCodecPopUp menu] addItem:item];
	}
	(void)[videoCodecPopUp selectItemWithTag:NSHFSTypeCodeFromFileType([[self defaults] objectForKey:ECVVideoCodecKey])];
	[self changeCodec:videoCodecPopUp];
	[videoQualitySlider setDoubleValue:[[self defaults] doubleForKey:ECVVideoQualityKey]];

	NSInteger const returnCode = [savePanel runModalForDirectory:nil file:NSLocalizedString(@"untitled", nil)];
	[[self defaults] setObject:[NSNumber numberWithDouble:[videoQualitySlider doubleValue]] forKey:ECVVideoQualityKey];
	if(NSFileHandlingPanelOKButton != returnCode) return;

	ECVMovieRecordingOptions *const options = [[[ECVMovieRecordingOptions alloc] init] autorelease];
	[options setURL:[savePanel URL]];
	[options setVideoStorage:[(ECVCaptureDevice *)[self document] videoStorage]];
	[options setAudioDevice:[[self document] audioInput]];

	[options setVideoCodec:(OSType)[videoCodecPopUp selectedTag]];
	[options setVideoQuality:[videoQualitySlider doubleValue]];
	[options setStretchOutput:NSOnState == [stretchTotAspectRatio state]];
	[options setOutputSize:ECVIntegerSizeFromNSSize([self outputSize])];
	[options setCropRect:[self cropRect]];
	[options setUpconvertsFromMono:[[self document] upconvertsFromMono]];
	[options setRecordsToRAM:NSOnState == [recordToRAMButton state]];

	ECVRational const frameRateRatio = ECVMakeRational(1, NSOnState == [halfFrameRate state] ? 2 : 1);
	[options setFrameRate:[ECVFrameRateConverter frameRateWithRatio:frameRateRatio ofFrameRate:[[options videoStorage] frameRate]]];

	NSError *error = nil;
	ECVMovieRecorder *const recorder = [[[ECVMovieRecorder alloc] initWithOptions:options error:&error] autorelease];
	if(recorder) {
		@synchronized(self) {
			_movieRecorder = [recorder retain];
		}
		[[self window] setDocumentEdited:YES];
	} else [[NSAlert alertWithError:error] runModal];
#endif
}
- (IBAction)stopRecording:(id)sender
{
#if !__LP64__
	if(!_movieRecorder) return;
	[_movieRecorder stopRecording];
	@synchronized(self) {
		[_movieRecorder release];
		_movieRecorder = nil;
	}
	[[self window] setDocumentEdited:NO];
#endif
}
- (IBAction)changeCodec:(id)sender
{
	NSString *const codec = NSFileTypeForHFSTypeCode((OSType)[sender selectedTag]);
	[[self defaults] setObject:codec forKey:ECVVideoCodecKey];
	NSNumber *const configurableQuality = [[[[NSBundle mainBundle] objectForInfoDictionaryKey:@"ECVInfoByVideoCodec"] objectForKey:codec] objectForKey:@"ECVConfigurableQuality"];
	[videoQualitySlider setEnabled:configurableQuality && [configurableQuality boolValue]];
}
- (IBAction)showRecordsToRAMInfo:(id)sender
{
	NSAlert *const alert = [[NSAlert alloc] init];
	[alert setMessageText:NSLocalizedString(@"Recording to RAM can enhance performance, but can also lead to performance degradation if used improperly.", nil)];
	[alert setInformativeText:NSLocalizedString(@"Movies recorded to RAM are limited to 2GB in size. Make sure you have enough available RAM to store the entire movie.", nil)];
	[[alert addButtonWithTitle:NSLocalizedString(@"OK", nil)] setKeyEquivalent:@"\r"];
	[alert beginSheetModalForWindow:[sender window] modalDelegate:nil didEndSelector:NULL contextInfo:NULL];
}
- (IBAction)toggleRecording:(id)sender
{
	if(_movieRecorder) [self stopRecording:sender];
	else [self startRecording:sender];
}

#pragma mark -

- (IBAction)toggleFullScreen:(id)sender
{
	[self setFullScreen:![self isFullScreen]];
}
- (IBAction)toggleFloatOnTop:(id)sender
{
	[[self window] setLevel:[[self window] level] == NSFloatingWindowLevel ? NSNormalWindowLevel : NSFloatingWindowLevel];
}
- (IBAction)changeScale:(id)sender
{
	[self setWindowContentSize:[self outputSizeWithScale:[sender tag]]];
}
- (IBAction)changeAspectRatio:(id)sender
{
	[self setAspectRatio:[self sizeWithAspectRatio:[sender tag]]];
	[[self defaults] setObject:[NSNumber numberWithUnsignedInteger:[sender tag]] forKey:ECVAspectRatio2Key];
}

#pragma mark -

- (IBAction)uncrop:(id)sender
{
	_cropSourceAspectRatio = ECVAspectRatioUnknown;
	_cropBorder = ECVCropBorderNone;
	[self _updateCropRect];
}
- (IBAction)changeCropSourceAspectRatio:(id)sender
{
	_cropSourceAspectRatio = [sender tag];
	if(ECVCropBorderCustom == _cropBorder) _cropBorder = ECVCropBorderNone;
	[self _updateCropRect];
}
- (IBAction)changeCropBorder:(id)sender
{
	_cropBorder = [sender tag];
	[self _updateCropRect];
}
- (IBAction)enterCustomCropMode:(id)sender
{
	ECVCropCell *const cell = [[[ECVCropCell alloc] initWithOpenGLContext:[videoView openGLContext]] autorelease];
	[cell setDelegate:self];
	[cell setCropRect:[self cropRect]];
	[videoView setCropRect:ECVUncroppedRect];
	[videoView setCell:cell];
}

#pragma mark -

- (IBAction)toggleVsync:(id)sender
{
	[videoView setVsync:![videoView vsync]];
	[[self defaults] setBool:[videoView vsync] forKey:ECVVsyncKey];
}
- (IBAction)toggleSmoothing:(id)sender
{
	switch([videoView magFilter]) {
		case GL_NEAREST: [videoView setMagFilter:GL_LINEAR]; break;
		case GL_LINEAR: [videoView setMagFilter:GL_NEAREST]; break;
	}
	[[self defaults] setInteger:[videoView magFilter] forKey:ECVMagFilterKey];
}
- (IBAction)toggleShowDroppedFrames:(id)sender
{
	[videoView setShowDroppedFrames:![videoView showDroppedFrames]];
	[[self defaults] setBool:[videoView showDroppedFrames] forKey:ECVShowDroppedFramesKey];
}

#pragma mark -

- (IBAction)changeVideoSource:(id)sender
{
	[[self document] setVideoSourceObject:[[[self document] allVideoSourceObjects] objectAtIndex:[sender tag]]];
}
- (IBAction)changeAudioSource:(id)sender
{
	[[self document] setAudioInput:[[sender selectedItem] representedObject]];
}

#pragma mark -

- (BTUserDefaults *)defaults
{
	return [(ECVCaptureDevice *)[self document] defaults];
}
- (NSSize)aspectRatio
{
	return [videoView aspectRatio];
}
- (void)setAspectRatio:(NSSize)ratio
{
	[videoView setAspectRatio:ratio];
	[[self window] setContentAspectRatio:ratio];
	CGFloat const r = ratio.height / ratio.width;
	NSSize s = [self windowContentSize];
	s.height = s.width * r;
	[self setWindowContentSize:s];
	[[self window] setMinSize:NSMakeSize(200.0f, 200.0f * r)];
	[self _updateCropRect];
}
- (NSRect)cropRect
{
	return [[videoView cell] respondsToSelector:@selector(cropRect)] ? [(ECVCropCell *)[videoView cell] cropRect] : [videoView cropRect];
}
@synthesize fullScreen = _fullScreen;
- (void)setFullScreen:(BOOL)flag
{
	if(flag == _fullScreen) return;
	_fullScreen = flag;
	NSDisableScreenUpdates();
	NSUInteger styleMask = NSBorderlessWindowMask;
	NSRect frame = NSZeroRect;
	if(flag) {
		NSArray *const screens = [NSScreen screens];
		if([screens count]) frame = [[screens objectAtIndex:0] frame];
	} else {
		styleMask = NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask;
		frame = (NSRect){{100, 100}, [self outputSize]};
	}
	NSWindow *const oldWindow = [self window];
	NSWindow *const w = [[[MPLWindow alloc] initWithContentRect:frame styleMask:styleMask backing:NSBackingStoreBuffered defer:YES] autorelease];
	NSView *const contentView = [[[oldWindow contentView] retain] autorelease];
	[oldWindow setContentView:nil];
	[w setContentView:contentView];
	[w setDelegate:self];
	[w setLevel:[oldWindow level]];
	[w setContentAspectRatio:[oldWindow contentAspectRatio]];
	[w setMinSize:[oldWindow minSize]];

	NSToolbar *const toolbar = [[[NSToolbar alloc] initWithIdentifier:@"ECVToolbar"] autorelease];
	[toolbar setDelegate:self];
	[w setToolbar:toolbar];
	[w setShowsToolbarButton:NO];

	[self setWindow:w];
	[self synchronizeWindowTitleWithDocumentName];
	[w setDocumentEdited:[oldWindow isDocumentEdited]];
	[w makeKeyAndOrderFront:self];
	[oldWindow close];
	if(!flag) [w center];
	[self videoSourceDidChange:nil];
	NSEnableScreenUpdates();
}
- (NSSize)windowContentSize
{
	NSWindow *const w = [self window];
	return [w contentRectForFrameRect:[w frame]].size;
}
- (void)setWindowContentSize:(NSSize)size
{
	if([self isFullScreen] || ![self isWindowLoaded]) return;
	NSWindow *const w = [self window];
	NSRect f = [w contentRectForFrameRect:[w frame]];
	f.origin.y += NSHeight(f) - size.height;
	f.size = size;
	[w setFrame:[w frameRectForContentRect:f] display:YES];
}
- (NSSize)outputSize
{
	NSSize const ratio = [videoView aspectRatio];
	ECVIntegerSize const s = [[self document] captureSize];
	return NSMakeSize(s.width, s.width / ratio.width * ratio.height);
}
- (NSSize)outputSizeWithScale:(NSInteger)scale
{
	NSSize const s = [self outputSize];
	CGFloat const factor = powf(2, (CGFloat)scale);
	return NSMakeSize(s.width * factor, s.height * factor);
}
- (NSSize)sizeWithAspectRatio:(ECVAspectRatio)ratio
{
	switch(ratio) {
		case ECVAspectRatio1x1:   return NSMakeSize( 1.0f,  1.0f);
		case ECVAspectRatio4x3:   return NSMakeSize( 4.0f,  3.0f);
		case ECVAspectRatio3x2:   return NSMakeSize( 3.0f,  2.0f);
		case ECVAspectRatio16x10: return NSMakeSize(16.0f, 10.0f);
		case ECVAspectRatio16x9:  return NSMakeSize(16.0f,  9.0f);
	}
	return NSZeroSize;
}
- (NSRect)cropRectWithSourceAspectRatio:(ECVAspectRatio)type
{
	if(ECVAspectRatioUnknown == type) return ECVUncroppedRect;
	NSSize const src = [self sizeWithAspectRatio:type];
	NSSize const dst = [self aspectRatio];
	CGFloat const correction = (dst.height / dst.width) / (src.height / src.width);
	return correction < 1.0f ? NSMakeRect(0.0f, (1.0f - correction) / 2.0f, 1.0f, correction) : NSMakeRect((1.0f - (1.0f / correction)) / 2.0f, 0.0f, 1.0f / correction, 1.0f);
}
- (NSRect)cropRect:(NSRect)r withBorder:(ECVCropBorder)border
{
	CGFloat b = 0.0f;
	switch(border) {
		case ECVCropBorder2_5Percent: b = 0.025f; break;
		case ECVCropBorder5Percent: b = 0.05f; break;
		case ECVCropBorder10Percent: b = 0.1f; break;
	}
	CGFloat const b2 = 1.0f - b * 2.0f;
	return NSMakeRect(NSMinX(r) + NSWidth(r) * b, NSMinY(r) + NSHeight(r) * b, NSWidth(r) * b2, NSHeight(r) * b2);
}

#pragma mark -

- (void)startPlaying
{
	[videoView setVideoStorage:[[self document] videoStorage]];
	[videoView startDrawing];
}
- (void)stopPlaying
{
	[videoView stopDrawing];
	[self stopRecording:self];
}
- (void)threaded_pushFrame:(ECVVideoFrame *)frame
{
	[videoView pushFrame:frame];
	if(_movieRecorder) @synchronized(self) {
		[_movieRecorder addVideoFrame:frame];
	}
}
- (void)threaded_pushAudioBufferListValue:(NSValue *)bufferListValue
{
	if(_movieRecorder) @synchronized(self) {
		[_movieRecorder addAudioBufferList:[bufferListValue pointerValue]];
	}
}

#pragma mark -

- (void)audioHardwareDevicesDidChange:(NSNotification *)aNotif
{
	if(![self isWindowLoaded]) return;
	for(NSToolbarItem *const toolbarItem in [[[self window] toolbar] items]) {
		if(!ECVEqualObjects([toolbarItem itemIdentifier], @"")) continue;
		[self _rebuildAudioInputMenuForPopUpButton:(NSPopUpButton *)[toolbarItem view]];
	}
}
- (void)videoSourceDidChange:(NSNotification *)aNotif
{
	if(![self isWindowLoaded]) return;
	NSUInteger const i = [[[self document] allVideoSourceObjects] indexOfObject:[[self document] videoSourceObject]];
	if(NSNotFound == i) return;
	[[[self window] toolbar] setSelectedItemIdentifier:[NSString stringWithFormat:@"ECVToolbarVideoSourceItem-%lu", (unsigned long)i]];
}

#pragma mark -ECVCaptureController(Private)

- (void)_hideMenuBar
{
#if __LP64__
	[NSApp setPresentationOptions:NSApplicationPresentationAutoHideMenuBar | NSApplicationPresentationAutoHideDock];
#else
	SetSystemUIMode(kUIModeAllSuppressed, kNilOptions);
#endif
}
- (void)_updateCropRect
{
	if(ECVCropBorderCustom != _cropBorder) {
		BOOL const hasCropCell = [[videoView cell] respondsToSelector:@selector(setCropRect:)];
		[hasCropCell ? (id)[videoView cell] : (id)videoView setCropRect:[self cropRect:[self cropRectWithSourceAspectRatio:_cropSourceAspectRatio] withBorder:_cropBorder]];
		if(hasCropCell) {
			[videoView setNeedsDisplay:YES];
			[[self window] invalidateCursorRectsForView:videoView];
		}
	}
	[[self defaults] setInteger:_cropSourceAspectRatio forKey:ECVCropSourceAspectRatioKey];
	[[self defaults] setInteger:_cropBorder forKey:ECVCropBorderKey];
}
- (void)_rebuildAudioInputMenuForPopUpButton:(NSPopUpButton *)popup
{
	[popup removeAllItems];
	ECVAudioDevice *const preferredInput = [[self document] audioInputOfCaptureHardware];
	if(preferredInput) {
		NSMenuItem *const item = [[[NSMenuItem alloc] initWithTitle:[preferredInput name] action:NULL keyEquivalent:@""] autorelease];
		[item setRepresentedObject:preferredInput];
		[[popup menu] addItem:item];
	}
	for(ECVAudioDevice *const device in [ECVAudioDevice allDevicesInput:YES]) {
		if(ECVEqualObjects(device, preferredInput)) continue;
		NSMenuItem *const item = [[[NSMenuItem alloc] initWithTitle:[device name] action:NULL keyEquivalent:@""] autorelease];
		[item setRepresentedObject:device];
		[[popup menu] addItem:item];
	}
	if([[popup menu] numberOfItems] > 1) [[popup menu] insertItem:[NSMenuItem separatorItem] atIndex:1];
	[popup setEnabled:!![[popup menu] numberOfItems]];

	NSMenuItem *const labelItem = [[[NSMenuItem alloc] initWithTitle:@"" action:NULL keyEquivalent:@""] autorelease];
	[labelItem setImage:ECVToolbarImageFromTemplate([NSImage imageNamed:@"Microphone"])];
	[[popup menu] insertItem:labelItem atIndex:0];
}

#pragma mark -NSWindowController

- (void)setDocument:(NSDocument *)doc
{
	[[self document] ECV_removeObserver:self name:ECVCaptureDeviceVideoSourceDidChangeNotification];
	[super setDocument:doc];
	[[self document] ECV_addObserver:self selector:@selector(videoSourceDidChange:) name:ECVCaptureDeviceVideoSourceDidChangeNotification];
}
- (void)windowDidLoad
{
	[[self defaults] registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithUnsignedInteger:ECVAspectRatio4x3], ECVAspectRatio2Key,
		[NSNumber numberWithBool:NO], ECVVsyncKey,
		[NSNumber numberWithInteger:GL_LINEAR], ECVMagFilterKey,
		[NSNumber numberWithBool:NO], ECVShowDroppedFramesKey,
		NSFileTypeForHFSTypeCode(kJPEGCodecType), ECVVideoCodecKey,
		[NSNumber numberWithDouble:0.5f], ECVVideoQualityKey,
		NSStringFromRect(ECVUncroppedRect), ECVCropRectKey,
		[NSNumber numberWithInteger:ECVAspectRatioUnknown], ECVCropSourceAspectRatioKey,
		[NSNumber numberWithInteger:ECVCropBorderNone], ECVCropBorderKey,
		nil]];

	NSWindow *const w = [self window];
	ECVIntegerSize const s = [[self document] captureSize];
	[w setFrame:[w frameRectForContentRect:NSMakeRect(0.0f, 0.0f, s.width, s.height)] display:NO];

	_cropSourceAspectRatio = [[self defaults] integerForKey:ECVCropSourceAspectRatioKey];
	_cropBorder = [[self defaults] integerForKey:ECVCropBorderKey];
	[videoView setCropRect:NSRectFromString([[self defaults] objectForKey:ECVCropRectKey])];
	[self _updateCropRect];

	[self setAspectRatio:[self sizeWithAspectRatio:[[[self defaults] objectForKey:ECVAspectRatio2Key] unsignedIntegerValue]]];

	[videoView setVsync:[[self defaults] boolForKey:ECVVsyncKey]];
	[videoView setShowDroppedFrames:[[self defaults] boolForKey:ECVShowDroppedFramesKey]];
	[videoView setMagFilter:[[self defaults] integerForKey:ECVMagFilterKey]];

	_playButtonCell = [[ECVPlayButtonCell alloc] initWithOpenGLContext:[videoView openGLContext]];
	[_playButtonCell setTarget:self];
	[_playButtonCell setAction:@selector(togglePlaying:)];
	[videoView setCell:_playButtonCell];

	[self videoSourceDidChange:nil];

	[[ECVAudioDevice class] ECV_addObserver:self selector:@selector(audioHardwareDevicesDidChange:) name:ECVAudioHardwareDevicesDidChangeNotification];

	[w center];
	[super windowDidLoad];
}
- (void)setDocumentEdited:(BOOL)flag {} // We keep track of recording, not the document.

#pragma mark -NSObject

- (id)init
{
	return [self initWithWindowNibName:@"ECVCapture"];
}
- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[_playButtonCell release];
	[_movieRecorder release];
	[super dealloc];
}

#pragma mark -NSObject(NSMenuValidation)

- (BOOL)validateMenuItem:(NSMenuItem *)anItem
{
	SEL const action = [anItem action];
	if(@selector(toggleFullScreen:) == action) [anItem setTitle:[self isFullScreen] ? NSLocalizedString(@"Exit Full Screen", nil) : NSLocalizedString(@"Enter Full Screen", nil)];
	if(@selector(togglePlaying:) == action) [anItem setTitle:[[self document] isPlaying] ? NSLocalizedString(@"Pause", nil) : NSLocalizedString(@"Play", nil)];
	if(@selector(changeScale:) == action) [anItem setState:!!NSEqualSizes([self windowContentSize], [self outputSizeWithScale:[anItem tag]])];
	if(@selector(changeAspectRatio:) == action) {
		NSSize const s1 = [self sizeWithAspectRatio:[anItem tag]];
		NSSize const s2 = [videoView aspectRatio];
		[anItem setState:s1.width / s1.height == s2.width / s2.height];
	}

	if(@selector(uncrop:) == action) [anItem setState:ECVAspectRatioUnknown == _cropSourceAspectRatio && ECVCropBorderNone == _cropBorder];
	if(@selector(changeCropBorder:) == action) [anItem setState:[anItem tag] == _cropBorder];
	if(@selector(changeCropSourceAspectRatio:) == action) [anItem setState:[anItem tag] == _cropSourceAspectRatio && ECVCropBorderCustom != _cropBorder];
	if(@selector(enterCustomCropMode:) == action) [anItem setState:ECVCropBorderCustom == _cropBorder];

	if(@selector(toggleFloatOnTop:) == action) [anItem setTitle:[[self window] level] == NSFloatingWindowLevel ? NSLocalizedString(@"Turn Floating Off", nil) : NSLocalizedString(@"Turn Floating On", nil)];
	if(@selector(toggleVsync:) == action) [anItem setTitle:[videoView vsync] ? NSLocalizedString(@"Turn V-Sync Off", nil) : NSLocalizedString(@"Turn V-Sync On", nil)];
	if(@selector(toggleSmoothing:) == action) [anItem setTitle:GL_LINEAR == [videoView magFilter] ? NSLocalizedString(@"Turn Smoothing Off", nil) : NSLocalizedString(@"Turn Smoothing On", nil)];
	if(@selector(toggleShowDroppedFrames:) == action) [anItem setTitle:[videoView showDroppedFrames] ? NSLocalizedString(@"Hide Dropped Frames", nil) : NSLocalizedString(@"Show Dropped Frames", nil)];

	if([self isFullScreen]) {
		if(@selector(changeScale:) == action) return NO;
	}
	if(_movieRecorder) {
		if(@selector(startRecording:) == action) return NO;
	} else {
		if(@selector(stopRecording:) == action) return NO;
	}
	if(![[self document] isPlaying]) {
		if(@selector(startRecording:) == action) return NO;
	}
	return [self respondsToSelector:action];
}

#pragma mark -NSObject(NSToolbarItemValidation)

- (BOOL)validateToolbarItem:(NSToolbarItem *)item
{
	SEL const action = [item action];
	if(@selector(toggleRecording:) == action) {
		[item setLabel:NSLocalizedString(_movieRecorder ? @"Stop" : @"Record", nil)];
		[item setImage:ECVImageForRecording(!!_movieRecorder)];
		if(![[self document] isPlaying]) return NO;
	}
	return [self respondsToSelector:action];
}

#pragma mark -<ECVCropCellDelegate>

- (void)cropCellDidFinishCropping:(ECVCropCell *)sender
{
	[videoView setCropRect:[sender cropRect]];
	[videoView setCell:_playButtonCell];
	[[self defaults] setObject:NSStringFromRect([sender cropRect]) forKey:ECVCropRectKey];
	_cropSourceAspectRatio = ECVAspectRatioUnknown;
	_cropBorder = ECVCropBorderCustom;
	[self _updateCropRect];
}

#pragma mark -<ECVVideoViewDelegate>

- (BOOL)videoView:(ECVVideoView *)sender handleKeyDown:(NSEvent *)anEvent
{
	NSString *const characters = [anEvent charactersIgnoringModifiers];
	if(![characters length]) return NO;
	unichar const character = [characters characterAtIndex:0];
	NSUInteger const modifiers = [anEvent modifierFlags] & (NSCommandKeyMask | NSShiftKeyMask | NSAlternateKeyMask | NSControlKeyMask);
	switch(character) {
		case ' ':
			[self togglePlaying:self];
			return YES;
	}
#if defined(ECV_ENABLE_AUDIO)
	if(NSCommandKeyMask == modifiers) switch(character) {
		case NSUpArrowFunctionKey:
			[[self document] setVolume:[[self document] volume] + 0.05f];
			return YES;
		case NSDownArrowFunctionKey:
			[[self document] setVolume:[[self document] volume] - 0.05f];
			return YES;
	}
	if((NSCommandKeyMask | NSAlternateKeyMask) == modifiers) switch(character) {
		case NSUpArrowFunctionKey:
		case NSDownArrowFunctionKey:
			[[self document] setMuted:![[self document] isMuted]];
			return YES;
	}
#endif
	return NO;
}

#pragma mark -<NSToolbarDelegate>

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)ident willBeInsertedIntoToolbar:(BOOL)flag
{
	NSArray *const systemIdentifiers = [NSArray arrayWithObjects:NSToolbarSeparatorItemIdentifier, NSToolbarSpaceItemIdentifier, NSToolbarFlexibleSpaceItemIdentifier, nil];
	if([systemIdentifiers containsObject:ident]) return [[[NSToolbarItem alloc] initWithItemIdentifier:ident] autorelease];

	NSToolbarItem *const item = [[[NSToolbarItem alloc] initWithItemIdentifier:ident] autorelease];
	[item setTarget:self];
	if(ECVEqualObjects(ident, @"ECVToolbarVideoSourceItem-0")) {
		[item setLabel:NSLocalizedString(@"Channel", nil)];
		[item setImage:ECVToolbarImageFromTemplate(ECVTemplateImageForInput(1))];
		[item setAction:@selector(changeVideoSource:)];
		[item setTag:0];
	} else if(ECVEqualObjects(ident, @"ECVToolbarVideoSourceItem-1")) {
		[item setLabel:NSLocalizedString(@"Channel", nil)];
		[item setImage:ECVToolbarImageFromTemplate(ECVTemplateImageForInput(2))];
		[item setAction:@selector(changeVideoSource:)];
		[item setTag:1];
	} else if(ECVEqualObjects(ident, @"ECVToolbarVideoSourceItem-2")) {
		[item setLabel:NSLocalizedString(@"Channel", nil)];
		[item setImage:ECVToolbarImageFromTemplate(ECVTemplateImageForInput(3))];
		[item setAction:@selector(changeVideoSource:)];
		[item setTag:2];
	} else if(ECVEqualObjects(ident, @"ECVToolbarVideoSourceItem-3")) {
		[item setLabel:NSLocalizedString(@"Channel", nil)];
		[item setImage:ECVToolbarImageFromTemplate(ECVTemplateImageForInput(4))];
		[item setAction:@selector(changeVideoSource:)];
		[item setTag:3];
	} else if(ECVEqualObjects(ident, @"ECVToolbarAudioInputItem")) {
		NSPopUpButton *const popup = [[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:YES] autorelease];
		[[popup cell] setArrowPosition:NSPopUpArrowAtBottom];
		[popup setBezelStyle:NSShadowlessSquareBezelStyle];
		[popup setImagePosition:NSImageRight];
		[popup setBordered:NO];
		[popup setTarget:self];
		[popup setAction:@selector(changeAudioSource:)];
		[self _rebuildAudioInputMenuForPopUpButton:popup];

		[item setLabel:NSLocalizedString(@"Audio", nil)];
		[item setMinSize:NSMakeSize(49, 32)];
		[item setMaxSize:NSMakeSize(49, 32)];
		[item setView:popup];
	} else if(ECVEqualObjects(ident, @"ECVToolbarToggleRecordingItem")) {
		[item setAction:@selector(toggleRecording:)];
		[self validateToolbarItem:item];
	} else if(ECVEqualObjects(ident, @"ECVToolbarConfigureDeviceItem")) {
		[item setLabel:NSLocalizedString(@"Configure", nil)];
		[item setImage:ECVToolbarImageFromTemplate(ECVGearTemplateImage())];
		[item setTarget:[ECVController sharedController]];
		[item setAction:@selector(configureDevice:)];
	} else if(ECVEqualObjects(ident, @"ECVToolbarAboutItem")) {
		[item setLabel:NSLocalizedString(@"About", nil)];
		[item setImage:ECVToolbarImageFromTemplate([NSImage imageNamed:@"RTC-Small"])];
		[item setTarget:NSApp];
		[item setAction:@selector(orderFrontStandardAboutPanel:)];
	}
	return item;
}
- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar*)toolbar
{
	return [NSArray arrayWithObjects:
		@"ECVToolbarVideoSourceItem-0",
		@"ECVToolbarVideoSourceItem-1",
		@"ECVToolbarVideoSourceItem-2",
		@"ECVToolbarVideoSourceItem-3",
		NSToolbarSeparatorItemIdentifier,
		@"ECVToolbarAudioInputItem",
		NSToolbarFlexibleSpaceItemIdentifier,
		@"ECVToolbarToggleRecordingItem",
		NSToolbarSeparatorItemIdentifier,
		@"ECVToolbarConfigureDeviceItem",
		@"ECVToolbarAboutItem",
		nil];
}
- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar*)toolbar
{
	return [self toolbarDefaultItemIdentifiers:toolbar];
}
- (NSArray *)toolbarSelectableItemIdentifiers:(NSToolbar *)toolbar
{
	return [NSArray arrayWithObjects:
		@"ECVToolbarVideoSourceItem-0",
		@"ECVToolbarVideoSourceItem-1",
		@"ECVToolbarVideoSourceItem-2",
		@"ECVToolbarVideoSourceItem-3",
		nil];
}

#pragma mark -<NSWindowDelegate>

- (void)windowDidBecomeMain:(NSNotification *)aNotif
{
	if([self isFullScreen]) [self performSelector:@selector(_hideMenuBar) withObject:nil afterDelay:0.0f inModes:[NSArray arrayWithObject:(NSString *)kCFRunLoopCommonModes]];
	[[ECVConfigController sharedConfigController] setCaptureDevice:[self document]];
}
- (void)windowDidResignMain:(NSNotification *)aNotif
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_hideMenuBar) object:nil];
#if __LP64__
	[NSApp setPresentationOptions:NSApplicationPresentationDefault];
#else
	SetSystemUIMode(kUIModeNormal, kNilOptions);
#endif
}
- (void)windowWillClose:(NSNotification *)aNotif
{
	if([aNotif object] == [self window]) [self stopRecording:self];
}

@end
