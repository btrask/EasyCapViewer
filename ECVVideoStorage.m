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
#import "ECVVideoStorage.h"

// Models
#import "ECVDeinterlacingMode.h"

@interface ECVIndependentVideoFrame : ECVVideoFrame
{
	@private
	void *_bufferBytes;
}

@end

@interface ECVVideoStorage(Private)

- (ECVVideoFrame *)_finishCurrentFrame;
- (ECVVideoFrame *)_nextFrameWithFieldType:(ECVFieldType)type;

@end

@implementation ECVVideoStorage

#pragma mark +ECVVideoStorage

+ (Class)preferredVideoStorageClass
{
	Class const dependentVideoStorage = NSClassFromString(@"ECVDependentVideoStorage");
	return dependentVideoStorage ? dependentVideoStorage : self;
}

#pragma mark -ECVVideoStorage

- (id)initWithDeinterlacingMode:(Class)mode captureSize:(ECVIntegerSize)captureSize pixelFormat:(OSType)pixelFormatType frameRate:(QTTime)frameRate
{
	NSAssert([mode isSubclassOfClass:[ECVDeinterlacingMode class]], @"Deinterlacing mode must be a subclass of ECVDeinterlacingMode.");
	if((self = [super init])) {
		_deinterlacingMode = [[mode alloc] init];
		_captureSize = captureSize;
		_pixelFormatType = pixelFormatType;
		_frameRate = frameRate;
		_bytesPerRow = [self pixelSize].width * [self bytesPerPixel];
		_bufferSize = [self pixelSize].height * [self bytesPerRow];

		_lock = [[NSRecursiveLock alloc] init];
		_frames = [[NSMutableArray alloc] initWithCapacity:[_deinterlacingMode newestCompletedFrameIndex] + 1];
	}
	return self;
}
@synthesize deinterlacingMode = _deinterlacingMode;
@synthesize captureSize = _captureSize;
- (ECVIntegerSize)pixelSize
{
	return [_deinterlacingMode outputSizeForCaptureSize:_captureSize];
}
@synthesize pixelFormatType = _pixelFormatType;
@synthesize frameRate = _frameRate;
- (size_t)bytesPerPixel
{
	return ECVPixelFormatBytesPerPixel(_pixelFormatType);
}
@synthesize bytesPerRow = _bytesPerRow;
@synthesize bufferSize = _bufferSize;

#pragma mark -

- (ECVVideoFrame *)currentFrame
{
	NSUInteger const i = [_deinterlacingMode newestCompletedFrameIndex];
	[self lock];
	ECVVideoFrame *const frame = i < [_frames count] ? [[[_frames objectAtIndex:i] retain] autorelease] : nil;
	[self unlock];
	return frame;
}

#pragma mark -

- (NSUInteger)numberOfFramesToDropWithCount:(NSUInteger)c
{
	NSUInteger const g = [_deinterlacingMode frameGroupSize];
	return c < g ? 0 : c - c % g;
}
- (NSUInteger)dropFramesFromArray:(NSMutableArray *)frames
{
	NSUInteger const count = [frames count];
	NSUInteger const drop = [self numberOfFramesToDropWithCount:count];
	[frames removeObjectsInRange:NSMakeRange(count - drop, drop)];
	return drop;
}

#pragma mark -

- (ECVVideoFrame *)generateFrameWithFrieldType:(ECVFieldType)type
{
	[self removeOldestFrameGroup];
	return [[[ECVIndependentVideoFrame alloc] initWithFieldType:type storage:self] autorelease];
}
- (void)removeOldestFrameGroup
{
	NSUInteger const count = [_frames count];
	NSUInteger const realMax = MIN([_deinterlacingMode frameGroupSize], SUB_ZERO(count, [_deinterlacingMode newestCompletedFrameIndex] + 1));
	if(realMax) [[_frames subarrayWithRange:NSMakeRange(count - realMax, realMax)] makeObjectsPerformSelector:@selector(removeFromStorageIfPossible)];
}
- (void)addVideoFrame:(ECVVideoFrame *)frame
{
	NSParameterAssert(frame);
	[_frames insertObject:frame atIndex:0];
	[_deinterlacingMode prepareNewFrameInArray:_frames];
}
- (BOOL)removeFrame:(ECVVideoFrame *)frame
{
	if(!frame) return NO;
	[self lock];
	NSUInteger const i = [_frames indexOfObjectIdenticalTo:frame];
	BOOL drop = NSNotFound != i && i > [_deinterlacingMode newestCompletedFrameIndex];
	if(drop) {
		[self removingFrame:[[frame retain] autorelease]];
		[_frames removeObjectAtIndex:i];
	}
	[self unlock];
	return drop;
}
- (void)removingFrame:(ECVVideoFrame *)frame {}

#pragma mark -ECVVideoStorage(Private)

- (ECVVideoFrame *)_finishCurrentFrame
{
	[_deinterlacingMode finishNewFrameInArray:_frames];
	return [self currentFrame];
}
- (ECVVideoFrame *)_nextFrameWithFieldType:(ECVFieldType)type
{
	if([_deinterlacingMode shouldDropFieldWithType:type]) return nil;
	[self lock];
	ECVVideoFrame *const frame = [self generateFrameWithFrieldType:type];
	if(frame) [self addVideoFrame:frame];
	[self unlock];
	return frame;
}

#pragma mark -NSObject

- (void)dealloc
{
	[_deinterlacingMode release];
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

@implementation ECVVideoFrameBuilder

#pragma mark -ECVVideoFrameBuilder

- (id)initWithVideoStorage:(ECVVideoStorage *)storage
{
	if((self = [super init])) {
		_thread = [[NSThread currentThread] retain];
		_videoStorage = [storage retain];
		_firstFrame = YES;
	}
	return self;
}
@synthesize videoStorage = _videoStorage;

- (ECVVideoFrame *)completedFrame
{
	NSAssert([NSThread currentThread] == _thread, @"Frame builders must be used from the thread where they are created.");
	[_pendingFrame release];
	_pendingFrame = nil;
	return [_videoStorage _finishCurrentFrame];
}
- (void)startNewFrameWithFieldType:(ECVFieldType)type
{
	NSAssert([NSThread currentThread] == _thread, @"Frame builders must be used from the thread where they are created.");
	if(_firstFrame) {
		_firstFrame = NO;
		return;
	}
	_pendingFrame = [[_videoStorage _nextFrameWithFieldType:type] retain];
}
- (void)appendBytes:(void const *)bytes length:(size_t)length
{
	NSAssert([NSThread currentThread] == _thread, @"Frame builders must be used from the thread where they are created.");
	[_pendingFrame appendBytes:bytes length:length];
}

#pragma mark -NSObject

- (void)dealloc
{
	[_thread release];
	[_videoStorage release];
	[_pendingFrame release];
	[super dealloc];
}

@end
