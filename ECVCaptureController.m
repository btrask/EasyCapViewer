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
#pragma GCC diagnostic ignored "-Wobjc-method-access"

#import "ECVCaptureController.h"

#import <Foundation/NSHFSFileTypes.h>

// Models
#import "ECVCaptureDocument.h"
#import "ECVCaptureDevice.h"
#import "ECVVideoFormat.h"
#import "ECVVideoStorage.h"
#import "ECVVideoFrame.h"
#import "ECVMovieRecorder.h"
#import "ECVFrameRateConverter.h"
#import "ECVAudioTarget.h"

// Views
#import "MPLWindow.h"
#import "ECVVideoView.h"
#import "ECVPlayButtonCell.h"
#import "ECVCropCell.h"

// Controllers
#import "ECVConfigController.h"

static NSString *const ECVAspectRatio2Key = @"ECVAspectRatio2";
static NSString *const ECVVsyncKey = @"ECVVsync";
static NSString *const ECVMagFilterKey = @"ECVMagFilter";
static NSString *const ECVShowDroppedFramesKey = @"ECVShowDroppedFrames";
static NSString *const ECVVideoCodecKey = @"ECVVideoCodec";
static NSString *const ECVVideoQualityKey = @"ECVVideoQuality";
static NSString *const ECVCropRectKey = @"ECVCropRect";
static NSString *const ECVCropSourceAspectRatioKey = @"ECVCropSourceAspectRatio";
static NSString *const ECVCropBorderKey = @"ECVCropBorder";

@interface ECVCaptureController(Private)

- (void)_hideMenuBar;
- (void)_updateCropRect;

@end

@implementation ECVCaptureController

#pragma mark -ECVCaptureController

- (IBAction)cloneViewer:(id)sender
{
	ECVCaptureController *const controller = [[[[self class] alloc] init] autorelease];
	[[self captureDocument] addWindowController:controller];
	[controller showWindow:sender];
	if(![[self captureDocument] isPaused]) [controller play];
}

#pragma mark -

- (IBAction)play:(id)sender
{
	[[self captureDocument] setPausedFromUI:NO];
}
- (IBAction)pause:(id)sender
{
	[[self captureDocument] setPausedFromUI:YES];
}
- (IBAction)togglePlaying:(id)sender
{
	[[self captureDocument] setPausedFromUI:![[self captureDocument] isPausedFromUI]];
}

#pragma mark -

- (IBAction)startRecording:(id)sender
{
#if __LP64__
	NSAlert *const alert = [[[NSAlert alloc] init] autorelease];
	[alert setMessageText:NSLocalizedString(@"Recording is not supported in 64-bit mode.", nil)];
	[alert setInformativeText:NSLocalizedString(@"Relaunch EasyCapViewer in 32-bit mode to record.", nil)];
	[alert addButtonWithTitle:NSLocalizedString(@"OK", nil)];
	[alert runModal];
#else
	if(_movieRecorder) return;

	NSUserDefaults *const d = [NSUserDefaults standardUserDefaults];

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
	(void)[videoCodecPopUp selectItemWithTag:NSHFSTypeCodeFromFileType([d objectForKey:ECVVideoCodecKey])];
	[self changeCodec:videoCodecPopUp];
	[videoQualitySlider setDoubleValue:[d doubleForKey:ECVVideoQualityKey]];

	NSInteger const returnCode = [savePanel runModalForDirectory:nil file:NSLocalizedString(@"untitled", nil)];
	[d setObject:[NSNumber numberWithDouble:[videoQualitySlider doubleValue]] forKey:ECVVideoQualityKey];
	if(NSFileHandlingPanelOKButton != returnCode) return;

	ECVMovieRecordingOptions *const options = [[[ECVMovieRecordingOptions alloc] init] autorelease];
	[options setURL:[savePanel URL]];
	[options setVideoStorage:[[[self captureDocument] videoDevice] videoStorage]];
	[options setAudioInput:[[self captureDocument] audioDevice]];

	[options setVideoCodec:(OSType)[videoCodecPopUp selectedTag]];
	[options setVideoQuality:[videoQualitySlider doubleValue]];
	[options setOutputSize:ECVIntegerSizeFromNSSize([self outputSize])];
	[options setCropRect:[self cropRect]];
	[options setUpconvertsFromMono:[[[self captureDocument] audioTarget] upconvertsFromMono]];
	[options setFrameRate:[[self videoFormat] frameRate]];

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
	[[NSUserDefaults standardUserDefaults] setObject:codec forKey:ECVVideoCodecKey];
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
	[[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithUnsignedInteger:[sender tag]] forKey:ECVAspectRatio2Key];
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
	[[NSUserDefaults standardUserDefaults] setBool:[videoView vsync] forKey:ECVVsyncKey];
}
- (IBAction)toggleSmoothing:(id)sender
{
	switch([videoView magFilter]) {
		case GL_NEAREST: [videoView setMagFilter:GL_LINEAR]; break;
		case GL_LINEAR: [videoView setMagFilter:GL_NEAREST]; break;
	}
	[[NSUserDefaults standardUserDefaults] setInteger:[videoView magFilter] forKey:ECVMagFilterKey];
}
- (IBAction)toggleShowDroppedFrames:(id)sender
{
	[videoView setShowDroppedFrames:![videoView showDroppedFrames]];
	[[NSUserDefaults standardUserDefaults] setBool:[videoView showDroppedFrames] forKey:ECVShowDroppedFramesKey];
}

