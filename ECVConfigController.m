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
#import "ECVConfigController.h"

// Models
#import "ECVCaptureDevice.h"
#import "ECVDeinterlacingMode.h"

// Other Sources
#import "ECVAudioDevice.h"
#import "ECVFoundationAdditions.h"

@interface ECVConfigController(Private)

- (void)_snapSlider:(NSSlider *)slider;

@end

@implementation ECVConfigController

#pragma mark +ECVConfigController

+ (id)sharedConfigController
{
	static ECVConfigController *c;
	if(!c) c = [[self alloc] init];
	return [[c retain] autorelease];
}

#pragma mark -ECVConfigController

- (IBAction)changeFormat:(id)sender
{
	[_captureDevice setVideoFormatObject:[[sender selectedItem] representedObject]];
}
- (IBAction)changeSource:(id)sender
{
	[_captureDevice setVideoSourceObject:[[sender selectedItem] representedObject]];
}
- (IBAction)changeDeinterlacing:(id)sender
{
	[_captureDevice setDeinterlacingMode:[ECVDeinterlacingMode deinterlacingModeWithType:[sender selectedTag]]];
}
- (IBAction)changeBrightness:(id)sender
{
	[self _snapSlider:sender];
	[_captureDevice setBrightness:[sender doubleValue]];
}
- (IBAction)changeContrast:(id)sender
{
	[self _snapSlider:sender];
	[_captureDevice setContrast:[sender doubleValue]];
}
- (IBAction)changeSaturation:(id)sender
{
	[self _snapSlider:sender];
	[_captureDevice setSaturation:[sender doubleValue]];
}
- (IBAction)changeHue:(id)sender
{
	[self _snapSlider:sender];
	[_captureDevice setHue:[sender doubleValue]];
}

#pragma mark -

- (IBAction)changeAudioInput:(id)sender
{
	[_captureDevice setAudioInput:[[sender selectedItem] representedObject]];
}
- (IBAction)changeUpconvertsFromMono:(id)sender
{
	[_captureDevice setUpconvertsFromMono:NSOnState == [sender state]];
}
- (IBAction)changeVolume:(id)sender
{
	[_captureDevice setVolume:[sender doubleValue]];
	[_captureDevice setMuted:NO];
}

#pragma mark -

@synthesize captureDevice = _captureDevice;
- (void)setCaptureDevice:(ECVCaptureDevice *)c
{
	[_captureDevice ECV_removeObserver:self name:ECVCaptureDeviceVolumeDidChangeNotification];
	_captureDevice = c;
	[_captureDevice ECV_addObserver:self selector:@selector(volumeDidChange:) name:ECVCaptureDeviceVolumeDidChangeNotification];
	[self volumeDidChange:nil];

	if(![self isWindowLoaded]) return;

	[sourcePopUp removeAllItems];
	if([_captureDevice respondsToSelector:@selector(allVideoSourceObjects)]) for(id const videoSourceObject in [_captureDevice allVideoSourceObjects]) {
		if([NSNull null] == videoSourceObject) {
			[[sourcePopUp menu] addItem:[NSMenuItem separatorItem]];
			continue;
		}
		NSMenuItem *const item = [[[NSMenuItem alloc] initWithTitle:[_captureDevice localizedStringForVideoSourceObject:videoSourceObject] action:NULL keyEquivalent:@""] autorelease];
		[item setRepresentedObject:videoSourceObject];
		[item setEnabled:[_captureDevice isValidVideoSourceObject:videoSourceObject]];
		[item setIndentationLevel:[_captureDevice indentationLevelForVideoSourceObject:videoSourceObject]];
		[[sourcePopUp menu] addItem:item];
	}
	[sourcePopUp setEnabled:[_captureDevice respondsToSelector:@selector(videoSourceObject)]];
	if([sourcePopUp isEnabled]) [sourcePopUp selectItemAtIndex:[sourcePopUp indexOfItemWithRepresentedObject:[_captureDevice videoSourceObject]]];

	[formatPopUp removeAllItems];
	if([_captureDevice respondsToSelector:@selector(allVideoFormatObjects)]) for(id const videoFormatObject in [_captureDevice allVideoFormatObjects]) {
		if([NSNull null] == videoFormatObject) {
			[[formatPopUp menu] addItem:[NSMenuItem separatorItem]];
			continue;
		}
		NSMenuItem *const item = [[[NSMenuItem alloc] initWithTitle:[_captureDevice localizedStringForVideoFormatObject:videoFormatObject] action:NULL keyEquivalent:@""] autorelease];
		[item setRepresentedObject:videoFormatObject];
		[item setEnabled:[_captureDevice isValidVideoFormatObject:videoFormatObject]];
		[item setIndentationLevel:[_captureDevice indentationLevelForVideoFormatObject:videoFormatObject]];
		[[formatPopUp menu] addItem:item];
	}
	[formatPopUp setEnabled:[_captureDevice respondsToSelector:@selector(videoFormatObject)]];
	if([formatPopUp isEnabled]) [formatPopUp selectItemAtIndex:[formatPopUp indexOfItemWithRepresentedObject:[_captureDevice videoFormatObject]]];

	[deinterlacePopUp selectItemWithTag:[[_captureDevice deinterlacingMode] deinterlacingModeType]];
	[deinterlacePopUp setEnabled:!!_captureDevice];

	[brightnessSlider setEnabled:[_captureDevice respondsToSelector:@selector(brightness)]];
	[contrastSlider setEnabled:[_captureDevice respondsToSelector:@selector(contrast)]];
	[saturationSlider setEnabled:[_captureDevice respondsToSelector:@selector(saturation)]];
	[hueSlider setEnabled:[_captureDevice respondsToSelector:@selector(hue)]];
	[brightnessSlider setDoubleValue:[brightnessSlider isEnabled] ? [_captureDevice brightness] : 0.5f];
	[contrastSlider setDoubleValue:[contrastSlider isEnabled] ? [_captureDevice contrast] : 0.5f];
	[saturationSlider setDoubleValue:[saturationSlider isEnabled] ? [_captureDevice saturation] : 0.5f];
	[hueSlider setDoubleValue:[hueSlider isEnabled] ? [_captureDevice hue] : 0.5f];
	[self _snapSlider:brightnessSlider];
	[self _snapSlider:contrastSlider];
	[self _snapSlider:saturationSlider];
	[self _snapSlider:hueSlider];

	[upconvertsFromMonoSwitch setEnabled:[_captureDevice respondsToSelector:@selector(upconvertsFromMono)]];
	[upconvertsFromMonoSwitch setState:[upconvertsFromMonoSwitch isEnabled] && [_captureDevice upconvertsFromMono]];

	[self audioHardwareDevicesDidChange:nil];
	[audioSourcePopUp setEnabled:!!_captureDevice];
}

