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
#import "ECVVideoStorage.h"

// Models
#import "ECVVideoFrame.h"

#define ECVExtraBufferCount 10

@interface ECVVideoStorage(Private)

- (void)_dropFrames;

@end

@implementation ECVVideoStorage

#pragma mark -ECVVideoStorage

- (id)initWithPixelFormatType:(OSType)formatType deinterlacingMode:(ECVDeinterlacingMode)mode originalSize:(ECVPixelSize)size frameRate:(QTTime)frameRate
{
	if((self = [super init])) {
		_numberOfBuffers = ECVUndroppableFrameCount + ECVExtraBufferCount;
		_pixelFormatType = formatType;
		_deinterlacingMode = mode;
		_originalSize = size;
		_frameRate = frameRate;
		_bytesPerRow = [self pixelSize].width * [self bytesPerPixel];
		_bufferSize = [self pixelSize].height * [self bytesPerRow];
		_allBufferData = [[NSMutableData alloc] initWithLength:_numberOfBuffers * _bufferSize];

		_lock = [[NSRecursiveLock alloc] init];
		_frames = [[NSMutableArray alloc] init];
		_unusedBufferIndexes = [[NSMutableIndexSet alloc] initWithIndexesInRange:NSMakeRange(0, _numberOfBuffers)];
	}
	return self;
}
@synthesize numberOfBuffers = _numberOfBuffers;
@synthesize pixelFormatType = _pixelFormatType;
@synthesize deinterlacingMode = _deinterlacingMode;
- (BOOL)halfHeight
{
	return _deinterlacingMode == ECVBlur || _deinterlacingMode == ECVLineDouble;
}
@synthesize originalSize = _originalSize;
- (ECVPixelSize)pixelSize
{
	return [self halfHeight] ? (ECVPixelSize){_originalSize.width, _originalSize.height / 2} : _originalSize;
}
@synthesize frameRate = _frameRate;
- (size_t)bytesPerPixel
{
	switch(_pixelFormatType) {
		case k2vuyPixelFormat: return 2;
	}
	return 0;
}
@synthesize bytesPerRow = _bytesPerRow;
@synthesize bufferSize = _bufferSize;
- (void *)allBufferBytes
{
	return [_allBufferData mutableBytes];
}
- (NSUInteger)frameGroupSize
{
	return ECVProgressiveScan == _deinterlacingMode ? 1 : 2;
}

#pragma mark -

- (ECVVideoFrame *)nextFrameWithFieldType:(ECVFieldType)type
{
	[_lock lock];
	NSUInteger index = [_unusedBufferIndexes firstIndex];
	if(NSNotFound == index) {
		[self _dropFrames];
		index = [_unusedBufferIndexes firstIndex];
	}
	ECVVideoFrame *frame = nil;
	if(NSNotFound != index) {
		frame = [[[ECVVideoFrame alloc] initWithStorage:self bufferIndex:index fieldType:type] autorelease];
		[_frames insertObject:frame atIndex:0];
		[_unusedBufferIndexes removeIndex:index];
	}
	[_lock unlock];
	return frame;
}
- (ECVVideoFrame *)frameAtIndex:(NSUInteger)i
{
	[_lock lock];
	ECVVideoFrame *const frame = i < [_frames count] ? [[[_frames objectAtIndex:i] retain] autorelease] : nil;
	[_lock unlock];
	return frame;
}

#pragma mark -

- (void *)bufferBytesAtIndex:(NSUInteger)index
{
	return [_allBufferData mutableBytes] + _bufferSize * index;
}
- (BOOL)removeFrame:(ECVVideoFrame *)frame
{
	if(!frame) return NO;
	[_lock lock];
	NSUInteger const i = [_frames indexOfObjectIdenticalTo:frame];
	BOOL drop = NSNotFound != i && i >= ECVUndroppableFrameCount;
	if(drop) {
		[[frame retain] autorelease];
		[_frames removeObjectAtIndex:i];
		[_unusedBufferIndexes addIndex:[frame bufferIndex]];
	}
	[_lock unlock];
	return drop;
}

#pragma mark -ECVVideoStorage(Private)

- (void)_dropFrames
{
	NSArray *const frames = [[_frames copy] autorelease];
	NSUInteger const count = [frames count];
	NSUInteger const drop = MIN(MAX(count, ECVUndroppableFrameCount) - ECVUndroppableFrameCount, [self frameGroupSize]);
	[[frames subarrayWithRange:NSMakeRange(count - drop, drop)] makeObjectsPerformSelector:@selector(removeFromStorage)];
}

#pragma mark -NSObject

- (void)dealloc
{
	[_allBufferData release];
	[_lock release];
	[_frames release];
	[_unusedBufferIndexes release];
	[super dealloc];
}

@end
