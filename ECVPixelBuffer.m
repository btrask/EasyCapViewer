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
#import "ECVPixelFormat.h"

NS_INLINE NSRange ECVRebaseRange(NSRange range, NSRange base)
{
	NSRange r = NSIntersectionRange(range, base);
	r.location -= base.location;
	return r;
}

typedef struct {
	size_t bytesPerRow;
	size_t bytesPerPixel;
	NSRange validRange;
} const ECVFastPixelBufferInfo;

NS_INLINE NSRange ECVValidRows(ECVFastPixelBufferInfo *info)
{
	return NSMakeRange(info->validRange.location / info->bytesPerRow, info->validRange.length / info->bytesPerRow + 2);
}
NS_INLINE void ECVDraw(UInt8 *dst, UInt8 const *src, size_t length, BOOL blended)
{
	if(blended) {
		size_t i;
		for(i = 0; i < length; ++i) dst[i] = dst[i] / 2 + src[i] / 2;
	} else memcpy(dst, src, length);
}
NS_INLINE void ECVDrawRow(UInt8 *dst, ECVFastPixelBufferInfo *dstInfo, UInt8 const *src, ECVFastPixelBufferInfo *srcInfo, ECVIntegerPoint dstPoint, ECVIntegerPoint srcPoint, size_t length, BOOL blended)
{
	NSRange const dstDesiredRange = NSMakeRange(dstPoint.y * dstInfo->bytesPerRow + dstPoint.x * dstInfo->bytesPerPixel, length * dstInfo->bytesPerPixel);
	NSRange const srcDesiredRange = NSMakeRange(srcPoint.y * srcInfo->bytesPerRow + srcPoint.x * srcInfo->bytesPerPixel, length * srcInfo->bytesPerPixel);

	NSRange const dstRowRange = NSMakeRange(dstPoint.y * dstInfo->bytesPerRow, dstInfo->bytesPerRow);
	NSRange const srcRowRange = NSMakeRange(srcPoint.y * srcInfo->bytesPerRow, srcInfo->bytesPerRow);

	NSRange const dstValidRange = NSIntersectionRange(NSIntersectionRange(dstDesiredRange, dstRowRange), dstInfo->validRange);
	NSRange const srcValidRange = NSIntersectionRange(NSIntersectionRange(srcDesiredRange, srcRowRange), srcInfo->validRange);

	NSUInteger const dstMinOffset = dstValidRange.location - dstDesiredRange.location;
	NSUInteger const srcMinOffset = srcValidRange.location - srcDesiredRange.location;
	NSUInteger const commonOffset = MAX(dstMinOffset, srcMinOffset);

	NSUInteger const dstMaxLength = SUB_ZERO(dstValidRange.length, commonOffset - dstMinOffset);
	NSUInteger const srcMaxLength = SUB_ZERO(srcValidRange.length, commonOffset - srcMinOffset);
	NSUInteger const commonLength = MIN(dstMaxLength, srcMaxLength);

	if(!commonLength) return;
	NSRange const dstRange = ECVRebaseRange(NSMakeRange(dstDesiredRange.location + commonOffset, commonLength), dstInfo->validRange);
	NSRange const srcRange = ECVRebaseRange(NSMakeRange(srcDesiredRange.location + commonOffset, commonLength), srcInfo->validRange);
	UInt8 *const dstBytes = dst + dstRange.location;
	UInt8 const *const srcBytes = src + srcRange.location;
	ECVDraw(dstBytes, srcBytes, commonLength, blended);
}
static void ECVDrawRect(ECVMutablePixelBuffer *dst, ECVPixelBuffer *src, ECVIntegerPoint dstPoint, ECVIntegerPoint srcPoint, ECVIntegerSize size, ECVPixelBufferDrawingOptions options)
{
	ECVFastPixelBufferInfo dstInfo = {
		.bytesPerRow = [dst bytesPerRow],
		.bytesPerPixel = ECVPixelFormatBytesPerPixel([dst pixelFormatType]),
		.validRange = [dst validRange],
	};
	ECVFastPixelBufferInfo srcInfo = {
		.bytesPerRow = [src bytesPerRow],
		.bytesPerPixel = ECVPixelFormatBytesPerPixel([src pixelFormatType]),
		.validRange = [src validRange],
	};
	UInt8 *const dstBytes = [dst mutableBytes];
	UInt8 const *const srcBytes = [src bytes];
	BOOL const useFields = ECVDrawToHighField & options || ECVDrawToLowField & options;
	NSUInteger const dstRowSpacing = useFields ? 2 : 1;
	BOOL const blended = !!(ECVDrawBlended & options);

	NSRange const srcRows = NSIntersectionRange(NSMakeRange(srcPoint.y, size.height), ECVValidRows(&srcInfo));
	NSUInteger i;
	for(i = srcRows.location; i < NSMaxRange(srcRows); ++i) {
		if(ECVDrawToHighField & options || !useFields) {
			ECVDrawRow(dstBytes, &dstInfo, srcBytes, &srcInfo, (ECVIntegerPoint){dstPoint.x, dstPoint.y + 0 + (i * dstRowSpacing)}, (ECVIntegerPoint){srcPoint.x, srcPoint.y + i}, size.width, blended);
		}
		if(ECVDrawToLowField & options) {
			ECVDrawRow(dstBytes, &dstInfo, srcBytes, &srcInfo, (ECVIntegerPoint){dstPoint.x, dstPoint.y + 1 + (i * dstRowSpacing)}, (ECVIntegerPoint){srcPoint.x, srcPoint.y + i}, size.width, blended);
		}
	}
}

