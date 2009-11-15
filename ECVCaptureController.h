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
#import <QuartzCore/QuartzCore.h>

// Models
@class ECVVideoFrame;

// Views
#import "ECVVideoView.h"
@class ECVPlayButtonCell;
#import "ECVCropCell.h"

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

@interface ECVCaptureController : NSWindowController <ECVCropCellDelegate, ECVVideoViewDelegate, NSWindowDelegate>
{
	@private
	IBOutlet ECVVideoView *videoView;
	BOOL _fullScreen;
	ECVPlayButtonCell *_playButtonCell;
}

- (IBAction)cloneViewer:(id)sender;

- (IBAction)play:(id)sender;
- (IBAction)pause:(id)sender;
- (IBAction)togglePlaying:(id)sender;

- (IBAction)startRecording:(id)sender;
- (IBAction)stopRecording:(id)sender;

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
@property(assign, getter = isFullScreen) BOOL fullScreen;
@property(assign) NSSize windowContentSize;
@property(readonly) NSSize outputSize;
- (NSSize)outputSizeWithScale:(NSInteger)scale;
- (NSSize)sizeWithAspectRatio:(ECVAspectRatio)ratio;
- (NSRect)cropRectWithType:(ECVCropType)type;
- (NSRect)cropRectWithAspectRatio:(ECVAspectRatio)ratio;

- (void)startPlaying;
- (void)stopPlaying;
- (void)threaded_pushFrame:(ECVVideoFrame *)frame;

@end