#pragma mark -

- (NSSize)aspectRatio
{
	return [videoView aspectRatio];
}
- (void)setAspectRatio:(NSSize const)ratio
{
	[videoView setAspectRatio:ratio];
	[[self window] setContentAspectRatio:ratio];
	CGFloat const r = ratio.width / ratio.height;
	NSSize s = [self windowContentSize];
	s.width = s.height * r;
	[self setWindowContentSize:s];
	[[self window] setMinSize:NSMakeSize(120.0f * r, 120.0f)];
	[self _updateCropRect];
}
- (NSRect)cropRect
{
	return [[videoView cell] respondsToSelector:@selector(cropRect)] ? [(ECVCropCell *)[videoView cell] cropRect] : [videoView cropRect];
}
- (BOOL)isFullScreen
{
	return _fullScreen || !!([[self window] styleMask] & NSFullScreenWindowMask);
}
- (void)setFullScreen:(BOOL const)flag
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
	[w setCollectionBehavior:NSWindowCollectionBehaviorFullScreenPrimary];
	[self setWindow:w];
	[self synchronizeWindowTitleWithDocumentName];
	[w setDocumentEdited:[oldWindow isDocumentEdited]];
	[w makeKeyAndOrderFront:self];
	[oldWindow close];
	if(!flag) [w center];
	NSEnableScreenUpdates();
}
- (NSSize)windowContentSize
{
	NSWindow *const w = [self window];
	return [w contentRectForFrameRect:[w frame]].size;
}
- (void)setWindowContentSize:(NSSize const)size
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
	return [[self videoFormat] displaySizeWithAspectRatio:[videoView aspectRatio]];
}
- (NSSize)outputSizeWithScale:(NSInteger const)scale
{
	NSSize const s = [self outputSize];
	CGFloat const factor = powf(2, (CGFloat)scale);
	return NSMakeSize(s.width * factor, s.height * factor);
}
- (NSSize)sizeWithAspectRatio:(ECVAspectRatio const)ratio
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
- (NSRect)cropRectWithSourceAspectRatio:(ECVAspectRatio const)type
{
	if(ECVAspectRatioUnknown == type) return ECVUncroppedRect;
	NSSize const src = [self sizeWithAspectRatio:type];
	NSSize const dst = [self aspectRatio];
	CGFloat const correction = (dst.height / dst.width) / (src.height / src.width);
	return correction < 1.0f ? NSMakeRect(0.0f, (1.0f - correction) / 2.0f, 1.0f, correction) : NSMakeRect((1.0f - (1.0f / correction)) / 2.0f, 0.0f, 1.0f / correction, 1.0f);
}
- (NSRect)cropRect:(NSRect const)r withBorder:(ECVCropBorder const)border
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
	[[NSUserDefaults standardUserDefaults] setInteger:_cropSourceAspectRatio forKey:ECVCropSourceAspectRatioKey];
	[[NSUserDefaults standardUserDefaults] setInteger:_cropBorder forKey:ECVCropBorderKey];
}

#pragma mark -NSWindowController

- (void)windowDidLoad
{
	NSUserDefaults *const d = [NSUserDefaults standardUserDefaults];
	[d registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithUnsignedInteger:ECVAspectRatio4x3], ECVAspectRatio2Key,
		[NSNumber numberWithBool:YES], ECVVsyncKey,
		[NSNumber numberWithInteger:GL_LINEAR], ECVMagFilterKey,
		[NSNumber numberWithBool:NO], ECVShowDroppedFramesKey,
		NSFileTypeForHFSTypeCode("jpeg"), ECVVideoCodecKey,
		[NSNumber numberWithDouble:0.5f], ECVVideoQualityKey,
		NSStringFromRect(ECVUncroppedRect), ECVCropRectKey,
		[NSNumber numberWithInteger:ECVAspectRatioUnknown], ECVCropSourceAspectRatioKey,
		[NSNumber numberWithInteger:ECVCropBorderNone], ECVCropBorderKey,
		nil]];

	_cropSourceAspectRatio = [d integerForKey:ECVCropSourceAspectRatioKey];
	_cropBorder = [d integerForKey:ECVCropBorderKey];
	[videoView setCropRect:NSRectFromString([d objectForKey:ECVCropRectKey])];
	[self _updateCropRect];

	[self setAspectRatio:[self sizeWithAspectRatio:[[d objectForKey:ECVAspectRatio2Key] unsignedIntegerValue]]];

	NSWindow *const w = [self window];
	NSSize const s = [self outputSize];
	[w setFrame:[w frameRectForContentRect:NSMakeRect(0.0f, 0.0f, s.width, s.height)] display:NO];
	[w setCollectionBehavior:NSWindowCollectionBehaviorFullScreenPrimary];

	[videoView setVsync:[d boolForKey:ECVVsyncKey]];
	[videoView setShowDroppedFrames:[d boolForKey:ECVShowDroppedFramesKey]];
	[videoView setMagFilter:(GLint)[d integerForKey:ECVMagFilterKey]];

	_playButtonCell = [[ECVPlayButtonCell alloc] initWithOpenGLContext:[videoView openGLContext]];
	[_playButtonCell setImage:[ECVPlayButtonCell playButtonImage]];
	[_playButtonCell setTarget:self];
	[_playButtonCell setAction:@selector(togglePlaying:)];
	[videoView setCell:_playButtonCell];

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
	[_playButtonCell release];
	[_movieRecorder release];
	[super dealloc];
}