@implementation ECVPixelBuffer

#pragma mark -ECVPixelBuffer

- (NSRange)fullRange
{
	return NSMakeRange(0, [self bytesPerRow] * [self pixelSize].height);
}

@end

@implementation ECVPointerPixelBuffer

#pragma mark -ECVPointerPixelBuffer

- (id)initWithPixelSize:(ECVIntegerSize)pixelSize bytesPerRow:(size_t)bytesPerRow pixelFormat:(OSType)pixelFormatType bytes:(void const *)bytes validRange:(NSRange)validRange
{
	if((self = [super init])) {
		_pixelSize = pixelSize;
		_bytesPerRow = bytesPerRow;
		_pixelFormatType = pixelFormatType;

		_bytes = bytes;
		_validRange = validRange;
	}
	return self;
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
- (OSType)pixelFormatType
{
	return _pixelFormatType;
}

#pragma mark -

- (void const *)bytes
{
	return _bytes;
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
	uint64_t const val = ECVPixelFormatBlackPattern([self pixelFormatType]);
	memset_pattern8([self mutableBytes] + r.location, &val, r.length);
}
- (void)clear
{
	NSUInteger const length = [self validRange].length;
	if(!length) return;
	uint64_t const val = ECVPixelFormatBlackPattern([self pixelFormatType]);
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
- (OSType)pixelFormatType
{
	return CVPixelBufferGetPixelFormatType(_pixelBuffer);
}

#pragma mark -

- (void const *)bytes
{
	return CVPixelBufferGetBaseAddress(_pixelBuffer);
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

- (id)initWithPixelSize:(ECVIntegerSize)pixelSize bytesPerRow:(size_t)bytesPerRow pixelFormat:(OSType)pixelFormatType data:(NSMutableData *)data offset:(NSUInteger)offset
{
	if((self = [super init])) {
		_pixelSize = pixelSize;
		_bytesPerRow = bytesPerRow;
		_pixelFormatType = pixelFormatType;

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
- (OSType)pixelFormatType
{
	return _pixelFormatType;
}

#pragma mark -

- (void const *)bytes
{
	return [_data bytes];
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
