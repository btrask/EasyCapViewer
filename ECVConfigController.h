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
// Models
@class ECVCaptureDevice;

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
	IBOutlet NSButtonCell *upconvertsFromMonoSwitch;
	IBOutlet NSSlider *volumeSlider;

	ECVCaptureDevice *_captureDevice;
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
- (IBAction)changeUpconvertsFromMono:(id)sender;
- (IBAction)changeVolume:(id)sender;

@property(nonatomic, assign) ECVCaptureDevice *captureDevice;

- (void)audioHardwareDevicesDidChange:(NSNotification *)aNotif;
- (void)volumeDidChange:(NSNotification *)aNotif;

@end

@protocol ECVCaptureDeviceConfiguring<NSObject>

@optional
@property(readonly) NSArray *allVideoSourceObjects;
@property(nonatomic, assign) id videoSourceObject;
- (NSString *)localizedStringForVideoSourceObject:(id)obj;
- (BOOL)isValidVideoSourceObject:(id)obj;
- (NSInteger)indentationLevelForVideoSourceObject:(id)obj;

@property(readonly) NSArray *allVideoFormatObjects;
@property(nonatomic, assign) id videoFormatObject;
- (NSString *)localizedStringForVideoFormatObject:(id)obj;
- (BOOL)isValidVideoFormatObject:(id)obj;
- (NSInteger)indentationLevelForVideoFormatObject:(id)obj;

@property(nonatomic, assign) CGFloat brightness;
@property(nonatomic, assign) CGFloat contrast;
@property(nonatomic, assign) CGFloat saturation;
@property(nonatomic, assign) CGFloat hue;
@property(nonatomic, assign, getter=isMuted) BOOL muted;
@property(nonatomic, assign) CGFloat volume;
@property(nonatomic, assign) BOOL upconvertsFromMono;

@end
