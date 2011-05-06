/* Copyright (c) 2010-2011, Ben Trask
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
#import "ECVDeinterlacer.h"

// Models
#import "ECVVideoStorage.h"

// Other Sources
#import "ECVFoundationAdditions.h"

static ECVPixelBufferDrawingOptions ECVFieldTypeDrawingOptions(ECVFieldType fieldType)
{
	switch(fieldType) {
		case ECVHighField: return ECVDrawToHighField;
		case ECVLowField: return ECVDrawToLowField;
		case ECVFullFrame: return kNilOptions;
	}
	ECVCAssertNotReached(@"Invalid field type.");
	return kNilOptions;
}

@implementation ECVDeinterlacer

#pragma mark +ECVDeinterlacer

+ (Class)deinterlacerWithType:(ECVDeinterlacerType)type
{
	Class c = Nil;
	switch(type) {
		case ECVProgressiveScan:
			c = [ECVProgressiveScanMode class]; break;
		case ECVWeave:
			c = [ECVWeaveDeinterlacer class]; break;
		case ECVLineDoubleLQ:
			c = [ECVLineDoubleLQDeinterlacer class]; break;
		case ECVLineDoubleHQ:
			c = [ECVLineDoubleHQDeinterlacer class]; break;
		case ECVAlternate:
			c = [ECVAlternateDeinterlacer class]; break;
		case ECVBlur:
			c = [ECVBlurDeinterlacer class]; break;
		case ECVDrop:
			c = [ECVDropDeinterlacer class]; break;
	}
	return c;
}

#pragma mark -ECVDeinterlacer

- (id)initWithVideoStorage:(ECVVideoStorage *)storage
{
	if((self = [super init])) {
		_videoStorage = storage;
	}
	return self;
}
- (ECVVideoStorage *)videoStorage
{
	return _videoStorage;
}
- (ECVIntegerSize)pixelSize
{
	return [_videoStorage captureSize];
}
- (ECVIntegerPoint)pixelPointForPoint:(ECVIntegerPoint)point
{
	return point;
}
- (NSUInteger)frameGroupSize
{
	return 2;
}
- (ECVMutablePixelBuffer *)pendingBuffer
{
	return _pendingBuffer;
}

#pragma mark -

- (ECVMutablePixelBuffer *)nextBufferWithFieldType:(ECVFieldType)fieldType
{
	[_videoStorage lock];
	ECVMutablePixelBuffer *const buffer = [_videoStorage nextBuffer];
	[_videoStorage unlock];
	return buffer;
}
- (ECVMutablePixelBuffer *)finishedBufferWithNextFieldType:(ECVFieldType)fieldType
{
	ECVMutablePixelBuffer *const finishedBuffer = [_pendingBuffer autorelease];
	_pendingBuffer = [[self nextBufferWithFieldType:fieldType] retain];
	return finishedBuffer;
}
- (void)drawPixelBuffer:(ECVPixelBuffer *)buffer atPoint:(ECVIntegerPoint)point
{
	[_pendingBuffer lock];
	[_pendingBuffer drawPixelBuffer:buffer options:[self drawingOptions] atPoint:[self pixelPointForPoint:point]];
	[_pendingBuffer unlock];
}
- (ECVPixelBufferDrawingOptions)drawingOptions
{
	return kNilOptions;
}
- (void)clearPendingBuffer
{
	[_pendingBuffer lock];
	[_pendingBuffer clear];
	[_pendingBuffer unlock];
}

#pragma mark -NSObject

- (void)dealloc
{
	[_pendingBuffer release];
	[super dealloc];
}

@end

@implementation ECVProgressiveScanMode

#pragma mark +ECVDeinterlacer(ECVAbstract)

+ (ECVDeinterlacerType)deinterlacerType
{
	return ECVProgressiveScan;
}

#pragma mark -ECVDeinterlacer

- (NSUInteger)frameGroupSize
{
	return 1;
}

@end

@implementation ECVLineDoubleHQDeinterlacer

#pragma mark +ECVDeinterlacer(ECVAbstract)

+ (ECVDeinterlacerType)deinterlacerType
{
	return ECVLineDoubleHQ;
}

#pragma mark -ECVDeinterlacer

- (ECVMutablePixelBuffer *)finishedBufferWithNextFieldType:(ECVFieldType)fieldType
{
	ECVMutablePixelBuffer *const finishedBuffer = [super finishedBufferWithNextFieldType:fieldType];
	switch(fieldType) {
		case ECVHighField: {
			_rowOffset = 0;
			break;
		}
		case ECVLowField: {
			ECVMutablePixelBuffer *const pendingBuffer = [self pendingBuffer];
			[pendingBuffer lock];
			[pendingBuffer clearRange:NSMakeRange(0, [pendingBuffer bytesPerRow])];
			[pendingBuffer unlock];
			_rowOffset = 1;
			break;
		}
	}
	return finishedBuffer;
}
- (void)drawPixelBuffer:(ECVPixelBuffer *)buffer atPoint:(ECVIntegerPoint)point
{
	[super drawPixelBuffer:buffer atPoint:(ECVIntegerPoint){point.x, point.y + _rowOffset}];
}
- (ECVPixelBufferDrawingOptions)drawingOptions
{
	return ECVDrawToHighField | ECVDrawToLowField;
}

@end

@implementation ECVWeaveDeinterlacer

#pragma mark +ECVDeinterlacer(ECVAbstract)

+ (ECVDeinterlacerType)deinterlacerType
{
	return ECVWeave;
}

#pragma mark -ECVDeinterlacer

- (ECVMutablePixelBuffer *)finishedBufferWithNextFieldType:(ECVFieldType)fieldType
{
	_drawingOptions = ECVFieldTypeDrawingOptions(fieldType);
	ECVMutablePixelBuffer *const finishedBuffer = [super finishedBufferWithNextFieldType:fieldType];
	ECVMutablePixelBuffer *const pendingBuffer = [self pendingBuffer];
	[pendingBuffer lock];
	if(finishedBuffer) [pendingBuffer drawPixelBuffer:finishedBuffer options:kNilOptions atPoint:(ECVIntegerPoint){0, 0}];
	else [pendingBuffer clear];
	[pendingBuffer unlock];
	return finishedBuffer;
}
- (ECVPixelBufferDrawingOptions)drawingOptions
{
	return _drawingOptions;
}

@end

@implementation ECVAlternateDeinterlacer

#pragma mark +ECVDeinterlacer(ECVAbstract)

+ (ECVDeinterlacerType)deinterlacerType
{
	return ECVAlternate;
}

#pragma mark -ECVDeinterlacer

- (ECVMutablePixelBuffer *)finishedBufferWithNextFieldType:(ECVFieldType)fieldType
{
	ECVMutablePixelBuffer *const finishedBuffer = [super finishedBufferWithNextFieldType:fieldType];
	[self clearPendingBuffer];
	_drawingOptions = ECVFieldTypeDrawingOptions(fieldType);
	return finishedBuffer;
}
- (ECVPixelBufferDrawingOptions)drawingOptions
{
	return _drawingOptions;
}

@end

@implementation ECVHalfHeightDeinterlacer

#pragma mark -ECVDeinterlacer

- (ECVIntegerSize)pixelSize
{
	ECVIntegerSize const s = [super pixelSize];
	return (ECVIntegerSize){s.width, s.height / 2};
}
- (ECVIntegerPoint)pixelPointForPoint:(ECVIntegerPoint)point
{
	return (ECVIntegerPoint){point.x, point.y / 2};
}

@end

@implementation ECVDropDeinterlacer

#pragma mark +ECVDeinterlacer(ECVAbstract)

+ (ECVDeinterlacerType)deinterlacerType
{
	return ECVDrop;
}

#pragma mark -ECVDeinterlacer

- (NSUInteger)frameGroupSize
{
	return 1;
}

#pragma mark -

- (ECVMutablePixelBuffer *)nextBufferWithFieldType:(ECVFieldType)fieldType
{
	return ECVLowField == fieldType ? nil : [super nextBufferWithFieldType:fieldType];
}

@end

@implementation ECVLineDoubleLQDeinterlacer

#pragma mark +ECVDeinterlacer(ECVAbstract)

+ (ECVDeinterlacerType)deinterlacerType
{
	return ECVLineDoubleLQ;
}

@end

@implementation ECVBlurDeinterlacer

#pragma mark +ECVDeinterlacer(ECVAbstract)

+ (ECVDeinterlacerType)deinterlacerType
{
	return ECVBlur;
}

#pragma mark -ECVDeinterlacer

- (ECVMutablePixelBuffer *)finishedBufferWithNextFieldType:(ECVFieldType)fieldType
{
	[_blurBuffer lock];
	[_blurBuffer drawPixelBuffer:[self pendingBuffer] options:ECVDrawBlended];
	[_blurBuffer unlock];
	ECVMutablePixelBuffer *const finishedBuffer = [_blurBuffer autorelease];
	_blurBuffer = [[super finishedBufferWithNextFieldType:fieldType] retain];
	[self clearPendingBuffer];
	return finishedBuffer;
}

#pragma mark -NSObject

- (void)dealloc
{
	[_blurBuffer release];
	[super dealloc];
}

@end
