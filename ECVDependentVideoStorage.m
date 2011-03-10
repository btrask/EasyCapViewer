/* Copyright (c) 2009-2010, Ben Trask
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
#import "ECVDependentVideoStorage.h"

// Other Sources
#import "ECVReadWriteLock.h"

#define ECVDependentBufferCount 16

@interface ECVDependentPixelBuffer : ECVMutablePixelBuffer
{
	@private
	ECVDependentVideoStorage *_videoStorage;
	NSUInteger _bufferIndex;
}

- (id)initWithVideoStorage:(ECVDependentVideoStorage *)storage bufferIndex:(NSUInteger)i;
- (NSUInteger)bufferIndex;

@end

@interface ECVDependentVideoFrame : ECVVideoFrame
{
	@private
	ECVReadWriteLock *_lock;
	NSUInteger _bufferIndex;
}

- (id)initWithVideoStorage:(ECVVideoStorage *)storage bufferIndex:(NSUInteger)i;
- (void)removeFromStorageIfPossible;

@end

@interface ECVDependentVideoFrame(Private)

- (BOOL)_removeFrame:(ECVVideoFrame *)frame;

@end

@implementation ECVDependentVideoStorage

#pragma mark -ECVDependentVideoStorage

@synthesize numberOfBuffers = _numberOfBuffers;
- (void *)allBufferBytes
{
	return [_allBufferData mutableBytes];
}
- (void *)bytesAtIndex:(NSUInteger)i
{
	return [_allBufferData mutableBytes] + [self bufferSize] * i;
}

#pragma mark -ECVDependentVideoFrame(Private)

- (BOOL)_removeFrame:(ECVVideoFrame *)frame
{
	if(!frame) return NO;
	[self lock];
	NSUInteger const i = [_frames indexOfObjectIdenticalTo:frame];
	BOOL drop = NSNotFound != i;
	if(drop) {
		[[frame retain] autorelease];
		[_unusedBufferIndexes addIndex:[frame bufferIndex]];
		[_frames removeObjectAtIndex:i];
	}
	[self unlock];
	return drop;
}

#pragma mark -ECVVideoStorage

- (id)initWithDeinterlacingMode:(Class)mode captureSize:(ECVIntegerSize)captureSize pixelFormat:(OSType)pixelFormatType frameRate:(QTTime)frameRate
{
	if((self = [super initWithDeinterlacingMode:mode captureSize:captureSize pixelFormat:pixelFormatType frameRate:frameRate])) {
		_frames = [[NSMutableArray alloc] initWithCapacity:ECVDependentBufferCount];
		_numberOfBuffers = ECVDependentBufferCount;
		_allBufferData = [[NSMutableData alloc] initWithLength:_numberOfBuffers * [self bufferSize]];
		_unusedBufferIndexes = [[NSMutableIndexSet alloc] initWithIndexesInRange:NSMakeRange(0, _numberOfBuffers)];
	}
	return self;
}

#pragma mark -ECVVideoStorage(ECVAbstract)

- (ECVVideoFrame *)currentFrame
{
	[self lock];
	ECVVideoFrame *const frame = [[[_frames lastObject] retain] autorelease];
	[self unlock];
	return frame;
}

#pragma mark -

- (ECVMutablePixelBuffer *)nextBuffer
{
	NSUInteger i = [_unusedBufferIndexes firstIndex];
	if(NSNotFound == i) {
		NSUInteger const frameCount = [_frames count];
		NSUInteger const framesToKeep = ((frameCount - 1) % [self frameGroupSize]) + 1;
		[[_frames subarrayWithRange:NSMakeRange(0, frameCount - framesToKeep)] makeObjectsPerformSelector:@selector(removeFromStorageIfPossible)];
		i = [_unusedBufferIndexes firstIndex];
		if(NSNotFound == i) return nil;
	}
	[_unusedBufferIndexes removeIndex:i];
	return [[[ECVDependentPixelBuffer alloc] initWithVideoStorage:self bufferIndex:i] autorelease];
}
- (ECVVideoFrame *)finishedFrameWithFinishedBuffer:(id)buffer
{
	ECVVideoFrame *const frame = [[[ECVDependentVideoFrame alloc] initWithVideoStorage:self bufferIndex:[buffer bufferIndex]] autorelease];
	[_frames addObject:frame];
	return frame;
}

#pragma mark -NSObject

- (void)dealloc
{
	[_frames release];
	[_allBufferData release];
	[_unusedBufferIndexes release];
	[super dealloc];
}

@end

@implementation ECVDependentPixelBuffer

#pragma mark -ECVDependentPixelBuffer

- (id)initWithVideoStorage:(ECVDependentVideoStorage *)storage bufferIndex:(NSUInteger)i
{
	if((self = [super init])) {
		_videoStorage = storage;
		_bufferIndex = i;
	}
	return self;
}
- (NSUInteger)bufferIndex
{
	return _bufferIndex;
}

#pragma mark -ECVMutablePixelBuffer(ECVAbstract)

- (void *)mutableBytes
{
	return [_videoStorage bytesAtIndex:_bufferIndex];
}

#pragma mark -ECVPixelBuffer(ECVAbstract)

- (ECVIntegerSize)pixelSize
{
	return [_videoStorage pixelSize];
}
- (size_t)bytesPerRow
{
	return [_videoStorage bytesPerRow];
}
- (OSType)pixelFormatType
{
	return [_videoStorage pixelFormatType];
}

#pragma mark -

- (void const *)bytes
{
	return [_videoStorage bytesAtIndex:_bufferIndex];
}
- (NSRange)validRange
{
	return NSMakeRange(0, [_videoStorage bufferSize]);
}

#pragma mark -ECVPixelBuffer(ECVAbstract) <NSLocking>

- (void)lock{}
- (void)unlock{}

@end

@implementation ECVDependentVideoFrame

#pragma mark -ECVDependentVideoFrame

- (id)initWithVideoStorage:(ECVVideoStorage *)storage bufferIndex:(NSUInteger)i
{
	if((self = [super initWithVideoStorage:storage])) {
		_lock = [[ECVReadWriteLock alloc] init];
		_bufferIndex = i;
	}
	return self;
}
- (void)removeFromStorageIfPossible
{
	NSAssert([self hasBytes], @"Frame not in storage to begin with.");
	if(![_lock tryWriteLock]) return;
	if([[self videoStorage] _removeFrame:self]) _bufferIndex = NSNotFound;
	[_lock unlock];
}

#pragma mark -ECVVideoFrame(ECVAbstract)

- (void const *)bytes
{
	return [[self videoStorage] bytesAtIndex:_bufferIndex];
}

#pragma mark -

- (BOOL)hasBytes
{
	return NSNotFound != _bufferIndex;
}
- (BOOL)lockIfHasBytes
{
	[self lock];
	if([self hasBytes]) return YES;
	[self unlock];
	return NO;
}

#pragma mark -ECVVideoFrame(ECVAbstract) <NSLocking>

- (void)lock
{
	[_lock readLock];
}
- (void)unlock
{
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

@end
