/* Copyright (c) 2009-2010, Ben Trask
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
#import <QTKit/QTKit.h>

// Models
#import "ECVVideoFrame.h"

@interface ECVVideoStorage : NSObject
{
	@private
	OSType _pixelFormatType;
	ECVDeinterlacingMode _deinterlacingMode;
	ECVPixelSize _originalSize;
	QTTime _frameRate;
	size_t _bytesPerRow;
	size_t _bufferSize;

	NSRecursiveLock *_lock;
	NSMutableArray *_frames;
#ifdef ECV_DEPENDENT_VIDEO_STORAGE
	NSMutableIndexSet *_unusedBufferIndexes;

	NSUInteger _numberOfBuffers;
	NSMutableData *_allBufferData;
#endif
}

- (id)initWithPixelFormatType:(OSType)formatType deinterlacingMode:(ECVDeinterlacingMode)mode originalSize:(ECVPixelSize)size frameRate:(QTTime)frameRate;
@property(readonly) OSType pixelFormatType;
@property(readonly) ECVDeinterlacingMode deinterlacingMode;
@property(readonly) BOOL halfHeight;
@property(readonly) ECVPixelSize originalSize;
@property(readonly) ECVPixelSize pixelSize;
@property(readonly) QTTime frameRate;
@property(readonly) size_t bytesPerPixel;
@property(readonly) size_t bytesPerRow;
@property(readonly) size_t bufferSize;
@property(readonly) NSUInteger frameGroupSize;

- (ECVVideoFrame *)nextFrameWithFieldType:(ECVFieldType)type;

- (NSUInteger)numberOfCompletedFrames;
- (ECVVideoFrame *)newestCompletedFrame;
- (ECVVideoFrame *)oldestFrame;

#ifdef ECV_DEPENDENT_VIDEO_STORAGE
@property(readonly) NSUInteger numberOfBuffers;
@property(readonly) void *allBufferBytes;
- (void *)bufferBytesAtIndex:(NSUInteger)index;
#endif

- (NSUInteger)numberOfFramesToDropWithCount:(NSUInteger)c;
- (NSUInteger)dropFramesFromArray:(NSMutableArray *)frames;

@end

#ifdef ECV_DEPENDENT_VIDEO_STORAGE
@interface ECVVideoFrame(ECVDependentVideoFrame)

@property(readonly) NSUInteger bufferIndex;

@end
#endif
