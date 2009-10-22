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
#import <Cocoa/Cocoa.h>

// Controllers
@class ECVCaptureController;

@protocol ECVCaptureControllerConfiguring;

@interface ECVConfigController : NSWindowController
{
	@private
	IBOutlet NSPopUpButton *sourcePopUp;
	IBOutlet NSPopUpButton *formatPopUp;
	IBOutlet NSPopUpButton *deinterlacePopUp;
	IBOutlet NSSlider *brightnessSlider;
	IBOutlet NSSlider *contrastSlider;
	IBOutlet NSSlider *hueSlider;
	IBOutlet NSSlider *saturationSlider;

	IBOutlet NSPopUpButton *audioSourcePopUp;
	IBOutlet NSSlider *volumeSlider;

	ECVCaptureController *_captureController;
}

+ (id)sharedConfigController;

- (IBAction)changeFormat:(id)sender;
- (IBAction)changeSource:(id)sender;
- (IBAction)changeDeinterlacing:(id)sender;
- (IBAction)changeBrightness:(id)sender;
- (IBAction)changeContrast:(id)sender;
- (IBAction)changeSaturation:(id)sender;
- (IBAction)changeHue:(id)sender;
- (IBAction)changeAudioInput:(id)sender;
- (IBAction)changeVolume:(id)sender;

@property(assign) ECVCaptureController *captureController;

- (void)audioHardwareDevicesDidChange:(NSNotification *)aNotif;

@end

@protocol ECVCaptureControllerConfiguring <NSObject>

@optional
@property(readonly) NSArray *allVideoSourceObjects;
@property(assign) id videoSourceObject;
- (NSString *)localizedStringForVideoSourceObject:(id)obj;
- (BOOL)isValidVideoSourceObject:(id)obj;
- (NSInteger)indentationLevelForVideoSourceObject:(id)obj;

@property(readonly) NSArray *allVideoFormatObjects;
@property(assign) id videoFormatObject;
- (NSString *)localizedStringForVideoFormatObject:(id)obj;
- (BOOL)isValidVideoFormatObject:(id)obj;
- (NSInteger)indentationLevelForVideoFormatObject:(id)obj;

@property(assign) CGFloat brightness;
@property(assign) CGFloat contrast;
@property(assign) CGFloat saturation;
@property(assign) CGFloat hue;
@property(assign) CGFloat volume;

@end
