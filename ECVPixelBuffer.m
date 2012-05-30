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
#import "ECVPixelFormat.h"

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
	NSUInteger const maximum = MIN((NSUInteger)MAX(a.location + a.length, 0), b.location + b.length);
	return NSMakeRange(location, SUB_ZERO(maximum, location));
}

NS_INLINE NSRange ECVRebaseRange(NSRange range, NSRange base)
{
	NSRange r = NSIntersectionRange(range, base);
	r.location -= base.location;
	return r;
}
NS_INLINE NSRange ECVRebaseRange2(NSRange range, ECVRange base)
{
	NSRange r = ECVIntersectionRange2(base, range);
	r.location -= base.location;
	return r;
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
NS_INLINE void ECVCopyByte(UInt8 *dstPixel, NSUInteger dstIndex, UInt8 const *srcPixel, NSUInteger srcIndex, NSRange range, ECVPixelBufferDrawingOptions options)
{
	if(!NSLocationInRange(dstIndex, range) || !NSLocationInRange(srcIndex, range)) return;
	NSUInteger const d = dstIndex - range.location;
	NSUInteger const s = srcIndex - range.location;
	dstPixel[d] = ECVDrawBlended & options ? dstPixel[d] / 2 + srcPixel[s] / 2 : srcPixel[s];
}
NS_INLINE void ECVDrawPixel(UInt8 *dstPixel, OSType dstFormat, UInt8 const *srcPixel, OSType srcFormat, NSRange range, ECVPixelBufferDrawingOptions options)
{
	NSCParameterAssert(dstFormat == srcFormat);
	if(!(ECVDrawChannelMask & options)) options |= ECVDrawChannelMask;
	#define ECV_COPY_BYTE(d, s) (ECVCopyByte(dstPixel, (d), srcPixel, (s), range, options))
	switch(srcFormat) {
		case kYVYU422PixelFormat:
		{
			if(ECVDrawChannel1 & options) ECV_COPY_BYTE(0, ECVDrawMirroredHorz & options ? 2 : 0);
			if(ECVDrawChannel2 & options) ECV_COPY_BYTE(1, 1);
			if(ECVDrawChannel3 & options) ECV_COPY_BYTE(2, ECVDrawMirroredHorz & options ? 0 : 2);
			if(ECVDrawChannel2 & options) ECV_COPY_BYTE(3, 3);
			return;
		}
		case k2vuyPixelFormat:
		{
			if(ECVDrawChannel1 & options) ECV_COPY_BYTE(0, 0);
			if(ECVDrawChannel2 & options) ECV_COPY_BYTE(1, ECVDrawMirroredHorz & options ? 3 : 1);
			if(ECVDrawChannel3 & options) ECV_COPY_BYTE(2, 2);
			if(ECVDrawChannel2 & options) ECV_COPY_BYTE(3, ECVDrawMirroredHorz & options ? 1 : 3);
			return;
		}
		case k24RGBPixelFormat:
		case k32ARGBPixelFormat:
		case k24BGRPixelFormat:
		case k32BGRAPixelFormat:
		case k32ABGRPixelFormat:
		case k32RGBAPixelFormat:
		{
			if(ECVDrawChannel1 & options) ECV_COPY_BYTE(0, 0);
			if(ECVDrawChannel2 & options) ECV_COPY_BYTE(1, 1);
			if(ECVDrawChannel3 & options) ECV_COPY_BYTE(2, 2);
			if(ECVDrawChannel4 & options) ECV_COPY_BYTE(3, 3);
			return;
		}
	}
	ECVCAssertNotReached(@"Combination of source pixel format %@ and destination pixel format %@ are unsupported", (NSString *)UTCreateStringForOSType(srcFormat), (NSString *)UTCreateStringForOSType(dstFormat));
}
NS_INLINE void ECVDrawRow(UInt8 *dst, ECVFastPixelBufferInfo *dstInfo, UInt8 const *src, ECVFastPixelBufferInfo *srcInfo, ECVIntegerPoint dstPoint, ECVIntegerPoint srcPoint, size_t length, ECVPixelBufferDrawingOptions options)
{
	NSUInteger const dstBytesPerPixel = ECVPixelFormatBytesPerPixel(dstInfo->pixelFormat);
	NSUInteger const srcBytesPerPixel = ECVPixelFormatBytesPerPixel(srcInfo->pixelFormat);

	ECVRange const dstRowRange = (ECVRange){dstPoint.y * dstInfo->bytesPerRow, dstInfo->bytesPerRow};
	ECVRange const srcRowRange = (ECVRange){srcPoint.y * srcInfo->bytesPerRow, srcInfo->bytesPerRow};

	ECVRange const dstDesiredRange = (ECVRange){dstRowRange.location + dstPoint.x * dstBytesPerPixel, length * dstBytesPerPixel};
	ECVRange const srcDesiredRange = (ECVRange){srcRowRange.location + srcPoint.x * srcBytesPerPixel, length * srcBytesPerPixel};

	if(!dstDesiredRange.length || !srcDesiredRange.length) return;

	if(ECVDrawChannelMask & options || ECVDrawMirroredHorz & options || dstInfo->pixelFormat != srcInfo->pixelFormat) {
		BOOL const dstFlip = !!(ECVDrawMirroredHorz & options);
		BOOL const srcFlip = NO;
		NSUInteger const dstBlockSize = ECVPixelFormatPixelsPerBlock(dstInfo->pixelFormat) * dstBytesPerPixel;
		NSUInteger const srcBlockSize = ECVPixelFormatPixelsPerBlock(srcInfo->pixelFormat) * srcBytesPerPixel;
		NSUInteger i;
		for(i = 0; ; ++i) {
			ECVRange const dstDesiredPixelRange = (ECVRange){dstDesiredRange.location + (dstFlip ? dstDesiredRange.length - (i + 1) * dstBlockSize : i * dstBlockSize), dstBlockSize};
			ECVRange const srcDesiredPixelRange = (ECVRange){srcDesiredRange.location + (srcFlip ? srcDesiredRange.length - (i + 1) * srcBlockSize : i * srcBlockSize), srcBlockSize};

			NSRange const dstValidPixelRange = ECVIntersectionRange2(ECVIntersectionRange(dstDesiredPixelRange, dstRowRange), dstInfo->validRange);
			NSRange const srcValidPixelRange = ECVIntersectionRange2(ECVIntersectionRange(srcDesiredPixelRange, srcRowRange), srcInfo->validRange);
			NSRange const pixelCommon = NSIntersectionRange(ECVRebaseRange2(dstValidPixelRange, dstDesiredPixelRange), ECVRebaseRange2(srcValidPixelRange, srcDesiredPixelRange));
			if(!pixelCommon.length) break;

			NSRange const dstPixelRange = NSMakeRange(dstDesiredPixelRange.location + pixelCommon.location, pixelCommon.length);
			NSRange const srcPixelRange = NSMakeRange(srcDesiredPixelRange.location + pixelCommon.location, pixelCommon.length);
			UInt8 *const dstPixelBytes = dst + (dstPixelRange.location - dstInfo->validRange.location);
			UInt8 const *const srcPixelBytes = src + (srcPixelRange.location - srcInfo->validRange.location);

			ECVDrawPixel(dstPixelBytes, dstInfo->pixelFormat, srcPixelBytes, srcInfo->pixelFormat, pixelCommon, options);
		}
		return;
	}

	NSRange const dstValidRange = ECVIntersectionRange2(ECVIntersectionRange(dstDesiredRange, dstRowRange), dstInfo->validRange);
	NSRange const srcValidRange = ECVIntersectionRange2(ECVIntersectionRange(srcDesiredRange, srcRowRange), srcInfo->validRange);
	NSRange const common = NSIntersectionRange(ECVRebaseRange2(dstValidRange, dstDesiredRange), ECVRebaseRange2(srcValidRange, srcDesiredRange));
	if(!common.length) return;

	NSRange const dstRange = NSMakeRange(dstDesiredRange.location + common.location, common.length);
	NSRange const srcRange = NSMakeRange(srcDesiredRange.location + common.location, common.length);
	UInt8 *const dstBytes = dst + (dstRange.location - dstInfo->validRange.location);
	UInt8 const *const srcBytes = src + (srcRange.location - srcInfo->validRange.location);

	if(ECVDrawBlended & options) {
		size_t i;
		for(i = 0; i < common.length; ++i) dstBytes[i] = dstBytes[i] / 2 + srcBytes[i] / 2;
	} else {
		memcpy(dstBytes, srcBytes, common.length);
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
