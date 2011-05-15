/* Copyright (c) 2011, Ben Trask
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
#import <CoreVideo/CoreVideo.h>

enum {
	ECVDrawToHighField = 1 << 0,
	ECVDrawToLowField = 1 << 1,
	ECVDrawFromHighField = 1 << 2, // Unimplemented
	ECVDrawFromLowField = 1 << 3, // Unimplemented
	ECVDrawChannel1 = 1 << 4,
	ECVDrawChannel2 = 1 << 5,
	ECVDrawChannel3 = 1 << 6,
	ECVDrawChannel4 = 1 << 7,
	ECVDrawChannelMask = ECVDrawChannel1 | ECVDrawChannel2 | ECVDrawChannel3 | ECVDrawChannel4,
	ECVDrawBlended = 1 << 16,
};
typedef NSUInteger ECVPixelBufferDrawingOptions;

@interface ECVPixelBuffer : NSObject

- (NSRange)fullRange;
- (BOOL)lockIfHasBytes;

@end

@interface ECVPixelBuffer(ECVAbstract) <NSLocking>

- (ECVIntegerSize)pixelSize;
- (size_t)bytesPerRow;
- (OSType)pixelFormat;

- (void const *)bytes;
- (BOOL)hasBytes;
- (NSRange)validRange;

@end

@interface ECVPointerPixelBuffer : ECVPixelBuffer
{
	@private
	ECVIntegerSize _pixelSize;
	size_t _bytesPerRow;
	OSType _pixelFormat;

	void const *_bytes;
	NSRange _validRange;
}

- (id)initWithPixelSize:(ECVIntegerSize)pixelSize bytesPerRow:(size_t)bytesPerRow pixelFormat:(OSType)pixelFormat bytes:(void const *)bytes validRange:(NSRange)validRange;
- (void)invalidate;

@end

@interface ECVMutablePixelBuffer : ECVPixelBuffer

- (void)drawPixelBuffer:(ECVPixelBuffer *)src;
- (void)drawPixelBuffer:(ECVPixelBuffer *)src options:(ECVPixelBufferDrawingOptions)options;
- (void)drawPixelBuffer:(ECVPixelBuffer *)src options:(ECVPixelBufferDrawingOptions)options atPoint:(ECVIntegerPoint)point;

- (void)clearRange:(NSRange)range;
- (void)clear;

@end

@interface ECVMutablePixelBuffer(ECVAbstract)

- (void *)mutableBytes;

@end

@interface ECVCVPixelBuffer : ECVMutablePixelBuffer
{
	CVPixelBufferRef _pixelBuffer;
}

- (id)initWithPixelBuffer:(CVPixelBufferRef)pixelBuffer;

@end

@interface ECVDataPixelBuffer : ECVMutablePixelBuffer
{
	@private
	ECVIntegerSize _pixelSize;
	size_t _bytesPerRow;
	OSType _pixelFormat;

	NSMutableData *_data;
	NSUInteger _offset;
}

- (id)initWithPixelSize:(ECVIntegerSize)pixelSize bytesPerRow:(size_t)bytesPerRow pixelFormat:(OSType)pixelFormat data:(NSMutableData *)data offset:(NSUInteger)offset;
- (NSMutableData *)mutableData;

@end

@interface ECVConcreteMutablePixelBuffer : ECVMutablePixelBuffer
{
	@private
	ECVIntegerSize _pixelSize;
	size_t _bytesPerRow;
	OSType _pixelFormat;
	void *_bytes;
}

- (id)initWithPixelSize:(ECVIntegerSize)pixelSize bytesPerRow:(size_t)bytesPerRow pixelFormat:(OSType)pixelFormat;

@end
