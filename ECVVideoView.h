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
#import <OpenGL/gl.h>
#import <QuartzCore/QuartzCore.h>
#import "ECVFrameReading.h"

// Models
@class ECVFrame;

typedef enum {
	ECVBufferFillGarbage,
	ECVBufferFillClear,
	ECVBufferFillPrevious,
} ECVBufferFillType;

@interface ECVVideoView : NSOpenGLView <ECVFrameReading>
{
	@private
	OSType _pixelFormatType;
	ECVPixelSize _pixelSize;
	NSUInteger _bufferSize;
	NSUInteger _numberOfBuffers;
	NSTimeInterval _frameStartTime;

	NSMutableData *_bufferData;
	NSMutableData *_textureNames;
	NSUInteger _fillingBufferIndex;
	NSUInteger _lastFilledBufferIndex;

	// Access to these ivars must be @synchronized.
	NSMutableArray *_readyBufferIndexQueue;
	CGFloat _frameDropStrength;

	CVDisplayLinkRef _displayLink;
	NSRect _outputRect;

	IBOutlet id delegate;
	BOOL _blurFramesTogether;
	NSSize _aspectRatio;
	BOOL _vsync;
	GLint _magFilter;
	BOOL _showDroppedFrames;
}

- (void)configureWithPixelFormat:(OSType)formatType size:(ECVPixelSize)size numberOfBuffers:(NSUInteger)numberOfBuffers; // NOT thread safe.

- (void)createNewBuffer:(ECVBufferFillType)fill time:(NSTimeInterval)time blendLastTwoBuffers:(BOOL)blend getLastFrame:(out ECVFrame **)outFrame; // NOT thread safe.
@property(readonly) void *mutableBufferBytes; // NOT thread safe.

@property(assign) id delegate;
@property(assign) BOOL blurFramesTogether;
@property(assign) NSSize aspectRatio;
@property(assign) BOOL vsync;
@property(assign) GLint magFilter;
@property(assign) BOOL showDroppedFrames;

@end

@interface NSObject (ECVVideoViewDelegate)

- (BOOL)videoView:(ECVVideoView *)sender handleKeyDown:(NSEvent *)anEvent;

@end