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
#import "ECVPixelBuffer.h"

// Other Sources
#import "ECVDebug.h"

typedef struct {
	NSInteger location;
	NSUInteger length;
} ECVRange;

NS_INLINE ECVRange ECVIntersectionRange(ECVRange a, ECVRange b)
{
	NSInteger const location = MAX(a.location, b.location);
	NSInteger const maximum = MIN(a.location + a.length, b.location + b.length);
	return (ECVRange){location, SUB_ZERO(maximum, location)};
}
NS_INLINE NSRange ECVIntersectionRange2(ECVRange a, NSRange b)
{
	NSUInteger const location = MAX((NSUInteger)MAX(a.location, 0), b.location);
	NSUInteger const maximum = MAX(MIN(a.location + a.length, b.location + b.length), 0);
	return NSMakeRange(location, SUB_ZERO(maximum, location));
}

NS_INLINE NSRange ECVRebaseRange(NSRange range, NSRange base)
{
	NSRange r = NSIntersectionRange(range, base);
	r.location -= base.location;
	return r;
}
NS_INLINE uint64_t ECVPixelFormatBlackPattern(OSType t)
{
	switch(t) {
		case k2vuyPixelFormat: return CFSwapInt64HostToBig(0x8010801080108010ULL);
	}
	ECVCAssertNotReached(@"Unrecognized pixel format.");
	return 0;
}

typedef struct {
	size_t bytesPerRow;
	OSType pixelFormat;
	NSRange validRange;
} const ECVFastPixelBufferInfo;

