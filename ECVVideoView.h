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

// Other Sources
#import "ECVFrameReading.h"

@protocol ECVVideoViewDelegate;

@interface ECVVideoView : NSOpenGLView <ECVFrameReading, NSWindowDelegate>
{
	@private
	NSMutableData *_bufferData;
	NSMutableData *_textureNames;
	NSUInteger _currentFillBufferIndex;
	NSUInteger _blurredBufferIndex;

	NSLock *_bufferPoolLock;
	NSMutableArray *_readyBufferIndexQueue;
	NSUInteger _currentDrawBufferIndex;
	CGFloat _frameDropStrength;
	OSType _pixelFormatType;
	ECVPixelSize _pixelSize;
	NSUInteger _bufferSize;

	NSRecursiveLock *_attachedFrameLock;
	NSMutableArray *_attachedFrames;
	NSMutableIndexSet *_attachedFrameIndexes;

	CVDisplayLinkRef _displayLink;
	NSRect _outputRect;

	IBOutlet NSObject<ECVVideoViewDelegate> *delegate;
	NSSize _aspectRatio;
	BOOL _vsync;
	GLint _magFilter;
	BOOL _showDroppedFrames;
}

// These methods must be called from the same thread.
- (void)setPixelFormat:(OSType)formatType size:(ECVPixelSize)size;

@property(assign, nonatomic) NSUInteger currentFillBufferIndex;
@property(readonly, nonatomic) NSUInteger currentDrawBufferIndex;
- (NSUInteger)bufferIndexByBlurringPastFrames;
- (NSUInteger)nextFillBufferIndex:(NSUInteger)bufferToDraw;
- (void)resetFrames;

- (void *)bufferBytesAtIndex:(NSUInteger)index;
- (void)clearBufferAtIndex:(NSUInteger)index;
- (void)drawBufferIndex:(NSUInteger)index;
- (id<ECVFrameReading>)frameWithBufferAtIndex:(NSUInteger)index;

// These mthods must be called from the main thread.
- (void)startDrawing;
- (void)stopDrawing;
@property(assign, nonatomic) NSSize aspectRatio;

// These methods are thread safe.
@property(assign) NSObject<ECVVideoViewDelegate> *delegate;
@property(assign) BOOL vsync;
@property(assign) GLint magFilter;
@property(assign) BOOL showDroppedFrames;

@end

@protocol ECVVideoViewDelegate <NSObject>

@optional
- (BOOL)videoView:(ECVVideoView *)sender handleKeyDown:(NSEvent *)anEvent;
- (BOOL)videoView:(ECVVideoView *)sender handleMouseDown:(NSEvent *)anEvent;

@end
