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
#import "ECVDeinterlacingMode.h"

// Models
#import "ECVVideoFormat.h"
#import "ECVVideoStorage.h"
#import "ECVVideoFrame.h"

// Other Sources
#import "ECVFoundationAdditions.h"

@interface ECVDeinterlacedVideoFormat : ECVVideoFormat
{
	@protected
	ECVVideoFormat *_nativeFormat;
}

- (id)initWithNativeFormat:(ECVVideoFormat *const)format;
- (ECVVideoFormat *)nativeFormat;
- (ECVIntegerSize)doubleNativeFrameSize;
- (QTTime)halfNativeFrameRate;

@end

@interface ECVDeinterlacedVideoFormat_LineDoubleHQ : ECVDeinterlacedVideoFormat
@end
@interface ECVDeinterlacedVideoFormat_Weave : ECVDeinterlacedVideoFormat
@end
@interface ECVDeinterlacedVideoFormat_Alternate : ECVDeinterlacedVideoFormat
@end
@interface ECVDeinterlacedVideoFormat_Drop : ECVDeinterlacedVideoFormat
@end
@interface ECVDeinterlacedVideoFormat_LineDoubleLQ : ECVDeinterlacedVideoFormat
@end
@interface ECVDeinterlacedVideoFormat_Blur : ECVDeinterlacedVideoFormat
@end

static ECVPixelBufferDrawingOptions ECVFieldTypeDrawingOptions(ECVFieldType const fieldType)
{
	switch(fieldType) {
		case ECVHighField: return ECVDrawToHighField;
		case ECVLowField: return ECVDrawToLowField;
		case ECVFullFrame: return kNilOptions;
	}
	ECVCAssertNotReached(@"Invalid field type.");
	return kNilOptions;
}

@implementation ECVDeinterlacingMode

#pragma mark +ECVDeinterlacingMode

+ (Class)deinterlacingModeWithType:(ECVDeinterlacingModeType const)type
{
	Class c = Nil;
	switch(type) {
		case ECVProgressiveScan:
			c = [ECVProgressiveScanMode class]; break;
		case ECVWeave:
			c = [ECVWeaveDeinterlacingMode class]; break;
		case ECVLineDoubleLQ:
			c = [ECVLineDoubleLQDeinterlacingMode class]; break;
		case ECVLineDoubleHQ:
			c = [ECVLineDoubleHQDeinterlacingMode class]; break;
		case ECVAlternate:
			c = [ECVAlternateDeinterlacingMode class]; break;
		case ECVBlur:
			c = [ECVBlurDeinterlacingMode class]; break;
		case ECVDrop:
			c = [ECVDropDeinterlacingMode class]; break;
	}
	return c;
}

#pragma mark -ECVDeinterlacingMode

- (id)initWithVideoStorage:(ECVVideoStorage *const)storage videoFormat:(ECVVideoFormat *const)videoFormat
{
	if((self = [super init])) {
		_videoStorage = storage;
		_videoFormat = [videoFormat retain];
	}
	return self;
}
- (ECVVideoStorage *)videoStorage
{
	return _videoStorage;
}
- (ECVVideoFormat *)videoFormat
{
	return [[_videoFormat retain] autorelease];
}
- (ECVIntegerPoint)pixelPointForPoint:(ECVIntegerPoint const)point
{
	return point;
}
- (ECVMutablePixelBuffer *)pendingBuffer
{
	return _pendingBuffer;
}

#pragma mark -

- (ECVMutablePixelBuffer *)nextBufferWithFieldType:(ECVFieldType const)fieldType
{
	[_videoStorage lock];
	ECVMutablePixelBuffer *const buffer = [_videoStorage nextBuffer];
	[_videoStorage unlock];
	return buffer;
}
- (ECVMutablePixelBuffer *)finishedBufferWithNextFieldType:(ECVFieldType const)fieldType
{
	ECVMutablePixelBuffer *const finishedBuffer = [_pendingBuffer autorelease];
	_pendingBuffer = [[self nextBufferWithFieldType:fieldType] retain];
	return finishedBuffer;
}
- (void)drawPixelBuffer:(ECVPixelBuffer *const)buffer atPoint:(ECVIntegerPoint const)point
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
	[_videoFormat release];
	[_pendingBuffer release];
	[super dealloc];
}

