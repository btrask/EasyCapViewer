/* Copyright (c) 2009, Ben Trask
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
	* Redistributions of source code must retain the above copyright
	  notice, this list of conditions and the following disclaimer.
	* Redistributions in binary form must reproduce the above copyright
	  notice, this list of conditions and the following disclaimer in the
	  documentation and/or other materials provided with the distribution.
	* The names of its contributors may be used to endorse or promote products
	  derived from this software without specific prior written permission.

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
#import <libkern/OSAtomic.h>

// Models
#import "ECVCaptureDevice.h"
#import "ECVVideoStorage.h"
#import "ECVVideoFrame.h"
#import "ECVMovieRecorder.h"

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

@interface ECVCaptureController(Private)

- (void)_hideMenuBar;

@end

@implementation ECVCaptureController

#pragma mark +NSObject

+ (void)initialize
{
	[[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithUnsignedInteger:ECV4x3AspectRatio], ECVAspectRatio2Key,
		[NSNumber numberWithBool:NO], ECVVsyncKey,
		[NSNumber numberWithInteger:GL_LINEAR], ECVMagFilterKey,
		[NSNumber numberWithBool:NO], ECVShowDroppedFramesKey,
		NSStringFromRect(ECVUncroppedRect), ECVCropRectKey,
		nil]];
}

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
	[alert setInformativeText:NSLocalizedString(@"Relaunch EasyCapViewer in 32-bit mode to record.", nil)];
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
	(void)[videoCodecPopUp selectItemWithTag:NSHFSTypeCodeFromFileType([[NSUserDefaults standardUserDefaults] objectForKey:ECVVideoCodecKey])];
	[self changeCodec:videoCodecPopUp];
	[videoQualitySlider setDoubleValue:[[NSUserDefaults standardUserDefaults] doubleForKey:ECVVideoQualityKey]];

	NSInteger const returnCode = [savePanel runModalForDirectory:nil file:NSLocalizedString(@"untitled", nil)];
	[[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithDouble:[videoQualitySlider doubleValue]] forKey:ECVVideoQualityKey];
	if(NSFileHandlingPanelOKButton != returnCode) return;

	ECVMovieRecorder *const recorder = [[[ECVMovieRecorder alloc] initWithURL:[savePanel URL] videoStorage:[[self document] videoStorage] audioDevice:[[self document] audioInput]] autorelease];
	[recorder setVideoCodec:(OSType)[videoCodecPopUp selectedTag]];
	[recorder setVideoQuality:[videoQualitySlider doubleValue]];
	[recorder setOutputSize:ECVPixelSizeFromNSSize([self outputSize])];
	[recorder setCropRect:[self cropRect]];

	NSError *error = nil;
	if([recorder startRecordingError:&error]) {
		OSMemoryBarrier();
		_movieRecorder = [recorder retain];
	} else [[NSAlert alertWithError:error] runModal];
#endif
}
- (IBAction)stopRecording:(id)sender
{
#if !__LP64__
	if(!_movieRecorder) return;
	ECVMovieRecorder *const recorder = _movieRecorder;
	_movieRecorder = nil;
	OSMemoryBarrier();
	[[recorder autorelease] stopRecording];
#endif
}
- (IBAction)changeCodec:(id)sender
{
	NSString *const codec = NSFileTypeForHFSTypeCode((OSType)[sender selectedTag]);
	[[NSUserDefaults standardUserDefaults] setObject:codec forKey:ECVVideoCodecKey];
	NSNumber *const configurableQuality = [[[[NSBundle mainBundle] objectForInfoDictionaryKey:@"ECVInfoByVideoCodec"] objectForKey:codec] objectForKey:@"ECVConfigurableQuality"];
	[videoQualitySlider setEnabled:configurableQuality && [configurableQuality boolValue]];
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
- (IBAction)changeCropType:(id)sender
{
	NSRect const r = [self cropRectWithType:[sender tag]];
	if([[videoView cell] respondsToSelector:@selector(setCropRect:)]) {
		[(ECVCropCell *)[videoView cell] setCropRect:r];
		[videoView setNeedsDisplay:YES];
		[[self window] invalidateCursorRectsForView:videoView];
	}else [self setCropRect:r];
}
- (IBAction)enterCropMode:(id)sender
{
	ECVCropCell *const cell = [[[ECVCropCell alloc] initWithOpenGLContext:[videoView openGLContext]] autorelease];
	cell.delegate = self;
	cell.cropRect = [self cropRect];
	[videoView setCropRect:ECVUncroppedRect];
	[videoView setCell:cell];
}
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
- (void)setAspectRatio:(NSSize)ratio
{
	[videoView setAspectRatio:ratio];
	[[self window] setContentAspectRatio:ratio];
	CGFloat const r = ratio.height / ratio.width;
	NSSize s = [self windowContentSize];
	s.height = s.width * r;
	[self setWindowContentSize:s];
	[[self window] setMinSize:NSMakeSize(200.0f, 200.0f * r)];
}
- (NSRect)cropRect
{
	return [[videoView cell] respondsToSelector:@selector(cropRect)] ? [(ECVCropCell *)[videoView cell] cropRect] : [videoView cropRect];
}
- (void)setCropRect:(NSRect)aRect
{
	[videoView setCropRect:aRect];
	[[NSUserDefaults standardUserDefaults] setObject:NSStringFromRect(aRect) forKey:ECVCropRectKey];
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
	[self setWindow:w];
	[self synchronizeWindowTitleWithDocumentName];
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
	ECVPixelSize const s = [[self document] captureSize];
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
		case ECV1x1AspectRatio:   return NSMakeSize( 1.0f,  1.0f);
		case ECV4x3AspectRatio:   return NSMakeSize( 4.0f,  3.0f);
		case ECV3x2AspectRatio:   return NSMakeSize( 3.0f,  2.0f);
		case ECV16x10AspectRatio: return NSMakeSize(16.0f, 10.0f);
		case ECV16x9AspectRatio:  return NSMakeSize(16.0f,  9.0f);
	}
	return NSZeroSize;
}
- (NSRect)cropRectWithType:(ECVCropType)type
{
	switch(type) {
		case ECVCrop2_5Percent: return NSMakeRect(0.025f, 0.025f, 0.95f, 0.95f);
		case ECVCrop5Percent: return NSMakeRect(0.05f, 0.05f, 0.9f, 0.9f);
		case ECVCrop10Percent: return NSMakeRect(0.1f, 0.1f, 0.8f, 0.8f);
		case ECVCrop4x3to16x9: return [self cropRectWithSourceAspectRatio:ECV4x3AspectRatio croppedToAspectRatio:ECV16x9AspectRatio];
		case ECVCrop4x3to16x10: return [self cropRectWithSourceAspectRatio:ECV4x3AspectRatio croppedToAspectRatio:ECV16x10AspectRatio];
		case ECVCrop16x9to16x10: return [self cropRectWithSourceAspectRatio:ECV16x9AspectRatio croppedToAspectRatio:ECV16x10AspectRatio];
		default: return ECVUncroppedRect;
	}
}
- (NSRect)cropRectWithSourceAspectRatio:(ECVAspectRatio)r1 croppedToAspectRatio:(ECVAspectRatio)r2
{
	NSSize const standard = [self sizeWithAspectRatio:r1];
	NSSize const user = [self sizeWithAspectRatio:r2];
	CGFloat const correction = (user.height / user.width) / (standard.height / standard.width);
	return correction < 1.0f ? NSMakeRect(0.0f, (1.0f - correction) / 2.0f, 1.0f, correction) : NSMakeRect((1.0f - (1.0f / correction)) / 2.0f, 0.0f, 1.0f / correction, 1.0f);
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
	if(_movieRecorder) {
		OSMemoryBarrier();
		[_movieRecorder addVideoFrame:frame];
	}
}
- (void)threaded_pushAudioBufferListValue:(NSValue *)bufferListValue
{
	if(_movieRecorder) {
		OSMemoryBarrier();
		[_movieRecorder addAudioBufferList:[bufferListValue pointerValue]];
	}
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

#pragma mark -NSWindowController

- (void)windowDidLoad
{
	NSWindow *const w = [self window];
	ECVPixelSize const s = [[self document] captureSize];
	[w setFrame:[w frameRectForContentRect:NSMakeRect(0.0f, 0.0f, s.width, s.height)] display:NO];
	[self setAspectRatio:[self sizeWithAspectRatio:[[[NSUserDefaults standardUserDefaults] objectForKey:ECVAspectRatio2Key] unsignedIntegerValue]]];

	[videoView setCropRect:NSRectFromString([[NSUserDefaults standardUserDefaults] stringForKey:ECVCropRectKey])];
	[videoView setVsync:[[NSUserDefaults standardUserDefaults] boolForKey:ECVVsyncKey]];
	[videoView setShowDroppedFrames:[[NSUserDefaults standardUserDefaults] boolForKey:ECVShowDroppedFramesKey]];
	[videoView setMagFilter:[[NSUserDefaults standardUserDefaults] integerForKey:ECVMagFilterKey]];

	_playButtonCell = [[ECVPlayButtonCell alloc] initWithOpenGLContext:[videoView openGLContext]];
	[_playButtonCell setImage:[ECVPlayButtonCell playButtonImage]];
	_playButtonCell.target = self;
	_playButtonCell.action = @selector(togglePlaying:);
	[videoView setCell:_playButtonCell];

	[w center];
	[super windowDidLoad];
}

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

#pragma mark -NSObject(NSMenuValidation)

- (BOOL)validateMenuItem:(NSMenuItem *)anItem
{
	SEL const action = [anItem action];
	if(@selector(toggleFullScreen:) == action) [anItem setTitle:[self isFullScreen] ? NSLocalizedString(@"Exit Full Screen", nil) : NSLocalizedString(@"Enter Full Screen", nil)];
	if(@selector(togglePlaying:) == action) [anItem setTitle:[[self document] isPlaying] ? NSLocalizedString(@"Pause", nil) : NSLocalizedString(@"Play", nil)];
	if(@selector(changeAspectRatio:) == action) {
		NSSize const s1 = [self sizeWithAspectRatio:[anItem tag]];
		NSSize const s2 = [videoView aspectRatio];
		[anItem setState:s1.width / s1.height == s2.width / s2.height];
	}
	if(@selector(changeCropType:) == action) [anItem setState:NSEqualRects([self cropRectWithType:[anItem tag]], [self cropRect])];
	if(@selector(changeScale:) == action) [anItem setState:!!NSEqualSizes([self windowContentSize], [self outputSizeWithScale:[anItem tag]])];
	if(@selector(toggleFloatOnTop:) == action) [anItem setTitle:[[self window] level] == NSFloatingWindowLevel ? NSLocalizedString(@"Turn Floating Off", nil) : NSLocalizedString(@"Turn Floating On", nil)];
	if(@selector(toggleVsync:) == action) [anItem setTitle:[videoView vsync] ? NSLocalizedString(@"Turn V-Sync Off", nil) : NSLocalizedString(@"Turn V-Sync On", nil)];
	if(@selector(toggleSmoothing:) == action) [anItem setTitle:GL_LINEAR == [videoView magFilter] ? NSLocalizedString(@"Turn Smoothing Off", nil) : NSLocalizedString(@"Turn Smoothing On", nil)];
	if(@selector(toggleShowDroppedFrames:) == action) [anItem setTitle:[videoView showDroppedFrames] ? NSLocalizedString(@"Hide Dropped Frames", nil) : NSLocalizedString(@"Show Dropped Frames", nil)];

	if(![self conformsToProtocol:@protocol(ECVCaptureControllerConfiguring)]) {
		if(@selector(configureDevice:) == action) return NO;
	}
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

#pragma mark -<ECVCropCellDelegate>

- (void)cropCellDidFinishCropping:(ECVCropCell *)sender
{
	[self setCropRect:[sender cropRect]];
	[videoView setCell:_playButtonCell];
}

#pragma mark -<ECVVideoViewDelegate>

- (BOOL)videoView:(ECVVideoView *)sender handleKeyDown:(NSEvent *)anEvent
{
	if([@" " isEqualToString:[anEvent charactersIgnoringModifiers]]) {
		[self togglePlaying:self];
		return YES;
	}
	return NO;
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

@end
