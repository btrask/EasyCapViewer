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

// Other Sources
#import "ECVReadWriteLock.h"

enum {
	ECVPendingFrameIndex,
	ECVPotentiallyCompletedFrameIndex, // May not be fully processed, depending on the deinterlacing mode.
	ECVGuaranteedCompletedFrame2Index,
	ECVUndroppableFrameCount,
};

@interface ECVDependentVideoFrame : ECVVideoFrame
{
	@private
	ECVReadWriteLock *_lock;
	NSUInteger _bufferIndex;
}

- (id)initWithFieldType:(ECVFieldType)type storage:(ECVVideoStorage *)storage bufferIndex:(NSUInteger)index;

@end

@interface ECVIndependentVideoFrame : ECVVideoFrame
{
	@private
	void *_bufferBytes;
}

@end

@interface ECVVideoStorage(Private)

- (NSUInteger)_newestCompletedFrameIndex;
- (BOOL)_removeFrame:(ECVVideoFrame *)frame;

@end

@implementation ECVVideoStorage

#pragma mark -ECVVideoStorage

- (id)initWithPixelFormatType:(OSType)formatType deinterlacingMode:(ECVDeinterlacingMode)mode originalSize:(ECVPixelSize)size frameRate:(QTTime)frameRate
{
	if((self = [super init])) {
		_pixelFormatType = formatType;
		_deinterlacingMode = mode;
		_originalSize = size;
		_frameRate = frameRate;
		_bytesPerRow = [self pixelSize].width * [self bytesPerPixel];
		_bufferSize = [self pixelSize].height * [self bytesPerRow];

		_lock = [[NSRecursiveLock alloc] init];
		_frames = [[NSMutableArray alloc] initWithCapacity:ECVUndroppableFrameCount];
#ifdef ECV_DEPENDENT_VIDEO_STORAGE
		_numberOfBuffers = ECVUndroppableFrameCount + 15;
		_allBufferData = [[NSMutableData alloc] initWithLength:_numberOfBuffers * [self bufferSize]];
		_unusedBufferIndexes = [[NSMutableIndexSet alloc] initWithIndexesInRange:NSMakeRange(0, _numberOfBuffers)];
#endif
	}
	return self;
}
@synthesize pixelFormatType = _pixelFormatType;
@synthesize deinterlacingMode = _deinterlacingMode;
- (BOOL)halfHeight
{
	return _deinterlacingMode == ECVBlur || _deinterlacingMode == ECVLineDoubleLQ;
}
@synthesize originalSize = _originalSize;
- (ECVPixelSize)pixelSize
{
	return [self halfHeight] ? (ECVPixelSize){_originalSize.width, _originalSize.height / 2} : _originalSize;
}
@synthesize frameRate = _frameRate;
- (size_t)bytesPerPixel
{
	return ECVPixelFormatBytesPerPixel(_pixelFormatType);
}
@synthesize bytesPerRow = _bytesPerRow;
@synthesize bufferSize = _bufferSize;
- (NSUInteger)frameGroupSize
{
	return ECVProgressiveScan == _deinterlacingMode ? 1 : 2;
}

#pragma mark -

- (ECVVideoFrame *)nextFrameWithFieldType:(ECVFieldType)type
{
	[_lock lock];
#ifdef ECV_DEPENDENT_VIDEO_STORAGE
	NSUInteger index = [_unusedBufferIndexes firstIndex];
	if(NSNotFound == index) {
		NSUInteger const count = [_frames count];
		NSUInteger const drop = MIN(MAX(count, ECVUndroppableFrameCount) - ECVUndroppableFrameCount, [self frameGroupSize]);
		[[_frames subarrayWithRange:NSMakeRange(count - drop, drop)] makeObjectsPerformSelector:@selector(removeFromStorage)];
		index = [_unusedBufferIndexes firstIndex];
		if(NSNotFound == index) {
			[_lock unlock];
			return nil;
		}
	}
	[_unusedBufferIndexes removeIndex:index];
	ECVVideoFrame *const frame = [[[ECVDependentVideoFrame alloc] initWithFieldType:type storage:self bufferIndex:index] autorelease];
#else
	ECVVideoFrame *const frame = [[[ECVIndependentVideoFrame alloc] initWithFieldType:type storage:self] autorelease];
#endif
	[_frames insertObject:frame atIndex:0];
	[_lock unlock];
	return frame;
}

#pragma mark -

- (NSUInteger)numberOfCompletedFrames
{
	[_lock lock];
	NSUInteger const count = [_frames count];
	[_lock unlock];
	return SUB_ZERO(count, [self _newestCompletedFrameIndex] + 1);
}
- (ECVVideoFrame *)newestCompletedFrame
{
	NSUInteger const i = [self _newestCompletedFrameIndex];
	[_lock lock];
	ECVVideoFrame *const frame = i < [_frames count] ? [[[_frames objectAtIndex:i] retain] autorelease] : nil;
	[_lock unlock];
	return frame;
}
- (ECVVideoFrame *)oldestFrame
{
	[_lock lock];
	ECVVideoFrame *const frame = [[[_frames lastObject] retain] autorelease];
	[_lock unlock];
	return frame;
}