#pragma mark -NSObject(ECVTarget)

- (void)play
{
	[videoView setVideoStorage:[[self videoDevice] videoStorage]];
	[videoView startDrawing];
}
- (void)stop
{
	[videoView stopDrawing];
	[self stopRecording:self];
}
- (void)pushVideoFrame:(ECVVideoFrame *const)frame
{
	[videoView pushFrame:frame];
	if(_movieRecorder) @synchronized(self) {
		[_movieRecorder addVideoFrame:frame];
	}
}
- (void)pushAudioBufferListValue:(NSValue *const)bufferListValue
{
	if(_movieRecorder) @synchronized(self) {
		[_movieRecorder addAudioBufferList:[bufferListValue pointerValue]];
	}
}

#pragma mark -NSObject(NSMenuValidation)

- (BOOL)validateMenuItem:(NSMenuItem *)anItem
{
	SEL const action = [anItem action];
	if(@selector(toggleFullScreen:) == action) [anItem setTitle:[self isFullScreen] ? NSLocalizedString(@"Exit Full Screen", nil) : NSLocalizedString(@"Enter Full Screen", nil)];
	if(@selector(togglePlaying:) == action) [anItem setTitle:![[self captureDocument] isPaused] ? NSLocalizedString(@"Pause", nil) : NSLocalizedString(@"Play", nil)];
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
	if([[self captureDocument] isPaused]) {
		if(@selector(startRecording:) == action) return NO;
	}
	return [self respondsToSelector:action];
}

#pragma mark -<ECVCropCellDelegate>

- (void)cropCellDidFinishCropping:(ECVCropCell *)sender
{
	[videoView setCropRect:[sender cropRect]];
	[videoView setCell:_playButtonCell];
	[[NSUserDefaults standardUserDefaults] setObject:NSStringFromRect([sender cropRect]) forKey:ECVCropRectKey];
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
	ECVAudioTarget *const audioTarget = [[self captureDocument] audioTarget];
	if(NSCommandKeyMask == modifiers) switch(character) {
		case NSUpArrowFunctionKey:
			[audioTarget setVolume:[audioTarget volume] + 0.05f];
			return YES;
		case NSDownArrowFunctionKey:
			[audioTarget setVolume:[audioTarget volume] - 0.05f];
			return YES;
	}
	if((NSCommandKeyMask | NSAlternateKeyMask) == modifiers) switch(character) {
		case NSUpArrowFunctionKey:
		case NSDownArrowFunctionKey:
			[audioTarget setMuted:![audioTarget isMuted]];
			return YES;
	}
	return NO;
}

#pragma mark -<NSWindowDelegate>

- (void)windowDidBecomeMain:(NSNotification *)aNotif
{
	if([self isFullScreen]) [self performSelector:@selector(_hideMenuBar) withObject:nil afterDelay:0.0f inModes:[NSArray arrayWithObject:(NSString *)kCFRunLoopCommonModes]];
	[[ECVConfigController sharedConfigController] setCaptureDocument:[self captureDocument]];
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

#pragma mark -

- (NSSize)window:(NSWindow *)window willUseFullScreenContentSize:(NSSize)proposedSize
{
	return proposedSize;
}
- (NSApplicationPresentationOptions)window:(NSWindow *)window willUseFullScreenPresentationOptions:(NSApplicationPresentationOptions)proposedOptions
{
	return proposedOptions;
}





// Ongoing refactoring... This code is new, the above code is not.


- (ECVCaptureDocument *)captureDocument
{
	return [self document];
}
- (ECVCaptureDevice *)videoDevice
{
	return [[self captureDocument] videoDevice];
}

- (ECVVideoFormat *)videoFormat
{
	return [[[self videoDevice] videoStorage] videoFormat];
}




@end
