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
#import "ECVDeinterlacingMode.h"

enum {
	ECVPendingFrameIndex,
	ECVPotentiallyCompletedFrameIndex, // May not be fully processed, depending on the deinterlacing mode.
	ECVGuaranteedCompletedFrame2Index,
	ECVUndroppableFrameCount,
};

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

#pragma mark +ECVVideoStorage

+ (Class)preferredVideoStorageClass
{
	Class const dependentVideoStorage = NSClassFromString(@"ECVDependentVideoStorage");
	return dependentVideoStorage ? dependentVideoStorage : self;
}

#pragma mark -ECVVideoStorage

- (id)initWithPixelFormatType:(OSType)formatType deinterlacingMode:(ECVDeinterlacingMode)mode originalSize:(ECVIntegerSize)size frameRate:(QTTime)frameRate
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
	}
	return self;
}
@synthesize pixelFormatType = _pixelFormatType;
@synthesize deinterlacingMode = _deinterlacingMode;
@synthesize originalSize = _originalSize;
- (ECVIntegerSize)pixelSize
{
	return ECVDeinterlacingModePixelSize(_deinterlacingMode, _originalSize);
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
	return ECVDeinterlacingModeFrameGroupSize(_deinterlacingMode);
}

#pragma mark -

- (ECVVideoFrame *)nextFrameWithFieldType:(ECVFieldType)type
{
	[self lock];
	[self removeOldestFrameGroup];
	ECVVideoFrame *const frame = [[[ECVIndependentVideoFrame alloc] initWithFieldType:type storage:self] autorelease];
	[self addVideoFrame:frame];
	[self unlock];
	return frame;
}
- (ECVVideoFrame *)currentFrame
{
	NSUInteger const i = [self _newestCompletedFrameIndex];
	[self lock];
	ECVVideoFrame *const frame = i < [_frames count] ? [[[_frames objectAtIndex:i] retain] autorelease] : nil;
	[self unlock];
	return frame;
}

#pragma mark -

- (void)removeOldestFrameGroup
{
	NSUInteger const count = [_frames count];
	NSUInteger const realMax = MIN([self frameGroupSize], SUB_ZERO(count, [self _newestCompletedFrameIndex] + 1));
	if(realMax) [[_frames subarrayWithRange:NSMakeRange(count - realMax, realMax)] makeObjectsPerformSelector:@selector(removeFromStorageIfPossible)];
}
- (void)addVideoFrame:(ECVVideoFrame *)frame
{
	NSParameterAssert(frame);
	[_frames insertObject:frame atIndex:0];
}
- (BOOL)removeFrame:(ECVVideoFrame *)frame
{
	if(!frame) return NO;
	[self lock];
	NSUInteger const i = [_frames indexOfObjectIdenticalTo:frame];
	BOOL drop = NSNotFound != i && i >= ECVUndroppableFrameCount;
	if(drop) {
		[self removingFrame:[[frame retain] autorelease]];
		[_frames removeObjectAtIndex:i];
	}
	[self unlock];
	return drop;
}
- (void)removingFrame:(ECVVideoFrame *)frame {}

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

#pragma mark -NSObject

- (void)dealloc
{
	[_lock release];
	[_frames release];
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
- (void)removeFromStorageIfPossible
{
	(void)[[self videoStorage] removeFrame:self];
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
