/* Copyright (c) 2010, Ben Trask
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
#import "ECVDependentVideoStorage.h"

// Models
#import "ECVVideoFrame.h"

// Other Sources
#import "ECVReadWriteLock.h"

enum {
	ECVPendingFrameIndex,
	ECVPotentiallyCompletedFrameIndex, // May not be fully processed, depending on the deinterlacing mode.
	ECVGuaranteedCompletedFrame2Index,
	ECVUndroppableFrameCount,
};
#define ECVExtraBufferCount 15

@interface ECVDependentVideoFrame : ECVVideoFrame
{
	@private
	ECVReadWriteLock *_lock;
	NSUInteger _bufferIndex;
}

- (id)initWithFieldType:(ECVFieldType)type storage:(ECVVideoStorage *)storage bufferIndex:(NSUInteger)index;
- (void)removeFromStorage;

@end

@interface ECVDependentVideoStorage(Private)

- (ECVVideoFrame *)_frameAtIndex:(NSUInteger)i;
- (void)_dropFrames;

@end

@implementation ECVDependentVideoStorage

#pragma mark -ECVDependentVideoStorage

- (id)initWithPixelFormatType:(OSType)formatType deinterlacingMode:(ECVDeinterlacingMode)mode originalSize:(ECVPixelSize)size frameRate:(QTTime)frameRate
{
	if((self = [super initWithPixelFormatType:formatType deinterlacingMode:mode originalSize:size frameRate:frameRate])) {
		_numberOfBuffers = ECVUndroppableFrameCount + ECVExtraBufferCount;
		_allBufferData = [[NSMutableData alloc] initWithLength:_numberOfBuffers * [self bufferSize]];

		_lock = [[NSRecursiveLock alloc] init];
		_frames = [[NSMutableArray alloc] init];
		_unusedBufferIndexes = [[NSMutableIndexSet alloc] initWithIndexesInRange:NSMakeRange(0, _numberOfBuffers)];
	}
	return self;
}
@synthesize numberOfBuffers = _numberOfBuffers;
- (void *)allBufferBytes
{
	return [_allBufferData mutableBytes];
}
- (void *)bufferBytesAtIndex:(NSUInteger)index
{
	return [_allBufferData mutableBytes] + [self bufferSize] * index;
}

#pragma mark -

- (ECVVideoFrame *)lastCompletedFrame
{
	return [self _frameAtIndex:ECVBlur == [self deinterlacingMode] ? ECVGuaranteedCompletedFrame2Index : ECVPotentiallyCompletedFrameIndex];
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

#pragma mark -ECVDependentVideoStorage(Private)

- (ECVVideoFrame *)_frameAtIndex:(NSUInteger)i
{
	[_lock lock];
	ECVVideoFrame *const frame = i < [_frames count] ? [[[_frames objectAtIndex:i] retain] autorelease] : nil;
	[_lock unlock];
	return frame;
}
- (void)_dropFrames
{
	NSUInteger const count = [_frames count];
	NSUInteger const drop = MIN(MAX(count, ECVUndroppableFrameCount) - ECVUndroppableFrameCount, [self frameGroupSize]);
	[[_frames subarrayWithRange:NSMakeRange(count - drop, drop)] makeObjectsPerformSelector:@selector(removeFromStorage)];
}

#pragma mark -ECVVideoStorage

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
		frame = [[[ECVDependentVideoFrame alloc] initWithFieldType:type storage:self bufferIndex:index] autorelease];
		[_frames insertObject:frame atIndex:0];
		[_unusedBufferIndexes removeIndex:index];
	}
	[_lock unlock];
	return frame;
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
- (void)removeFromStorage
{
	NSAssert([self hasBuffer], @"Frame not in storage to begin with.");
	if(![_lock tryWriteLock]) return;
	if([[self videoStorage] removeFrame:self]) _bufferIndex = NSNotFound;
	[_lock unlock];
}

#pragma mark -ECVVideoFrame(ECVAbstract)

- (void *)bufferBytes
{
	return [[self videoStorage] bufferBytesAtIndex:_bufferIndex];
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

#pragma mark -ECVVideoFrame(ECVDependentVideoFrame)

@synthesize bufferIndex = _bufferIndex;

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
