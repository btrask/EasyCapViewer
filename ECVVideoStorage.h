/* Copyright (c) 2009-2010, Ben Trask
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
#import <QTKit/QTKit.h>

// Models
#import "ECVVideoFrame.h"
@class ECVDeinterlacingMode;

@interface ECVVideoStorage : NSObject <NSLocking>
{
	@private
	ECVDeinterlacingMode *_deinterlacingMode;
	ECVIntegerSize _captureSize;
	OSType _pixelFormatType;
	QTTime _frameRate;
	size_t _bytesPerRow;
	size_t _bufferSize;

	NSRecursiveLock *_lock;
	NSMutableArray *_frames;
}

+ (Class)preferredVideoStorageClass;

- (id)initWithDeinterlacingMode:(Class)mode captureSize:(ECVIntegerSize)captureSize pixelFormat:(OSType)pixelFormatType frameRate:(QTTime)frameRate;
@property(readonly) ECVDeinterlacingMode *deinterlacingMode; // TODO: Ideally this should not be exposed.
@property(readonly) ECVIntegerSize captureSize;
@property(readonly) ECVIntegerSize pixelSize;
@property(readonly) OSType pixelFormatType;
@property(readonly) QTTime frameRate;
@property(readonly) size_t bytesPerPixel;
@property(readonly) size_t bytesPerRow;
@property(readonly) size_t bufferSize;

- (ECVVideoFrame *)currentFrame;

- (NSUInteger)numberOfFramesToDropWithCount:(NSUInteger)c;
- (NSUInteger)dropFramesFromArray:(NSMutableArray *)frames;

// Overriding (do not call these directly):
- (ECVVideoFrame *)generateFrameWithFrieldType:(ECVFieldType)type;
- (void)removeOldestFrameGroup; // Called from -nextFrameWithFieldType:. Must lock first.
- (void)addVideoFrame:(ECVVideoFrame *)frame; // Called from -nextFrameWithFieldType:. Must lock first.
- (BOOL)removeFrame:(ECVVideoFrame *)frame; // Called from -[ECVVideoFrame(ECVAbstract) removeFromStorageIfPossible].
- (void)removingFrame:(ECVVideoFrame *)frame;

@end

@interface ECVVideoFrameBuilder : NSObject
{
	@private
	NSThread *_thread;
	ECVVideoStorage *_videoStorage;
	BOOL _firstFrame;
	ECVVideoFrame *_pendingFrame;
}

- (id)initWithVideoStorage:(ECVVideoStorage *)storage;
@property(readonly) ECVVideoStorage *videoStorage;

- (ECVVideoFrame *)completedFrame;
- (void)startNewFrameWithFieldType:(ECVFieldType)type;
- (void)appendBytes:(void const *)bytes length:(size_t)length;

@end
