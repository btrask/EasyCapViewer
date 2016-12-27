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

// Models
@class ECVVideoFormat;
@class ECVDeinterlacingMode;
@class ECVPixelBuffer;
@class ECVMutablePixelBuffer;
@class ECVVideoFrame;

@interface ECVVideoStorage : NSObject <NSLocking>
{
	@private
	ECVVideoFormat *_videoFormat;
	ECVDeinterlacingMode *_deinterlacingMode;
	OSType _pixelFormat;
	size_t _bytesPerRow;
	size_t _bufferSize;
	NSRecursiveLock *_lock;
}

+ (Class)preferredVideoStorageClass;

- (id)initWithVideoFormat:(ECVVideoFormat *const)videoFormat deinterlacingMode:(Class const)mode pixelFormat:(OSType const)pixelFormat;
- (ECVVideoFormat *)videoFormat;
- (OSType)pixelFormat;
- (size_t)bytesPerPixel;
- (size_t)bytesPerRow;
- (size_t)bufferSize;

- (NSUInteger)numberOfFramesToDropWithCount:(NSUInteger)c;
- (NSUInteger)dropFramesFromArray:(NSMutableArray *)frames;

- (ECVVideoFrame *)finishedFrameWithNextFieldType:(ECVFieldType)fieldType;
- (void)drawPixelBuffer:(ECVPixelBuffer *)buffer atPoint:(ECVIntegerPoint)point;

@end

@interface ECVVideoStorage(ECVAbstract)

- (ECVVideoFrame *)currentFrame;

- (ECVMutablePixelBuffer *)nextBuffer;
- (ECVVideoFrame *)finishedFrameWithFinishedBuffer:(id)buffer;

- (void)empty;

@end
