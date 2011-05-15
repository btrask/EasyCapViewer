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
#import "ECVStorage.h"
#import "ECVPixelBuffer.h"
#import <QTKit/QTKit.h>

// Models/Pipes/Video
@class ECVVideoPipe;

// Other Sources
#import "ECVRational.h"

@protocol ECVVideoStorageDelegate;
@class ECVVideoFrame;

@interface ECVVideoStorage : ECVStorage <NSLocking>
{
	@private
	NSRecursiveLock *_lock;
	NSObject<ECVVideoStorageDelegate> *_delegate;
	ECVIntegerSize _pixelSize;
	OSType _pixelFormat;
	QTTime _frameRate;
	ECVRational _pixelAspectRatio;
	BOOL _read;
}

@property(assign) NSObject<ECVVideoStorageDelegate> *delegate;
@property(assign) ECVIntegerSize pixelSize;
@property(assign) OSType pixelFormat;
@property(assign) QTTime frameRate;
@property(assign) ECVRational pixelAspectRatio;

@property(readonly) size_t bytesPerPixel;
@property(readonly) size_t bytesPerRow;
@property(readonly) size_t bufferSize;

- (void)addVideoPipe:(ECVVideoPipe *)pipe;
- (void)removeVideoPipe:(ECVVideoPipe *)pipe;

@end

@interface ECVVideoStorage(ECVAbstract)

- (ECVVideoFrame *)currentFrame;

- (ECVMutablePixelBuffer *)nextBuffer;
- (ECVVideoFrame *)finishedFrameWithFinishedBuffer:(id)buffer;

@end

@interface ECVVideoStorage(ECVFromPipe_Thread)

- (void)videoPipeDidFinishFrame:(ECVVideoPipe *)pipe;
- (void)videoPipe:(ECVVideoPipe *)pipe drawPixelBuffer:(ECVPixelBuffer *)buffer;

@end

@protocol ECVVideoStorageDelegate

- (void)videoStorage:(ECVVideoStorage *)storage didFinishFrame:(ECVVideoFrame *)frame;

@end

@interface ECVVideoFrame : ECVPixelBuffer
{
	@private
	ECVVideoStorage *_videoStorage;
}

- (id)initWithVideoStorage:(ECVVideoStorage *)storage;
@property(readonly) id videoStorage;

@end

@interface ECVVideoFrame(ECVAbstract) <NSLocking>

- (void const *)bytes;
- (BOOL)hasBytes;

@end