NS_INLINE NSRange ECVValidRows(ECVFastPixelBufferInfo *info)
{
	return NSMakeRange(info->validRange.location / info->bytesPerRow, info->validRange.length / info->bytesPerRow + 2);
}
NS_INLINE void ECVDrawByte(UInt8 *dst, UInt8 const *src, OSType format, NSUInteger byteInPixel, ECVPixelBufferDrawingOptions options)
{
	switch(format) {
		case k2vuyPixelFormat:
		case k24RGBPixelFormat:
		case k32ARGBPixelFormat:
		case k24BGRPixelFormat:
		case k32BGRAPixelFormat:
		case k32ABGRPixelFormat:
		case k32RGBAPixelFormat:
		{
			if((0 == byteInPixel && ECVDrawChannel1 & options) ||
			   (1 == byteInPixel && ECVDrawChannel2 & options) ||
			   (2 == byteInPixel && ECVDrawChannel3 & options) ||
			   (3 == byteInPixel && ECVDrawChannel4 & options)) *dst = ECVDrawBlended & options ? (*dst / 2 + *src / 2) : *src;
			return;
		}
	}
	ECVCAssertNotReached(@"Pixel format '%@' does not support channel drawing options.", (NSString *)UTCreateStringForOSType(format));
}
NS_INLINE void ECVDrawRow(UInt8 *dst, ECVFastPixelBufferInfo *dstInfo, UInt8 const *src, ECVFastPixelBufferInfo *srcInfo, ECVIntegerPoint dstPoint, ECVIntegerPoint srcPoint, size_t length, ECVPixelBufferDrawingOptions options)
{
	NSUInteger const dstBytesPerPixel = ECVPixelFormatBytesPerPixel(dstInfo->pixelFormat);
	NSUInteger const srcBytesPerPixel = ECVPixelFormatBytesPerPixel(srcInfo->pixelFormat);

	ECVRange const dstRowRange = (ECVRange){dstPoint.y * dstInfo->bytesPerRow, dstInfo->bytesPerRow};
	ECVRange const srcRowRange = (ECVRange){srcPoint.y * srcInfo->bytesPerRow, srcInfo->bytesPerRow};

	ECVRange const dstDesiredRange = (ECVRange){dstRowRange.location + dstPoint.x * dstBytesPerPixel, length * dstBytesPerPixel};
	ECVRange const srcDesiredRange = (ECVRange){srcRowRange.location + srcPoint.x * srcBytesPerPixel, length * srcBytesPerPixel};

	NSRange const dstValidRange = ECVIntersectionRange2(ECVIntersectionRange(dstDesiredRange, dstRowRange), dstInfo->validRange);
	NSRange const srcValidRange = ECVIntersectionRange2(ECVIntersectionRange(srcDesiredRange, srcRowRange), srcInfo->validRange);

	NSUInteger const dstMinOffset = dstValidRange.location - dstDesiredRange.location;
	NSUInteger const srcMinOffset = srcValidRange.location - srcDesiredRange.location;
	NSUInteger const commonOffset = MAX(dstMinOffset, srcMinOffset);

	NSUInteger const dstMaxLength = SUB_ZERO(dstValidRange.length, commonOffset - dstMinOffset);
	NSUInteger const srcMaxLength = SUB_ZERO(srcValidRange.length, commonOffset - srcMinOffset);
	NSUInteger const commonLength = MIN(dstMaxLength, srcMaxLength);

	if(!commonLength) return;

	NSRange const dstRange = NSMakeRange(dstDesiredRange.location + commonOffset, commonLength);
	NSRange const srcRange = NSMakeRange(srcDesiredRange.location + commonOffset, commonLength);
	UInt8 *const dstBytes = dst + (dstRange.location - dstInfo->validRange.location);
	UInt8 const *const srcBytes = src + (srcRange.location - srcInfo->validRange.location);

	if(ECVDrawChannelMask & options) {
		size_t i;
		for(i = 0; i < commonLength; ++i) ECVDrawByte(dstBytes + i, srcBytes + i, dstInfo->pixelFormat, (dstRange.location + i) % dstBytesPerPixel, options);
	} else if(ECVDrawBlended & options) {
		size_t i;
		for(i = 0; i < commonLength; ++i) dstBytes[i] = dstBytes[i] / 2 + srcBytes[i] / 2;
	} else {
		memcpy(dstBytes, srcBytes, commonLength);
	}
}
static void ECVDrawRect(ECVMutablePixelBuffer *dst, ECVPixelBuffer *src, ECVIntegerPoint dstPoint, ECVIntegerPoint srcPoint, ECVIntegerSize size, ECVPixelBufferDrawingOptions options)
{
	if(!src || !dst) return;
	ECVFastPixelBufferInfo dstInfo = {
		.bytesPerRow = [dst bytesPerRow],
		.pixelFormat = [dst pixelFormat],
		.validRange = [dst validRange],
	};
	ECVFastPixelBufferInfo srcInfo = {
		.bytesPerRow = [src bytesPerRow],
		.pixelFormat = [src pixelFormat],
		.validRange = [src validRange],
	};
	UInt8 *const dstBytes = [dst mutableBytes];
	UInt8 const *const srcBytes = [src bytes];
	BOOL const useFields = ECVDrawToHighField & options || ECVDrawToLowField & options;
	NSUInteger const dstRowSpacing = useFields ? 2 : 1;

	NSRange const srcRows = ECVIntersectionRange2((ECVRange){srcPoint.y, size.height}, ECVValidRows(&srcInfo));
	NSUInteger i;
	for(i = srcRows.location; i < NSMaxRange(srcRows); ++i) {
		NSUInteger const dstRowOffset = (ECVDrawMirroredVert & options ? size.height - i : i) * dstRowSpacing;
		if(ECVDrawToHighField & options || !useFields) {
			ECVDrawRow(dstBytes, &dstInfo, srcBytes, &srcInfo, (ECVIntegerPoint){dstPoint.x, dstPoint.y + 0 + dstRowOffset}, (ECVIntegerPoint){srcPoint.x, srcPoint.y + i}, size.width, options);
		}
		if(ECVDrawToLowField & options) {
			ECVDrawRow(dstBytes, &dstInfo, srcBytes, &srcInfo, (ECVIntegerPoint){dstPoint.x, dstPoint.y + 1 + dstRowOffset}, (ECVIntegerPoint){srcPoint.x, srcPoint.y + i}, size.width, options);
		}
	}
}

