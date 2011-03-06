/* Copyright (c) 2009, Ben Trask
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
#import "ECVVideoFrame.h"

// Models
#import "ECVVideoStorage.h"
#import "ECVDeinterlacingMode.h"

// Other Sources
#import "ECVDebug.h"
#import "ECVFoundationAdditions.h"

typedef struct {
	void *bytes;
	size_t length;
	ECVFieldType fieldType;
	BOOL doubledLines;
	size_t bytesPerRow;
	OSType pixelFormatType;
	ECVIntegerSize pixelSize;
} ECVBufferInfo;
static NSRange ECVBufferNextRowInRange(ECVBufferInfo info, NSRange range)
{
	size_t const rowActual = info.bytesPerRow;
	size_t const rowTheoretical = ECVPixelFormatBytesPerPixel(info.pixelFormatType) * info.pixelSize.width;
	NSCAssert(rowActual >= rowTheoretical, @"Rows must have non-negative padding.");
	size_t const rowOffset = range.location % rowActual;
	size_t const max = MIN(info.length, NSMaxRange(range));
	if(rowTheoretical > rowOffset) return NSMakeRange(range.location, MIN(rowTheoretical - rowOffset, max - range.location));
	off_t const nextOffset = range.location - rowOffset + rowActual;
	return NSMakeRange(nextOffset, MIN(rowTheoretical, max - nextOffset));
}
static off_t ECVBufferCopyToOffsetFromRange(ECVBufferInfo dst, ECVBufferInfo src, off_t dstOffset, NSRange srcRange)
{
	if(!dst.bytes || !dst.length || !src.bytes || !src.length) return dstOffset;
	NSCAssert(ECVFullFrame != dst.fieldType || !dst.doubledLines, @"Full frames cannot be line doubled.");
	NSCAssert(dst.pixelFormatType == src.pixelFormatType, @"ECVBufferCopyToOffsetFromRange doesn't convert formats.");
	NSCAssert(ECVEqualPixelSizes(dst.pixelSize, src.pixelSize), @"ECVBufferCopyToOffsetFromRange doesn't convert sizes.");
	size_t const dstMax = dst.length;
	size_t const srcMax = MIN(src.length, NSMaxRange(srcRange));
	off_t i = dstOffset;
	off_t j = srcRange.location;
	while(i < dstMax && j < srcMax) {
		NSRange const dstRow = ECVBufferNextRowInRange(dst, NSMakeRange(i, dstMax - i));
		NSRange const srcRow = ECVBufferNextRowInRange(src, NSMakeRange(j, srcMax - j));
		size_t const length = MIN(dstRow.length, srcRow.length);
		memcpy(dst.bytes + dstRow.location, src.bytes + srcRow.location, length);
		if(dst.doubledLines) {
			size_t const alternate = dstRow.location + dst.bytesPerRow;
			memcpy(dst.bytes + alternate, src.bytes + j, MIN(dstMax - alternate, length));
		}
		i = dstRow.location + length;
		j = srcRow.location + length;
		if(length >= dstRow.length && ECVFullFrame != dst.fieldType) i += dst.bytesPerRow;
		if(length >= srcRow.length && ECVFullFrame != src.fieldType) j += src.bytesPerRow;
	}
	return MIN(i, dstMax) - dstOffset;
}

NS_INLINE uint64_t ECVPixelFormatBlackPattern(OSType t)
{
	switch(t) {
		case k2vuyPixelFormat: return CFSwapInt64HostToBig(0x8010801080108010ULL);
	}
	return 0;
}

@interface ECVVideoFrame(Private)

- (ECVBufferInfo)_bufferInfo;

@end

@implementation ECVVideoFrame

#pragma mark -ECVVideoFrame

- (id)initWithFieldType:(ECVFieldType)type storage:(ECVVideoStorage *)storage
{
	NSAssert(![self isMemberOfClass:[ECVVideoFrame class]], @"ECVVideoFrame is an abstract class and should never be instantiated directly.");
	NSAssert([[storage deinterlacingMode] isAcceptableFieldType:type], @"Field type not allowed in current deinterlacing mode.");
	if((self = [super init])) {
		_videoStorage = storage;
		_fieldType = type;
		if([[_videoStorage deinterlacingMode] hasOffsetFields] && ECVLowField == _fieldType) _byteRange.location = [_videoStorage bytesPerRow];
	}
	return self;
}
@synthesize videoStorage = _videoStorage;
@synthesize fieldType = _fieldType;

#pragma mark -

- (void)clearRange:(NSRange)range resetLength:(BOOL)flag
{
	if(range.length) {
		uint64_t const val = ECVPixelFormatBlackPattern([_videoStorage pixelFormatType]);
		memset_pattern8([self bufferBytes] + range.location, &val, range.length);
	}
	if(flag) _byteRange.length = 0;
}
- (void)clear
{
	[self clearRange:NSMakeRange(0, [_videoStorage bufferSize]) resetLength:YES];
}
- (void)clearHead
{
	[self clearRange:NSMakeRange(0, _byteRange.location) resetLength:NO];
}
- (void)clearTail
{
	[self clearRange:NSMakeRange(NSMaxRange(_byteRange), [_videoStorage bufferSize] - NSMaxRange(_byteRange)) resetLength:NO];
}

#pragma mark -

- (void)fillWithFrame:(ECVVideoFrame *)frame
{
	if([frame lockIfHasBuffer]) {
		memcpy([self bufferBytes], [frame bufferBytes], [_videoStorage bufferSize]);
		[frame unlock];
		_byteRange.length = 0;
	} else [self clear];
}
- (void)fillHead
{
	if(!_byteRange.location) return;
	void *const bytes = [self bufferBytes];
	memcpy(bytes, bytes + _byteRange.location, _byteRange.location);
}
- (void)blurWithFrame:(ECVVideoFrame *)frame
{
	if(!frame) return;
	size_t const l = [_videoStorage bufferSize];
	UInt8 *const dst = [self bufferBytes];
	if([frame lockIfHasBuffer]) {
		NSUInteger i;
		UInt8 *const src = [frame bufferBytes];
		for(i = 0; i < l; i++) dst[i] = dst[i] / 2 + src[i] / 2;
		[frame unlock];
	}
}
- (void)appendBytes:(void const *)bytes length:(size_t)length
{
	ECVBufferInfo const dstInfo = [self _bufferInfo];
	ECVBufferInfo const srcInfo = {
		(void *)bytes,
		length,
		ECVFullFrame,
		NO,
		dstInfo.bytesPerRow,
		dstInfo.pixelFormatType,
		dstInfo.pixelSize,
	};
	_byteRange.length += ECVBufferCopyToOffsetFromRange(dstInfo, srcInfo, NSMaxRange(_byteRange), NSMakeRange(0, srcInfo.length));
}
- (void)copyToPixelBuffer:(CVPixelBufferRef)pixelBuffer
{
	if(!pixelBuffer) return;
	ECVCVReturn(CVPixelBufferLockBaseAddress(pixelBuffer, kNilOptions));
	ECVBufferInfo srcInfo = [self _bufferInfo];
	srcInfo.fieldType = ECVFullFrame;
	srcInfo.doubledLines = NO;
	ECVBufferInfo const dstInfo = {
		CVPixelBufferGetBaseAddress(pixelBuffer),
		CVPixelBufferGetDataSize(pixelBuffer),
		ECVFullFrame,
		NO,
		CVPixelBufferGetBytesPerRow(pixelBuffer),
		CVPixelBufferGetPixelFormatType(pixelBuffer),
		{CVPixelBufferGetWidth(pixelBuffer), CVPixelBufferGetHeight(pixelBuffer)},
	};
	(void)ECVBufferCopyToOffsetFromRange(dstInfo, srcInfo, 0, NSMakeRange(0, srcInfo.length));
	ECVCVReturn(CVPixelBufferUnlockBaseAddress(pixelBuffer, kNilOptions));
}

#pragma mark -ECVVideoFrame(Private)

- (ECVBufferInfo)_bufferInfo
{
	ECVDeinterlacingMode *const d = [_videoStorage deinterlacingMode];
	return (ECVBufferInfo){
		[self bufferBytes],
		[_videoStorage bufferSize],
		[d hasOffsetFields] ? _fieldType : ECVFullFrame,
		[d drawsDoubledLines],
		[_videoStorage bytesPerRow],
		[_videoStorage pixelFormatType],
		[_videoStorage pixelSize],
	};
}

@end
