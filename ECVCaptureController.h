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
#import <IOKit/usb/IOUSBLib.h>
#import <QuartzCore/QuartzCore.h>
#import <QTKit/QTKit.h>

// Models
@class ECVVideoFrame;

// Views
#import "ECVVideoView.h"
@class ECVPlayButtonCell;
#import "ECVCropCell.h"

// Controllers
#import "ECVConfigController.h"

// Other Sources
#import "ECVAudioDevice.h"
@class ECVAudioPipe;
@class ECVSoundTrack;
@class ECVVideoTrack;

enum {
	ECV1x1AspectRatio = 3,
	ECV4x3AspectRatio = 0,
	ECV3x2AspectRatio = 4,
	ECV16x10AspectRatio = 2,
	ECV16x9AspectRatio = 1,
};
typedef NSUInteger ECVAspectRatio;

enum {
	ECVUncropped = 0,
	ECVCrop2_5Percent = 1,
	ECVCrop5Percent = 2,
	ECVCrop10Percent = 3,
	ECVCropLetterbox16x9 = 4,
	ECVCropLetterbox16x10 = 5,
};
typedef NSUInteger ECVCropType;

enum {
	ECVFullFrame = 0,
	ECVHighField = 1,
	ECVLowField = 2,
};
typedef NSUInteger ECVFieldType;

enum {
	ECVWeave = 0,
	ECVLineDouble = 1,
	ECVAlternate = 2,
	ECVBlur = 3,
};
typedef NSInteger ECVDeinterlacingMode;

extern NSString *const ECVDeinterlacingModeKey;
extern NSString *const ECVBrightnessKey;
extern NSString *const ECVContrastKey;
extern NSString *const ECVHueKey;
extern NSString *const ECVSaturationKey;

@interface ECVCaptureController : NSWindowController <ECVAudioDeviceDelegate, ECVCaptureControllerConfiguring, ECVCropCellDelegate, ECVVideoViewDelegate, NSWindowDelegate>
{
	@private
	IBOutlet ECVVideoView *videoView;
	IBOutlet NSView *exportAccessoryView;
	IBOutlet NSPopUpButton *videoCodecPopUp;
	IBOutlet NSSlider *videoQualitySlider;

	io_service_t _device;
	NSString *_productName;

	io_object_t _deviceRemovedNotification;
	IOUSBDeviceInterface182 **_deviceInterface;
	IOUSBInterfaceInterface197 **_interfaceInterface;
	UInt32 _frameTime;

	size_t _pendingImageLength;
	ECVFieldType _fieldType;
	ECVDeinterlacingMode _deinterlacingMode;
	NSConditionLock *_playLock;
	BOOL _firstFrame;
	ECVVideoFrame *_pendingFrame;
	ECVVideoFrame *_lastCompletedFrame;

	ECVAudioDevice *_audioInput;
	ECVAudioDevice *_audioOutput;
	ECVAudioPipe *_audioPreviewingPipe;
	CGFloat _volume;

	QTMovie *_movie;
	ECVVideoTrack *_videoTrack;
	ECVSoundTrack *_soundTrack;
	ECVAudioPipe *_audioRecordingPipe;

	BOOL _fullScreen;
	BOOL _noteDeviceRemovedWhenSheetCloses;
	ECVPlayButtonCell *_playButtonCell;
}

+ (BOOL)deviceAddedWithIterator:(io_iterator_t)iterator;

- (id)initWithDevice:(io_service_t)device error:(out NSError **)outError;
- (void)noteDeviceRemoved;
- (void)workspaceWillSleep:(NSNotification *)aNotif;

- (IBAction)play:(id)sender;
- (IBAction)pause:(id)sender;
- (IBAction)togglePlaying:(id)sender;

- (IBAction)startRecording:(id)sender;
- (IBAction)stopRecording:(id)sender;
- (IBAction)changeCodec:(id)sender;

- (IBAction)toggleFullScreen:(id)sender;
- (IBAction)changeScale:(id)sender;
- (IBAction)changeAspectRatio:(id)sender;
- (IBAction)changeCropType:(id)sender;
- (IBAction)enterCropMode:(id)sender;
- (IBAction)toggleFloatOnTop:(id)sender;
- (IBAction)toggleVsync:(id)sender;
- (IBAction)toggleSmoothing:(id)sender;
- (IBAction)toggleShowDroppedFrames:(id)sender;

@property(assign) NSSize aspectRatio;
@property(assign) NSRect cropRect;
@property(assign) ECVDeinterlacingMode deinterlacingMode;
@property(assign, getter = isFullScreen) BOOL fullScreen;
@property(assign, getter = isPlaying) BOOL playing;
@property(assign) NSSize windowContentSize;
@property(readonly) NSSize outputSize;
- (NSSize)outputSizeWithScale:(NSInteger)scale;
- (NSSize)sizeWithAspectRatio:(ECVAspectRatio)ratio;
- (NSRect)cropRectWithType:(ECVCropType)type;
- (NSRect)cropRectWithAspectRatio:(ECVAspectRatio)ratio;

@property(readonly) ECVAudioDevice *audioInputOfCaptureHardware;
@property(retain) ECVAudioDevice *audioInput;
@property(retain) ECVAudioDevice *audioOutput;
- (BOOL)startAudio;
- (void)stopAudio;

- (void)threaded_readIsochPipeAsync;
- (void)threaded_readImageBytes:(UInt8 const *)bytes length:(size_t)length;
- (void)threaded_startNewImageWithFieldType:(ECVFieldType)fieldType;

- (BOOL)setAlternateInterface:(UInt8)alternateSetting;
- (BOOL)controlRequestWithType:(UInt8)type request:(UInt8)request value:(UInt16)value index:(UInt16)index length:(UInt16)length data:(void *)data;
- (BOOL)writeValue:(UInt16)value atIndex:(UInt16)index;
- (BOOL)readValue:(out SInt32 *)outValue atIndex:(UInt16)index;
- (BOOL)setFeatureAtIndex:(UInt16)index;

@end

@interface ECVCaptureController(ECVAbstract)

@property(readonly) BOOL requiresHighSpeed;
@property(readonly) ECVPixelSize captureSize;
@property(readonly) NSUInteger simultaneousTransfers;
@property(readonly) NSUInteger microframesPerTransfer;
@property(readonly) UInt8 isochReadingPipe;
@property(readonly) QTTime frameRate;

- (BOOL)threaded_play;
- (BOOL)threaded_pause;
- (BOOL)threaded_watchdog;
- (void)threaded_readFrame:(IOUSBLowLatencyIsocFrame *)frame bytes:(UInt8 const *)bytes;

@end