@implementation ECVPixelBuffer

#pragma mark -ECVPixelBuffer

- (NSRange)fullRange
{
	return NSMakeRange(0, [self bytesPerRow] * [self pixelSize].height);
}
- (BOOL)lockIfHasBytes
{
	[self lock];
	if([self hasBytes]) return YES;
	[self unlock];
	return NO;
}

@end

@implementation ECVPointerPixelBuffer

#pragma mark -ECVPointerPixelBuffer

- (id)initWithPixelSize:(ECVIntegerSize)pixelSize bytesPerRow:(size_t)bytesPerRow pixelFormat:(OSType)pixelFormat bytes:(void const *)bytes validRange:(NSRange)validRange
{
	if((self = [super init])) {
		_pixelSize = pixelSize;
		_bytesPerRow = bytesPerRow;
		_pixelFormat = pixelFormat;

		_bytes = bytes;
		_validRange = validRange;
	}
	return self;
}
- (void)invalidate
{
	_bytes = NULL;
}

#pragma mark -ECVPixelBuffer(ECVAbstract)

- (ECVIntegerSize)pixelSize
{
	return _pixelSize;
}
- (size_t)bytesPerRow
{
	return _bytesPerRow;
}
- (OSType)pixelFormat
{
	return _pixelFormat;
}

#pragma mark -

- (void const *)bytes
{
	return _bytes;
}
- (BOOL)hasBytes
{
	return !!_bytes;
}
- (NSRange)validRange
{
	return _validRange;
}

#pragma mark -ECVPixelBuffer(ECVAbstract) <NSLocking>

- (void)lock {}
- (void)unlock {}

@end

@implementation ECVMutablePixelBuffer

#pragma mark -ECVMutablePixelBuffer

- (void)drawPixelBuffer:(ECVPixelBuffer *)src
{
	[self drawPixelBuffer:src options:kNilOptions];
}
- (void)drawPixelBuffer:(ECVPixelBuffer *)src options:(ECVPixelBufferDrawingOptions)options
{
	[self drawPixelBuffer:src options:options atPoint:(ECVIntegerPoint){0, 0}];
}
- (void)drawPixelBuffer:(ECVPixelBuffer *)src options:(ECVPixelBufferDrawingOptions)options atPoint:(ECVIntegerPoint)point
{
	ECVIntegerPoint const dstPoint = point;
	ECVIntegerPoint const srcPoint = (ECVIntegerPoint){0, 0};
	ECVDrawRect(self, src, dstPoint, srcPoint, [src pixelSize], options);
}

#pragma mark -

- (void)clearRange:(NSRange)range
{
	NSRange const r = ECVRebaseRange(range, [self validRange]);
	if(!r.length) return;
	uint64_t const val = ECVPixelFormatBlackPattern([self pixelFormat]);
	memset_pattern8([self mutableBytes] + r.location, &val, r.length);
}
- (void)clear
{
	NSUInteger const length = [self validRange].length;
	if(!length) return;
	uint64_t const val = ECVPixelFormatBlackPattern([self pixelFormat]);
	memset_pattern8([self mutableBytes], &val, length);
}

@end

@implementation ECVCVPixelBuffer : ECVMutablePixelBuffer

#pragma mark -ECVCVPixelBuffer

- (id)initWithPixelBuffer:(CVPixelBufferRef)pixelBuffer
{
	if((self = [super init])) {
		_pixelBuffer = CVPixelBufferRetain(pixelBuffer);
	}
	return self;
}

#pragma mark -ECVMutablePixelBuffer(ECVAbstract)

- (void *)mutableBytes
{
	return CVPixelBufferGetBaseAddress(_pixelBuffer);
}

#pragma mark -ECVPixelBuffer(ECVAbstract)

