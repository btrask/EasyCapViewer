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
#import "ECVCaptureDocument.h"
//#import "ECVDeinterlacingMode.h"

// Other Sources
//#import "ECVAudioDevice.h"
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
//	[_captureDocument setVideoFormatObject:[[sender selectedItem] representedObject]];
}
- (IBAction)changeSource:(id)sender
{
//	[_captureDocument setVideoSourceObject:[[sender selectedItem] representedObject]];
}
- (IBAction)changeDeinterlacing:(id)sender
{
//	[_captureDocument setDeinterlacingMode:[ECVDeinterlacingMode deinterlacingModeWithType:[sender selectedTag]]];
}
- (IBAction)changeBrightness:(id)sender
{
	[self _snapSlider:sender];
//	[_captureDocument setBrightness:[sender doubleValue]];
}
- (IBAction)changeContrast:(id)sender
{
	[self _snapSlider:sender];
//	[_captureDocument setContrast:[sender doubleValue]];
}
- (IBAction)changeSaturation:(id)sender
{
	[self _snapSlider:sender];
//	[_captureDocument setSaturation:[sender doubleValue]];
}
- (IBAction)changeHue:(id)sender
{
	[self _snapSlider:sender];
//	[_captureDocument setHue:[sender doubleValue]];
}

#pragma mark -

- (IBAction)changeAudioInput:(id)sender
{
//	[_captureDocument setAudioInput:[[sender selectedItem] representedObject]];
}
- (IBAction)changeUpconvertsFromMono:(id)sender
{
//	[_captureDocument setUpconvertsFromMono:NSOnState == [sender state]];
}
- (IBAction)changeVolume:(id)sender
{
//	[_captureDocument setVolume:[sender doubleValue]];
//	[_captureDocument setMuted:NO];
}

#pragma mark -

@synthesize captureDocument = _captureDocument;
- (void)setCaptureDocument:(ECVCaptureDocument *)c
{
//	[_captureDocument ECV_removeObserver:self name:ECVCaptureDocumentVolumeDidChangeNotification];
//	_captureDocument = c;
//	[_captureDocument ECV_addObserver:self selector:@selector(volumeDidChange:) name:ECVCaptureDocumentVolumeDidChangeNotification];
//	[self volumeDidChange:nil];
//
//	if(![self isWindowLoaded]) return;
//
//	[sourcePopUp removeAllItems];
//	if([_captureDocument respondsToSelector:@selector(allVideoSourceObjects)]) for(id const videoSourceObject in [_captureDocument allVideoSourceObjects]) {
//		if([NSNull null] == videoSourceObject) {
//			[[sourcePopUp menu] addItem:[NSMenuItem separatorItem]];
//			continue;
//		}
//		NSMenuItem *const item = [[[NSMenuItem alloc] initWithTitle:[_captureDocument localizedStringForVideoSourceObject:videoSourceObject] action:NULL keyEquivalent:@""] autorelease];
//		[item setRepresentedObject:videoSourceObject];
//		[item setEnabled:[_captureDocument isValidVideoSourceObject:videoSourceObject]];
//		[item setIndentationLevel:[_captureDocument indentationLevelForVideoSourceObject:videoSourceObject]];
//		[[sourcePopUp menu] addItem:item];
//	}
//	[sourcePopUp setEnabled:[_captureDocument respondsToSelector:@selector(videoSourceObject)]];
//	if([sourcePopUp isEnabled]) [sourcePopUp selectItemAtIndex:[sourcePopUp indexOfItemWithRepresentedObject:[_captureDocument videoSourceObject]]];
//
//	[formatPopUp removeAllItems];
//	if([_captureDocument respondsToSelector:@selector(allVideoFormatObjects)]) for(id const videoFormatObject in [_captureDocument allVideoFormatObjects]) {
//		if([NSNull null] == videoFormatObject) {
//			[[formatPopUp menu] addItem:[NSMenuItem separatorItem]];
//			continue;
//		}
//		NSMenuItem *const item = [[[NSMenuItem alloc] initWithTitle:[_captureDocument localizedStringForVideoFormatObject:videoFormatObject] action:NULL keyEquivalent:@""] autorelease];
//		[item setRepresentedObject:videoFormatObject];
//		[item setEnabled:[_captureDocument isValidVideoFormatObject:videoFormatObject]];
//		[item setIndentationLevel:[_captureDocument indentationLevelForVideoFormatObject:videoFormatObject]];
//		[[formatPopUp menu] addItem:item];
//	}
//	[formatPopUp setEnabled:[_captureDocument respondsToSelector:@selector(videoFormatObject)]];
//	if([formatPopUp isEnabled]) [formatPopUp selectItemAtIndex:[formatPopUp indexOfItemWithRepresentedObject:[_captureDocument videoFormatObject]]];
//
////	[deinterlacePopUp selectItemWithTag:[[_captureDocument deinterlacingMode] deinterlacingModeType]];
////	[deinterlacePopUp setEnabled:!!_captureDocument];
//
//	[brightnessSlider setEnabled:[_captureDocument respondsToSelector:@selector(brightness)]];
//	[contrastSlider setEnabled:[_captureDocument respondsToSelector:@selector(contrast)]];
//	[saturationSlider setEnabled:[_captureDocument respondsToSelector:@selector(saturation)]];
//	[hueSlider setEnabled:[_captureDocument respondsToSelector:@selector(hue)]];
//	[brightnessSlider setDoubleValue:[brightnessSlider isEnabled] ? [_captureDocument brightness] : 0.5f];
//	[contrastSlider setDoubleValue:[contrastSlider isEnabled] ? [_captureDocument contrast] : 0.5f];
//	[saturationSlider setDoubleValue:[saturationSlider isEnabled] ? [_captureDocument saturation] : 0.5f];
//	[hueSlider setDoubleValue:[hueSlider isEnabled] ? [_captureDocument hue] : 0.5f];
//	[self _snapSlider:brightnessSlider];
//	[self _snapSlider:contrastSlider];
//	[self _snapSlider:saturationSlider];
//	[self _snapSlider:hueSlider];
//
//	[upconvertsFromMonoSwitch setEnabled:[_captureDocument respondsToSelector:@selector(upconvertsFromMono)]];
//	[upconvertsFromMonoSwitch setState:[upconvertsFromMonoSwitch isEnabled] && [_captureDocument upconvertsFromMono]];
//
////	[self audioHardwareDevicesDidChange:nil];
}

