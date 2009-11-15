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

NS_INLINE uint64_t ECVPixelFormatBlackPattern(OSType t)
{
	switch(t) {
		case k2vuyPixelFormat: return CFSwapInt64HostToBig(0x8010801080108010ULL);
	}
	return 0;
}

@implementation ECVVideoFrame

#pragma mark -ECVAttachedFrame

- (id)initWithStorage:(ECVVideoStorage *)storage bufferIndex:(NSUInteger)index
{
	if((self = [super init])) {
		_lock = [[NSLock alloc] init];

		_videoStorage = storage;
		_bufferIndex = index;

		_pixelSize = [_videoStorage pixelSize];
		_pixelFormatType = [_videoStorage pixelFormatType];
		_bytesPerRow = [_videoStorage bytesPerRow];
	}
	return self;
}
- (NSUInteger)bufferIndex
{
	return _bufferIndex;
}

#pragma mark -

- (BOOL)isValid
{
	return _videoStorage || _bufferData;
}
- (BOOL)isDroppable
{
	return _droppable;
}
- (BOOL)isDropped
{
	return !_videoStorage;
}
- (BOOL)isDetached
{
	return !!_bufferData;
}

#pragma mark -

- (void *)bufferBytes
{
	return _bufferData ? [_bufferData mutableBytes] : [_videoStorage bufferBytesAtIndex:_bufferIndex];
}
- (size_t)bufferSize
{
	return _bufferData ? [_bufferData length] : [_videoStorage bufferSize];
}
- (ECVPixelSize)pixelSize
{
	return _pixelSize;
}
- (OSType)pixelFormatType
{
	return _pixelFormatType;
}
- (size_t)bytesPerRow
{
	return _bytesPerRow;
}

#pragma mark -

- (void)becomeDroppable
{
	[_lock lock];
	_droppable = YES;
	[_lock unlock];
}
- (void)detachInsteadOfDroppingWhenRemoved
{
	[_lock lock];
	_detachInsteadOfDroppingWhenRemoved = YES;
	[_lock unlock];
}
- (BOOL)removeFromStorage
{
	if(!_videoStorage || !_droppable) return NO;
	if(_detachInsteadOfDroppingWhenRemoved) _bufferData = [[NSMutableData alloc] initWithBytes:[self bufferBytes] length:[self bufferSize]];
	[_videoStorage removeFrame:self];
	_videoStorage = nil;
	_bufferIndex = NSNotFound;
	return YES;
}
- (BOOL)lockAndRemoveFromStorage
{
	[_lock lock];
	BOOL const success = [self removeFromStorage];
	[_lock unlock];
	return success;
}
- (BOOL)tryLockAndRemoveFromStorage
{
	if(![_lock tryLock]) return NO;
	BOOL success = [self removeFromStorage];
	[_lock unlock];
	return success;
}

#pragma mark -

- (void)clear
{
	uint64_t const val = ECVPixelFormatBlackPattern([self pixelFormatType]);
	memset_pattern8([self bufferBytes], &val, [self bufferSize]);
}
- (void)fillWithFrame:(ECVVideoFrame *)frame
{
	BOOL filled = NO;
	if(frame) {
		[frame lock];
		if([frame isValid]) {
			size_t const l = MIN([self bufferSize], [frame bufferSize]);
			UInt8 *const src = [frame bufferBytes];
			UInt8 *const dst = [self bufferBytes];
			memcpy(dst, src, l);
			filled = YES;
		}
		[frame unlock];
	}
	if(!filled) [self clear];
}
- (void)blurWithFrame:(ECVVideoFrame *)frame
{
	if(!frame) return;
	[frame lock];
	if([frame isValid]) {
		size_t const l = MIN([self bufferSize], [frame bufferSize]);
		UInt8 *const src = [frame bufferBytes];
		UInt8 *const dst = [self bufferBytes];
		NSUInteger i;
		for(i = 0; i < l; i++) dst[i] = dst[i] / 2 + src[i] / 2;
	}
	[frame unlock];
}

#pragma mark -NSObject

- (void)dealloc
{
	[_videoStorage removeFrame:self];
	[_lock release];
	[_bufferData release];
	[super dealloc];
}

#pragma mark -<NSLocking>

- (void)lock
{
	[_lock lock];
}
- (void)unlock
{
	[_lock unlock];
}

@end
