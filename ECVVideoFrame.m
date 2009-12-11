/* Copyright (c) 2009, Ben Trask
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
#import "ECVVideoFrame.h"

// Models
#import "ECVVideoStorage.h"

// Other Sources
#import "ECVDebug.h"
#import "ECVReadWriteLock.h"

typedef struct {
	void *bytes;
	size_t length;
	ECVFieldType fieldType;
	BOOL doubledLines;
	size_t bytesPerRow;
	OSType pixelFormatType;
	ECVPixelSize pixelSize;
} ECVBufferInfo;
static size_t ECVBufferRemainingInRange(ECVBufferInfo info, NSRange range)
{
	size_t const actual = info.bytesPerRow;
	size_t const theoretical = ECVPixelFormatBytesPerPixel(info.pixelFormatType) * info.pixelSize.width;
	NSCAssert(actual >= theoretical, @"Row padding must be non-negative.");
	size_t const actualOffset = range.location % actual;
	NSAssert(theoretical >= actualOffset, @"Invalid position.");
	size_t const remaining = theoretical - actualOffset;
	size_t const max = MIN(info.length, NSMaxRange(range));
	return MIN(remaining, max - range.location);
}
static off_t ECVBufferCopyToOffsetFromRange(ECVBufferInfo dst, ECVBufferInfo src, off_t dstOffset, NSRange srcRange)
{
	if(!dst.bytes || !dst.length || !src.bytes || !src.length) return dstOffset;
	NSCAssert(dst.pixelFormatType == src.pixelFormatType, @"ECVBufferCopy doesn't convert formats.");
	NSCAssert(ECVEqualPixelSizes(dst.pixelSize, src.pixelSize), @"ECVBufferCopy doesn't convert sizes.");
	size_t const dstTheoretical = ECVPixelFormatBytesPerPixel(dst.pixelFormatType) * dst.pixelSize.width;
	size_t const srcTheoretical = ECVPixelFormatBytesPerPixel(src.pixelFormatType) * src.pixelSize.width;
	size_t const dstActual = dst.bytesPerRow;
	size_t const srcActual = src.bytesPerRow;
	NSCAssert(dstActual >= dstTheoretical, @"ECVBufferCopy destination row padding must be non-negative.");
	NSCAssert(srcActual >= srcTheoretical, @"ECVBufferCopy source row padding must be non-negative.");
	size_t const dstPadding = dstActual - dstTheoretical;
	size_t const srcPadding = srcActual - srcTheoretical;
	size_t const dstMax = dst.length;
	size_t const srcMax = MIN(src.length, NSMaxRange(srcRange));
	off_t i = dstOffset;
	off_t j = srcRange.location;
	while(i < dstMax && j < srcMax) {
		size_t const dstRemaining = ECVBufferRemainingInRange(dst, NSMakeRange(i, dstMax - i));
		size_t const srcRemaining = ECVBufferRemainingInRange(src, NSMakeRange(j, srcMax - j));
		size_t const length = MIN(dstRemaining, srcRemaining);
		memcpy(dst.bytes + i, src.bytes + j, length);
		if(dst.doubledLines && !src.doubledLines) {
			size_t const alternate = i + dstActual;
			memcpy(dst.bytes + alternate, src.bytes + j, MIN(dstMax - alternate, length));
		}
		i += length;
		j += length;
		if(length == dstRemaining) {
			i += dstPadding;
			if(ECVFullFrame != dst.fieldType) i += dstActual;
		}
		if(length == srcRemaining) {
			j += srcPadding;
			if(ECVFullFrame != src.fieldType) j += srcActual;
		}
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

#pragma mark -ECVAttachedFrame

- (id)initWithStorage:(ECVVideoStorage *)storage bufferIndex:(NSUInteger)index fieldType:(ECVFieldType)type
{
	NSAssert((ECVFullFrame == type) == (ECVProgressiveScan == [storage deinterlacingMode]), @"Field type and deinterlacing mode must match.");
	if((self = [super init])) {
		_lock = [[ECVReadWriteLock alloc] init];
		_videoStorage = storage;
		_bufferIndex = index;
		_fieldType = type;
		switch([_videoStorage deinterlacingMode]) {
			case ECVWeave:
			case ECVLineDoubleHQ:
			case ECVAlternate:
				if(ECVLowField == _fieldType) _byteRange.location = [_videoStorage bytesPerRow];
				break;
		}
	}
	return self;
}
@synthesize videoStorage = _videoStorage;
@synthesize bufferIndex = _bufferIndex;
@synthesize fieldType = _fieldType;

#pragma mark -

- (BOOL)hasBuffer
{
	return NSNotFound != _bufferIndex;
}
- (void *)bufferBytes
{
	return [_videoStorage bufferBytesAtIndex:_bufferIndex];
}
- (BOOL)lockIfHasBuffer
{
	[self lock];
	if([self hasBuffer]) return YES;
	[self unlock];
	return NO;
}

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
	ECVBufferInfo const dstInfo = {
		CVPixelBufferGetBaseAddress(pixelBuffer),
		CVPixelBufferGetDataSize(pixelBuffer),
		srcInfo.fieldType,
		srcInfo.doubledLines,
		CVPixelBufferGetBytesPerRow(pixelBuffer),
		CVPixelBufferGetPixelFormatType(pixelBuffer),
		{CVPixelBufferGetWidth(pixelBuffer), CVPixelBufferGetHeight(pixelBuffer)},
	};
	(void)ECVBufferCopyToOffsetFromRange(dstInfo, srcInfo, 0, NSMakeRange(0, srcInfo.length));
	ECVCVReturn(CVPixelBufferUnlockBaseAddress(pixelBuffer, kNilOptions));
}

#pragma mark -

- (void)removeFromStorage
{
	NSAssert([self hasBuffer], @"Frame not in storage to begin with.");
	if(![_lock tryWriteLock]) return;
	if([_videoStorage removeFrame:self]) _bufferIndex = NSNotFound;
	[_lock unlock];
}

#pragma mark -ECVVideoFrame(Private)

- (ECVBufferInfo)_bufferInfo
{
	return (ECVBufferInfo){
		[self bufferBytes],
		[_videoStorage bufferSize],
		[_videoStorage halfHeight] ? ECVFullFrame : _fieldType,
		[_videoStorage deinterlacingMode] == ECVLineDoubleHQ,
		[_videoStorage bytesPerRow],
		[_videoStorage pixelFormatType],
		[_videoStorage pixelSize],
	};
}

#pragma mark -NSObject

- (void)dealloc
{
	[_lock release];
	[super dealloc];
}

#pragma mark -<NSLocking>

- (void)lock
{
	[_lock readLock];
}
- (void)unlock
{
	[_lock unlock];
}

@end