#pragma mark -

- (void)audioHardwareDevicesDidChange:(NSNotification *)aNotif
{
//	[audioSourcePopUp removeAllItems];
//	ECVAudioDevice *const preferredInput = [_captureDocument audioInputOfCaptureHardware];
//	if(preferredInput) {
//		NSMenuItem *const item = [[[NSMenuItem alloc] initWithTitle:[preferredInput name] action:NULL keyEquivalent:@""] autorelease];
//		[item setRepresentedObject:preferredInput];
//		[[audioSourcePopUp menu] addItem:item];
//	}
//	for(ECVAudioDevice *const device in [ECVAudioDevice allDevicesInput:YES]) {
//		if(ECVEqualObjects(device, preferredInput)) continue;
//		NSMenuItem *const item = [[[NSMenuItem alloc] initWithTitle:[device name] action:NULL keyEquivalent:@""] autorelease];
//		[item setRepresentedObject:device];
//		[[audioSourcePopUp menu] addItem:item];
//	}
//	if([[audioSourcePopUp menu] numberOfItems] > 1) [[audioSourcePopUp menu] insertItem:[NSMenuItem separatorItem] atIndex:1];
//	[audioSourcePopUp selectItemAtIndex:[audioSourcePopUp indexOfItemWithRepresentedObject:[_captureDocument audioInput]]];
//	[audioSourcePopUp setEnabled:!![[audioSourcePopUp menu] numberOfItems]];
}
- (void)volumeDidChange:(NSNotification *)aNotif
{
//	if(![self isWindowLoaded]) return;
//	BOOL const volumeSupported = [_captureDocument respondsToSelector:@selector(volume)];
//	[volumeSlider setEnabled:volumeSupported];
//	if(volumeSupported) [volumeSlider setDoubleValue:[_captureDocument isMuted] ? 0.0f : [_captureDocument volume]];
//	else [volumeSlider setDoubleValue:1.0f];
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
	[(NSPanel *)[self window] setBecomesKeyOnlyIfNeeded:YES];
//	[[ECVAudioDevice class] ECV_addObserver:self selector:@selector(audioHardwareDevicesDidChange:) name:ECVAudioHardwareDevicesDidChangeNotification];
	[self setCaptureDocument:_captureDocument];
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
