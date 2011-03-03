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

@interface ECVDependentVideoFrame : ECVVideoFrame
{
	@private
	ECVReadWriteLock *_lock;
	NSUInteger _bufferIndex;
}

- (id)initWithFieldType:(ECVFieldType)type storage:(ECVVideoStorage *)storage bufferIndex:(NSUInteger)i;

@end

@implementation ECVDependentVideoStorage

#pragma mark -ECVDependentVideoStorage

@synthesize numberOfBuffers = _numberOfBuffers;
- (void *)allBufferBytes
{
	return [_allBufferData mutableBytes];
}
- (void *)bufferBytesAtIndex:(NSUInteger)i
{
	return [_allBufferData mutableBytes] + [self bufferSize] * i;
}

#pragma mark -ECVVideoStorage

- (id)initWithPixelFormatType:(OSType)formatType deinterlacingMode:(ECVDeinterlacingMode)mode originalSize:(ECVIntegerSize)size frameRate:(QTTime)frameRate
{
	if((self = [super initWithPixelFormatType:formatType deinterlacingMode:mode originalSize:size frameRate:frameRate])) {
		_numberOfBuffers = 16;
		_allBufferData = [[NSMutableData alloc] initWithLength:_numberOfBuffers * [self bufferSize]];
		_unusedBufferIndexes = [[NSMutableIndexSet alloc] initWithIndexesInRange:NSMakeRange(0, _numberOfBuffers)];
	}
	return self;
}

#pragma mark -

- (ECVVideoFrame *)nextFrameWithFieldType:(ECVFieldType)type
{
	if(ECVDrop == [self deinterlacingMode] && type == ECVLowField) return nil;
	[self lock];
	NSUInteger i = [_unusedBufferIndexes firstIndex];
	if(NSNotFound == i) {
		[self removeOldestFrameGroup];
		i = [_unusedBufferIndexes firstIndex];
		if(NSNotFound == i) {
			[self unlock];
			return nil;
		}
	}
	[_unusedBufferIndexes removeIndex:i];
	ECVVideoFrame *const frame = [[[ECVDependentVideoFrame alloc] initWithFieldType:type storage:self bufferIndex:i] autorelease];
	[self addVideoFrame:frame];
	[self unlock];
	return frame;
}

#pragma mark -

- (void)removingFrame:(ECVVideoFrame *)frame
{	
	[_unusedBufferIndexes addIndex:[frame bufferIndex]];
	[super removingFrame:frame];
}

#pragma mark -NSObject

- (void)dealloc
{
	[_allBufferData release];
	[_unusedBufferIndexes release];
	[super dealloc];
}

@end

@implementation ECVDependentVideoFrame

#pragma mark -ECVVideoFrame

- (id)initWithFieldType:(ECVFieldType)type storage:(ECVVideoStorage *)storage bufferIndex:(NSUInteger)i
{
	if((self = [super initWithFieldType:type storage:storage])) {
		_lock = [[ECVReadWriteLock alloc] init];
		_bufferIndex = i;
	}
	return self;
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
- (void)removeFromStorageIfPossible
{
	NSAssert([self hasBuffer], @"Frame not in storage to begin with.");
	if(![_lock tryWriteLock]) return;
	if([[self videoStorage] removeFrame:self]) _bufferIndex = NSNotFound;
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
