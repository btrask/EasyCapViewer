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
#import "ECVConfigController.h"

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
	BOOL const playing = _captureController.playing;
	if(playing) _captureController.playing = NO;
	_captureController.videoFormatObject = [[sender selectedItem] representedObject];
	if(playing) _captureController.playing = YES;
}
- (IBAction)changeSource:(id)sender
{
	BOOL const playing = _captureController.playing;
	if(playing) _captureController.playing = NO;
	_captureController.videoSourceObject = [[sender selectedItem] representedObject];
	if(playing) _captureController.playing = YES;
}
- (IBAction)changeDeinterlacing:(id)sender
{
	BOOL const playing = _captureController.playing;
	if(playing) _captureController.playing = NO;
	_captureController.deinterlacingMode = [sender selectedTag];
	if(playing) _captureController.playing = YES;
}
- (IBAction)changeBrightness:(id)sender
{
	[self _snapSlider:sender];
	_captureController.brightness = [sender doubleValue];
}
- (IBAction)changeContrast:(id)sender
{
	[self _snapSlider:sender];
	_captureController.contrast = [sender doubleValue];
}
- (IBAction)changeSaturation:(id)sender
{
	[self _snapSlider:sender];
	_captureController.saturation = [sender doubleValue];
}
- (IBAction)changeHue:(id)sender
{
	[self _snapSlider:sender];
	_captureController.hue = [sender doubleValue];
}

#pragma mark -

@synthesize captureController = _captureController;
- (void)setCaptureController:(ECVCaptureController<ECVCaptureControllerConfiguring> *)c
{
	(void)[self window]; // Load.

	_captureController = c;

	[sourcePopUp removeAllItems];
	if([_captureController respondsToSelector:@selector(allVideoSourceObjects)]) for(id const videoSourceObject in _captureController.allVideoSourceObjects) {
		if([NSNull null] == videoSourceObject) {
			[[sourcePopUp menu] addItem:[NSMenuItem separatorItem]];
			continue;
		}
		NSMenuItem *const item = [[[NSMenuItem alloc] initWithTitle:[_captureController localizedStringForVideoSourceObject:videoSourceObject] action:NULL keyEquivalent:@""] autorelease];
		[item setRepresentedObject:videoSourceObject];
		[item setEnabled:[_captureController isValidVideoSourceObject:videoSourceObject]];
		[item setIndentationLevel:[_captureController indentationLevelForVideoSourceObject:videoSourceObject]];
		[[sourcePopUp menu] addItem:item];
	}
	[sourcePopUp setEnabled:[_captureController respondsToSelector:@selector(videoSourceObject)]];
	if([sourcePopUp isEnabled]) [sourcePopUp selectItemAtIndex:[sourcePopUp indexOfItemWithRepresentedObject:_captureController.videoSourceObject]];

	[formatPopUp removeAllItems];
	if([_captureController respondsToSelector:@selector(allVideoFormatObjects)]) for(id const videoFormatObject in _captureController.allVideoFormatObjects) {
		if([NSNull null] == videoFormatObject) {
			[[formatPopUp menu] addItem:[NSMenuItem separatorItem]];
			continue;
		}
		NSMenuItem *const item = [[[NSMenuItem alloc] initWithTitle:[_captureController localizedStringForVideoFormatObject:videoFormatObject] action:NULL keyEquivalent:@""] autorelease];
		[item setRepresentedObject:videoFormatObject];
		[item setEnabled:[_captureController isValidVideoFormatObject:videoFormatObject]];
		[item setIndentationLevel:[_captureController indentationLevelForVideoFormatObject:videoFormatObject]];
		[[formatPopUp menu] addItem:item];
	}
	[formatPopUp setEnabled:[_captureController respondsToSelector:@selector(videoFormatObject)]];
	if([formatPopUp isEnabled]) [formatPopUp selectItemAtIndex:[formatPopUp indexOfItemWithRepresentedObject:_captureController.videoFormatObject]];

	[deinterlacePopUp selectItemWithTag:_captureController.deinterlacingMode];
	[deinterlacePopUp setEnabled:!!_captureController];

	[brightnessSlider setEnabled:[_captureController respondsToSelector:@selector(brightness)]];
	[contrastSlider setEnabled:[_captureController respondsToSelector:@selector(contrast)]];
	[saturationSlider setEnabled:[_captureController respondsToSelector:@selector(saturation)]];
	[hueSlider setEnabled:[_captureController respondsToSelector:@selector(hue)]];
	[brightnessSlider setDoubleValue:[brightnessSlider isEnabled] ? _captureController.brightness : 0.5f];
	[contrastSlider setDoubleValue:[contrastSlider isEnabled] ? _captureController.contrast : 0.5f];
	[saturationSlider setDoubleValue:[saturationSlider isEnabled] ? _captureController.saturation : 0.5f];
	[hueSlider setDoubleValue:[hueSlider isEnabled] ? _captureController.hue : 0.5f];
	[self _snapSlider:brightnessSlider];
	[self _snapSlider:contrastSlider];
	[self _snapSlider:saturationSlider];
	[self _snapSlider:hueSlider];
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
	[[self window] center];
}

#pragma mark -NSObject

- (id)init
{
	return [super initWithWindowNibName:@"ECVConfig"];
}

@end
