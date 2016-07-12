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
#import <OpenGL/gl.h>
#import <QuartzCore/QuartzCore.h>

// Models
@class ECVDependentVideoStorage;
@class ECVVideoFrame;

@protocol ECVVideoViewCell, ECVVideoViewDelegate;

@interface ECVVideoView : NSOpenGLView
#if defined(MAC_OS_X_VERSION_10_6)
<NSWindowDelegate>
#endif
{
	@private
	CVDisplayLinkRef _displayLink;
	NSRect _outputRect;

	IBOutlet NSObject<ECVVideoViewDelegate> *delegate;
	ECVDependentVideoStorage *_videoStorage;
	NSSize _aspectRatio;
	NSRect _cropRect;
	BOOL _vsync;
	GLint _magFilter;
	BOOL _showDroppedFrames;
	NSCell<ECVVideoViewCell> *_cell;

	NSMutableData *_textureNames;
	NSMutableArray *_frames;
	CGFloat _frameDropStrength;
}

// These methods must be called from the main thread.
- (void)startDrawing;
- (void)stopDrawing;

// These methods are thread safe.
- (ECVDependentVideoStorage *)videoStorage;
- (void)setVideoStorage:(id)storage;
@property(assign) NSObject<ECVVideoViewDelegate> *delegate;
@property(assign) NSSize aspectRatio;
@property(assign) NSRect cropRect;
@property(assign) BOOL vsync;
@property(assign) GLint magFilter;
@property(assign) BOOL showDroppedFrames;
@property(nonatomic, retain) NSCell<ECVVideoViewCell> *cell;
- (void)pushFrame:(ECVVideoFrame *)frame;

@end

@protocol ECVVideoViewCell <NSObject>
@required
- (void)drawWithFrame:(NSRect)r inVideoView:(ECVVideoView *)v playing:(BOOL)flag;
@end

@protocol ECVVideoViewDelegate <NSObject>
@optional
- (BOOL)videoView:(ECVVideoView *)sender handleKeyDown:(NSEvent *)anEvent;
@end