#pragma mark -

- (void)audioHardwareDevicesDidChange:(NSNotification *)aNotif
{
	[audioSourcePopUp removeAllItems];
	NSMenuItem *const nilItem = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"No Input", nil) action:NULL keyEquivalent:@""] autorelease];
	[[audioSourcePopUp menu] addItem:nilItem];
	ECVAudioInput *const preferredInput = [_captureDevice audioInputOfCaptureHardware];
	if(preferredInput) {
		NSMenuItem *const item = [[[NSMenuItem alloc] initWithTitle:[preferredInput name] action:NULL keyEquivalent:@""] autorelease];
		[item setRepresentedObject:preferredInput];
		[[audioSourcePopUp menu] addItem:item];
	}
	NSMenuItem *const separator = [NSMenuItem separatorItem];
	[[audioSourcePopUp menu] addItem:separator];
	BOOL hasAdditionalItems = NO;
	for(ECVAudioInput *const input in [ECVAudioInput allDevices]) {
		if(ECVEqualObjects(input, preferredInput)) continue;
		NSMenuItem *const item = [[[NSMenuItem alloc] initWithTitle:[input name] action:NULL keyEquivalent:@""] autorelease];
		[item setRepresentedObject:input];
		[[audioSourcePopUp menu] addItem:item];
		hasAdditionalItems = YES;
	}
	if(!hasAdditionalItems) [[audioSourcePopUp menu] removeItem:separator];
	ECVAudioInput *const input = [_captureDevice audioInput];
	[audioSourcePopUp selectItemAtIndex:input ? [audioSourcePopUp indexOfItemWithRepresentedObject:input] : 0];
}
- (void)volumeDidChange:(NSNotification *)aNotif
{
	if(![self isWindowLoaded]) return;
	BOOL const volumeSupported = [_captureDevice respondsToSelector:@selector(volume)];
	[volumeSlider setEnabled:volumeSupported];
	if(volumeSupported) [volumeSlider setDoubleValue:[_captureDevice isMuted] ? 0.0f : [_captureDevice volume]];
	else [volumeSlider setDoubleValue:1.0f];
}

#pragma mark -ECVConfigController(Private)

- (void)_snapSlider:(NSSlider *)slider
{
	if(ABS([slider doubleValue] - 0.5f) < 0.03f) [slider setDoubleValue:0.5f];
}

#pragma mark -NSWindowController

- (void)windowDidLoad
{
	[super windowDidLoad];
	NSPanel *const w = (NSPanel *)[self window];
	[w setBecomesKeyOnlyIfNeeded:YES];
	[w setCollectionBehavior:NSWindowCollectionBehaviorFullScreenAuxiliary];
	[[ECVAudioDevice class] ECV_addObserver:self selector:@selector(audioHardwareDevicesDidChange:) name:ECVAudioHardwareDevicesDidChangeNotification];
	[self setCaptureDevice:_captureDevice];
}
- (NSString *)windowFrameAutosaveName
{
	return NSStringFromClass([self class]);
}

#pragma mark -NSObject

- (id)init
{
	return [super initWithWindowNibName:@"ECVConfig"];
}
- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[super dealloc];
}

@end
