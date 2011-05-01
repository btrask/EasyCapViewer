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
#import "ECVCaptureDocument.h"
#import <QuartzCore/QuartzCore.h>
#import <QTKit/QTKit.h>

// Models
@class ECVVideoFrame;
@class ECVMovieRecorder;

// Views
#import "ECVVideoView.h"
@class ECVPlayButtonCell;
#import "ECVCropCell.h"

// External
@class BTUserDefaults;

enum {
	ECVAspectRatioUnknown = -1,
	ECVAspectRatio1x1 = 3,
	ECVAspectRatio4x3 = 0,
	ECVAspectRatio3x2 = 4,
	ECVAspectRatio16x10 = 2,
	ECVAspectRatio16x9 = 1,
};
typedef NSInteger ECVAspectRatio;
enum {
	ECVCropBorderCustom = -1,
	ECVCropBorderNone = 0,
	ECVCropBorder2_5Percent = 1,
	ECVCropBorder5Percent = 2,
	ECVCropBorder10Percent = 3,
};
typedef NSInteger ECVCropBorder;

@interface ECVCaptureController : NSWindowController <ECVCropCellDelegate, ECVVideoViewDelegate
#if defined(MAC_OS_X_VERSION_10_6)
, NSWindowDelegate
#endif
>
{
	@private
	IBOutlet ECVVideoView *videoView;
	IBOutlet NSView *exportAccessoryView;
	IBOutlet NSPopUpButton *videoCodecPopUp;
	IBOutlet NSSlider *videoQualitySlider;
	IBOutlet NSButton *halfFrameRate;
	IBOutlet NSButton *stretchTotAspectRatio;
	IBOutlet NSButton *recordToRAMButton;

	BOOL _fullScreen;
	ECVPlayButtonCell *_playButtonCell;
	ECVMovieRecorder *_movieRecorder;

	ECVCropBorder _cropBorder;
	ECVAspectRatio _cropSourceAspectRatio;
}

- (IBAction)cloneViewer:(id)sender;

- (IBAction)play:(id)sender;
- (IBAction)pause:(id)sender;
- (IBAction)togglePlaying:(id)sender;

- (IBAction)startRecording:(id)sender;
- (IBAction)stopRecording:(id)sender;
- (IBAction)changeCodec:(id)sender;
- (IBAction)showRecordsToRAMInfo:(id)sender;

- (IBAction)toggleFullScreen:(id)sender;
- (IBAction)changeScale:(id)sender;
- (IBAction)changeAspectRatio:(id)sender;

- (IBAction)uncrop:(id)sender;
- (IBAction)changeCropSourceAspectRatio:(id)sender;
- (IBAction)changeCropBorder:(id)sender;
- (IBAction)enterCustomCropMode:(id)sender;

- (IBAction)toggleFloatOnTop:(id)sender;
- (IBAction)toggleVsync:(id)sender;
- (IBAction)toggleSmoothing:(id)sender;
- (IBAction)toggleShowDroppedFrames:(id)sender;

@property(readonly) BTUserDefaults *defaults;
@property(assign) NSSize aspectRatio;
@property(readonly) NSRect cropRect;
@property(nonatomic, assign, getter = isFullScreen) BOOL fullScreen;
@property(nonatomic, assign) NSSize windowContentSize;
@property(readonly) NSSize outputSize;
- (NSSize)outputSizeWithScale:(NSInteger)scale;
- (NSSize)sizeWithAspectRatio:(ECVAspectRatio)ratio;
- (NSRect)cropRectWithSourceAspectRatio:(ECVAspectRatio)type;
- (NSRect)cropRect:(NSRect)rect withBorder:(ECVCropBorder)border;

@end

@interface ECVCaptureController(ECVFromDocument) <ECVAVReceiving>

- (void)play;
- (void)stop;

@end