- (ECVIntegerSize)pixelSize
{
	return (ECVIntegerSize){CVPixelBufferGetWidth(_pixelBuffer), CVPixelBufferGetHeight(_pixelBuffer)};
}
- (size_t)bytesPerRow
{
	return CVPixelBufferGetBytesPerRow(_pixelBuffer);
}
- (OSType)pixelFormat
{
	return CVPixelBufferGetPixelFormatType(_pixelBuffer);
}

#pragma mark -

- (void const *)bytes
{
	return CVPixelBufferGetBaseAddress(_pixelBuffer);
}
- (BOOL)hasBytes
{
	return YES;
}
- (NSRange)validRange
{
	return [self fullRange];
}

#pragma mark -ECVPixelBuffer(ECVAbstract) <NSLocking>

- (void)lock
{
	CVPixelBufferLockBaseAddress(_pixelBuffer, kNilOptions);
}
- (void)unlock
{
	CVPixelBufferUnlockBaseAddress(_pixelBuffer, kNilOptions);
}

#pragma mark -NSObject

- (void)dealloc
{
	CVPixelBufferRelease(_pixelBuffer);
	[super dealloc];
}

@end

@implementation ECVDataPixelBuffer

#pragma mark -ECVDataPixelBuffer

- (id)initWithPixelSize:(ECVIntegerSize)pixelSize bytesPerRow:(size_t)bytesPerRow pixelFormat:(OSType)pixelFormat data:(NSMutableData *)data offset:(NSUInteger)offset
{
	if((self = [super init])) {
		_pixelSize = pixelSize;
		_bytesPerRow = bytesPerRow;
		_pixelFormat = pixelFormat;

		_data = [data retain];
		_offset = offset;
	}
	return self;
}
- (NSMutableData *)mutableData
{
	return [[_data retain] autorelease];
}

#pragma mark -ECVMutablePixelBuffer(ECVAbstract)

- (void *)mutableBytes
{
	return [_data mutableBytes];
}

#pragma mark -ECVPixelBuffer(ECVAbstract)

- (ECVIntegerSize)pixelSize
{
	return _pixelSize;
}
- (size_t)bytesPerRow
{
	return _bytesPerRow;
}
- (OSType)pixelFormat
{
	return _pixelFormat;
}

#pragma mark -

- (void const *)bytes
{
	return [_data bytes];
}
- (BOOL)hasBytes
{
	return YES;
}
- (NSRange)validRange
{
	return NSMakeRange(_offset, [_data length]);
}

#pragma mark -ECVPixelBuffer(ECVAbstract) <NSLocking>

- (void)lock {}
- (void)unlock {}

#pragma mark -NSObject

- (void)dealloc
{
	[_data release];
	[super dealloc];
}

@end

@implementation ECVConcreteMutablePixelBuffer

#pragma mark -ECVConcreteMutablePixelBuffer

- (id)initWithPixelSize:(ECVIntegerSize)pixelSize bytesPerRow:(size_t)bytesPerRow pixelFormat:(OSType)pixelFormat
{
	if((self = [super init])) {
		_pixelSize = pixelSize;
		_bytesPerRow = bytesPerRow;
		_pixelFormat = pixelFormat;
		_bytes = malloc([self fullRange].length);
	}
	return self;
}

#pragma mark -ECVMutablePixelBuffer(ECVAbstract)

- (void *)mutableBytes
{
	return _bytes;
}

#pragma mark -ECVPixelBuffer(ECVAbstract)

- (ECVIntegerSize)pixelSize
{
	return _pixelSize;
}
- (size_t)bytesPerRow
{
	return _bytesPerRow;
}
- (OSType)pixelFormat
{
	return _pixelFormat;
}

#pragma mark -

- (void const *)bytes
{
	return _bytes;
}
- (BOOL)hasBytes
{
	return YES;
}
- (NSRange)validRange
{
	return [self fullRange];
}

#pragma mark -ECVPixelBuffer(ECVAbstract) <NSLocking>

- (void)lock {}
- (void)unlock {}

#pragma mark -NSObject

- (void)dealloc
{
	if(_bytes) free(_bytes);
	[super dealloc];
}

@end
