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
#import <pthread.h>

// Models
#import "ECVVideoStorage.h"

// Other Sources
#import "ECVDebug.h"

NS_INLINE uint64_t ECVPixelFormatBlackPattern(OSType t)
{
	switch(t) {
		case k2vuyPixelFormat: return CFSwapInt64HostToBig(0x8010801080108010ULL);
	}
	return 0;
}

@interface ECVVideoFrame(Private)

- (void)_resetLength;

@end

@implementation ECVVideoFrame

#pragma mark -ECVAttachedFrame

- (id)initWithStorage:(ECVVideoStorage *)storage bufferIndex:(NSUInteger)index fieldType:(ECVFieldType)type
{
	NSAssert((ECVFullFrame == type) == (ECVProgressiveScan == [storage deinterlacingMode]), @"Field type and deinterlacing mode must match.");
	if((self = [super init])) {
		ECVErrno(pthread_rwlock_init(&_lock, NULL));
		_videoStorage = storage;
		_bufferIndex = index;
		_fieldType = type;
		[self _resetLength];
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

- (BOOL)removeFromStorage
{
	int const error = pthread_rwlock_trywrlock(&_lock);
	if(error) {
		if(EBUSY != error) ECVErrno(error);
		return NO;
	}
	BOOL success = NO;
	if(_videoStorage) {
		[_videoStorage removeFrame:self];
		_bufferIndex = NSNotFound;
		success = YES;
	}
	ECVErrno(pthread_rwlock_unlock(&_lock));
	return success;
}
- (void)invalidate
{
	ECVErrno(pthread_rwlock_wrlock(&_lock));
	_videoStorage = nil;
	_bufferIndex = NSNotFound;
	ECVErrno(pthread_rwlock_unlock(&_lock));
}

#pragma mark -

- (void)clear
{
	uint64_t const val = ECVPixelFormatBlackPattern([_videoStorage pixelFormatType]);
	memset_pattern8([self bufferBytes], &val, [_videoStorage bufferSize]);
	[self _resetLength];
}
- (void)fillWithFrame:(ECVVideoFrame *)frame
{
	if([frame lockIfHasBuffer]) {
		memcpy([self bufferBytes], [frame bufferBytes], [_videoStorage bufferSize]);
		[frame unlock];
		[self _resetLength];
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
	[self _resetLength];
}
- (void)appendBytes:(void const *)bytes length:(size_t)length
{
	if(!bytes || !length) return;
	UInt8 *const dest = [self bufferBytes];
	if(!dest) return;
	size_t const maxLength = [_videoStorage bufferSize];
	size_t const theoreticalRowLength = [_videoStorage pixelSize].width * [_videoStorage bytesPerPixel];
	size_t const actualRowLength = [_videoStorage bytesPerRow];
	size_t const rowPadding = actualRowLength - theoreticalRowLength;
	BOOL const skipLines = ECVFullFrame != _fieldType && ![_videoStorage halfHeight];

	size_t used = 0;
	size_t rowOffset = _length % actualRowLength;
	while(used < length) {
		size_t const remainingRowLength = theoreticalRowLength - rowOffset;
		size_t const unused = length - used;
		BOOL const isFinishingRow = unused >= remainingRowLength;
		size_t const rowFillLength = MIN(maxLength - _length, MIN(remainingRowLength, unused));
		memcpy(dest + _length, bytes + used, rowFillLength);
		_length += rowFillLength;
		if(_length >= maxLength) break;
		if(isFinishingRow) {
			_length += rowPadding;
			if(skipLines) _length += actualRowLength;
		}
		used += rowFillLength;
		rowOffset = 0;
	}
}

#pragma mark -ECVVideoFrame(Private)

- (void)_resetLength
{
	ECVDeinterlacingMode const m = [_videoStorage deinterlacingMode];
	_length = ECVLowField == _fieldType && (ECVWeave == m || ECVAlternate == m) ? [_videoStorage bytesPerRow] : 0;
}

#pragma mark -NSObject

- (void)dealloc
{
	ECVErrno(pthread_rwlock_destroy(&_lock));
	[super dealloc];
}

#pragma mark -<NSLocking>

- (void)lock
{
	ECVErrno(pthread_rwlock_rdlock(&_lock));
}
- (void)unlock
{
	ECVErrno(pthread_rwlock_unlock(&_lock));
}

@end