#pragma mark -

#ifdef ECV_DEPENDENT_VIDEO_STORAGE
@synthesize numberOfBuffers = _numberOfBuffers;
- (void *)allBufferBytes
{
	return [_allBufferData mutableBytes];
}
- (void *)bufferBytesAtIndex:(NSUInteger)index
{
	return [_allBufferData mutableBytes] + [self bufferSize] * index;
}
#endif

#pragma mark -

- (NSUInteger)numberOfFramesToDropWithCount:(NSUInteger)c
{
	NSUInteger const g = [self frameGroupSize];
	return c < g ? 0 : c - c % g;
}
- (NSUInteger)dropFramesFromArray:(NSMutableArray *)frames
{
	NSUInteger const count = [frames count];
	NSUInteger const drop = [self numberOfFramesToDropWithCount:count];
	[frames removeObjectsInRange:NSMakeRange(count - drop, drop)];
	return drop;
}

#pragma mark -ECVVideoStorage(Private)

- (NSUInteger)_newestCompletedFrameIndex
{
	return ECVBlur == [self deinterlacingMode] ? ECVGuaranteedCompletedFrame2Index : ECVPotentiallyCompletedFrameIndex;
}
- (BOOL)_removeFrame:(ECVVideoFrame *)frame
{
	if(!frame) return NO;
	[_lock lock];
	NSUInteger const i = [_frames indexOfObjectIdenticalTo:frame];
	BOOL drop = NSNotFound != i && i >= ECVUndroppableFrameCount;
	if(drop) {
		[[frame retain] autorelease];
		[_frames removeObjectAtIndex:i];
#ifdef ECV_DEPENDENT_VIDEO_STORAGE
		[_unusedBufferIndexes addIndex:[frame bufferIndex]];
#endif
	}
	[_lock unlock];
	return drop;
}

#pragma mark -NSObject

- (void)dealloc
{
	[_lock release];
	[_frames release];
#ifdef ECV_DEPENDENT_VIDEO_STORAGE
	[_allBufferData release];
	[_unusedBufferIndexes release];
#endif
	[super dealloc];
}

@end

@implementation ECVDependentVideoFrame

#pragma mark -ECVDependentVideoFrame

- (id)initWithFieldType:(ECVFieldType)type storage:(ECVVideoStorage *)storage bufferIndex:(NSUInteger)index
{
	if((self = [super initWithFieldType:type storage:storage])) {
		_lock = [[ECVReadWriteLock alloc] init];
		_bufferIndex = index;
	}
	return self;
}

#pragma mark -ECVVideoFrame(ECVAbstract)

- (void *)bufferBytes
{
#ifdef ECV_DEPENDENT_VIDEO_STORAGE
	return [[self videoStorage] bufferBytesAtIndex:_bufferIndex];
#else
	return NULL;
#endif
}
- (BOOL)hasBuffer
{
	return NSNotFound != _bufferIndex;
}
- (BOOL)lockIfHasBuffer
{
	[self lock];
	if([self hasBuffer]) return YES;
	[self unlock];
	return NO;
}
- (void)removeFromStorage
{
	NSAssert([self hasBuffer], @"Frame not in storage to begin with.");
	if(![_lock tryWriteLock]) return;
	if([[self videoStorage] _removeFrame:self]) _bufferIndex = NSNotFound;
	[_lock unlock];
}

#pragma mark -ECVVideoFrame(ECVDependentVideoFrame)

- (NSUInteger)bufferIndex
{
	return _bufferIndex;
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

@implementation ECVIndependentVideoFrame

#pragma mark -ECVIndependentVideoFrame

- (id)initWithFieldType:(ECVFieldType)type storage:(ECVVideoStorage *)storage
{
	if((self = [super initWithFieldType:type storage:storage])) {
		_bufferBytes = malloc([storage bufferSize]);
	}
	return self;
}

#pragma mark -ECVVideoFrame(ECVAbstract)

- (void *)bufferBytes
{
	return _bufferBytes;
}
- (BOOL)hasBuffer
{
	return YES;
}
- (BOOL)lockIfHasBuffer
{
	return YES;
}
- (void)removeFromStorage
{
	(void)[[self videoStorage] _removeFrame:self];
}

#pragma mark -NSObject

- (void)dealloc
{
	free(_bufferBytes);
	[super dealloc];
}

#pragma mark -<NSLocking>

- (void)lock {}
- (void)unlock {}

@end