@end

@implementation ECVProgressiveScanMode

#pragma mark +ECVDeinterlacingMode(ECVAbstract)

+ (ECVDeinterlacingModeType)deinterlacingModeType
{
	return ECVProgressiveScan;
}

@end

@implementation ECVLineDoubleHQDeinterlacingMode

#pragma mark +ECVDeinterlacingMode(ECVAbstract)

+ (ECVDeinterlacingModeType)deinterlacingModeType
{
	return ECVLineDoubleHQ;
}

#pragma mark -ECVDeinterlacingMode

- (id)initWithVideoStorage:(ECVVideoStorage *const)storage videoFormat:(ECVVideoFormat *const)videoFormat
{
	return [super initWithVideoStorage:storage videoFormat:[[[ECVDeinterlacedVideoFormat_LineDoubleHQ alloc] initWithNativeFormat:videoFormat] autorelease]];
}
- (ECVMutablePixelBuffer *)finishedBufferWithNextFieldType:(ECVFieldType const)fieldType
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
- (void)drawPixelBuffer:(ECVPixelBuffer *const)buffer atPoint:(ECVIntegerPoint const)point
{
	[super drawPixelBuffer:buffer atPoint:(ECVIntegerPoint){point.x, point.y + _rowOffset}];
}
- (ECVPixelBufferDrawingOptions)drawingOptions
{
	return ECVDrawToHighField | ECVDrawToLowField;
}

@end

@implementation ECVWeaveDeinterlacingMode

#pragma mark +ECVDeinterlacingMode(ECVAbstract)

+ (ECVDeinterlacingModeType)deinterlacingModeType
{
	return ECVWeave;
}

#pragma mark -ECVDeinterlacingMode

- (id)initWithVideoStorage:(ECVVideoStorage *const)storage videoFormat:(ECVVideoFormat *const)videoFormat
{
	return [super initWithVideoStorage:storage videoFormat:[[[ECVDeinterlacedVideoFormat_Weave alloc] initWithNativeFormat:videoFormat] autorelease]];
}
- (ECVMutablePixelBuffer *)finishedBufferWithNextFieldType:(ECVFieldType const)fieldType
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

@implementation ECVAlternateDeinterlacingMode

#pragma mark +ECVDeinterlacingMode(ECVAbstract)

+ (ECVDeinterlacingModeType)deinterlacingModeType
{
	return ECVAlternate;
}

#pragma mark -ECVDeinterlacingMode

- (id)initWithVideoStorage:(ECVVideoStorage *const)storage videoFormat:(ECVVideoFormat *const)videoFormat
{
	return [super initWithVideoStorage:storage videoFormat:[[[ECVDeinterlacedVideoFormat_Alternate alloc] initWithNativeFormat:videoFormat] autorelease]];
}
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

@implementation ECVHalfHeightDeinterlacingMode

#pragma mark -ECVDeinterlacingMode

- (ECVIntegerPoint)pixelPointForPoint:(ECVIntegerPoint const)point
{
	return (ECVIntegerPoint){point.x, point.y / 2};
}

@end

@implementation ECVDropDeinterlacingMode

#pragma mark +ECVDeinterlacingMode(ECVAbstract)

+ (ECVDeinterlacingModeType)deinterlacingModeType
{
	return ECVDrop;
}

#pragma mark -ECVDeinterlacingMode

- (id)initWithVideoStorage:(ECVVideoStorage *const)storage videoFormat:(ECVVideoFormat *const)videoFormat
{
	return [super initWithVideoStorage:storage videoFormat:[[[ECVDeinterlacedVideoFormat_Drop alloc] initWithNativeFormat:videoFormat] autorelease]];
}

#pragma mark -

- (ECVMutablePixelBuffer *)nextBufferWithFieldType:(ECVFieldType const)fieldType
{
	return ECVLowField == fieldType ? nil : [super nextBufferWithFieldType:fieldType];
}

@end

@implementation ECVLineDoubleLQDeinterlacingMode

#pragma mark +ECVDeinterlacingMode(ECVAbstract)

+ (ECVDeinterlacingModeType)deinterlacingModeType
{
	return ECVLineDoubleLQ;
}

#pragma mark -ECVDeinterlacingMode

- (id)initWithVideoStorage:(ECVVideoStorage *const)storage videoFormat:(ECVVideoFormat *const)videoFormat
{
	return [super initWithVideoStorage:storage videoFormat:[[[ECVDeinterlacedVideoFormat_LineDoubleLQ alloc] initWithNativeFormat:videoFormat] autorelease]];
}

@end

@implementation ECVBlurDeinterlacingMode

#pragma mark +ECVDeinterlacingMode(ECVAbstract)

+ (ECVDeinterlacingModeType)deinterlacingModeType
{
	return ECVBlur;
}

#pragma mark -ECVDeinterlacingMode

- (id)initWithVideoStorage:(ECVVideoStorage *const)storage videoFormat:(ECVVideoFormat *const)videoFormat
{
	return [super initWithVideoStorage:storage videoFormat:[[[ECVDeinterlacedVideoFormat_Blur alloc] initWithNativeFormat:videoFormat] autorelease]];
}
- (ECVMutablePixelBuffer *)finishedBufferWithNextFieldType:(ECVFieldType const)fieldType
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

@implementation ECVDeinterlacedVideoFormat

#pragma mark -ECVDeinterlacedVideoFormat

- (id)initWithNativeFormat:(ECVVideoFormat *const)format
{
	NSParameterAssert([format isInterlaced]);
	if((self = [super init])) {
		_nativeFormat = [format retain];
	}
	return self;
}
- (ECVVideoFormat *)nativeFormat
{
	return [[_nativeFormat retain] autorelease];
}
- (ECVIntegerSize)doubleNativeFrameSize
{
	ECVIntegerSize const s = [_nativeFormat frameSize];
	return (ECVIntegerSize){s.width, s.height*2};
}
- (QTTime)halfNativeFrameRate
{
	QTTime f = [_nativeFormat frameRate];
	f.timeScale *= 2;
	return f;
}

#pragma mark -ECVVideoFormat(ECVAbstract)

- (NSString *)localizedName { return [_nativeFormat localizedName]; }
- (ECVIntegerSize)frameSize { return [_nativeFormat frameSize]; }
- (BOOL)isInterlaced { return NO; }
- (BOOL)isProgressive { return YES; }
- (QTTime)frameRate { return [_nativeFormat frameRate]; }
- (BOOL)is60Hz { return [_nativeFormat is60Hz]; }
- (BOOL)is50Hz { return [_nativeFormat is50Hz]; }

#pragma mark -NSObject<NSObject>

- (NSUInteger)hash
{
	return (intptr_t)self >> 4;
}
- (BOOL)isEqual:(id const)obj
{
	return NO;
}

@end

@implementation ECVDeinterlacedVideoFormat_LineDoubleHQ
- (ECVIntegerSize)frameSize { return [self doubleNativeFrameSize]; }
- (NSUInteger)frameGroupSize { return 2; }
@end
@implementation ECVDeinterlacedVideoFormat_Weave
- (ECVIntegerSize)frameSize { return [self doubleNativeFrameSize]; }
- (NSUInteger)frameGroupSize { return 1; }
@end
@implementation ECVDeinterlacedVideoFormat_Alternate
- (ECVIntegerSize)frameSize { return [self doubleNativeFrameSize]; }
- (NSUInteger)frameGroupSize { return 2; }
@end
@implementation ECVDeinterlacedVideoFormat_Drop
- (NSUInteger)frameGroupSize { return 1; }
- (QTTime)frameRate { return [self halfNativeFrameRate]; }
- (BOOL)is60Hz { return NO; }
- (BOOL)is50Hz { return NO; }
@end
@implementation ECVDeinterlacedVideoFormat_LineDoubleLQ
- (NSUInteger)frameGroupSize { return 2; }
@end
@implementation ECVDeinterlacedVideoFormat_Blur
- (NSUInteger)frameGroupSize { return 1; }
@end
