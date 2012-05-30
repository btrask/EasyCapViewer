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

// Other Sources
#import "ECVPixelFormat.h"

@implementation ECVVideoStorage

#pragma mark +ECVVideoStorage

+ (Class)preferredVideoStorageClass
{
	Class const dependentVideoStorage = NSClassFromString(@"ECVDependentVideoStorage");
	if(dependentVideoStorage) return dependentVideoStorage;
	Class const independentVideoStorage = NSClassFromString(@"ECVIndependentVideoStorage");
	if(independentVideoStorage) return independentVideoStorage;
	ECVAssertNotReached(@"No video storage class found.");
	return nil;
}

#pragma mark -ECVVideoStorage

- (id)initWithDeinterlacingMode:(Class)mode captureSize:(ECVIntegerSize)captureSize pixelFormat:(OSType)pixelFormat frameRate:(QTTime)frameRate
{
	NSAssert([mode isSubclassOfClass:[ECVDeinterlacingMode class]], @"Deinterlacing mode must be a subclass of ECVDeinterlacingMode.");
	if((self = [super init])) {
		_deinterlacingMode = [[mode alloc] initWithVideoStorage:self];
		_captureSize = captureSize;
		_pixelFormat = pixelFormat;
		_frameRate = frameRate;
		_bytesPerRow = [self pixelSize].width * [self bytesPerPixel];
		_bufferSize = [self pixelSize].height * [self bytesPerRow];
		_lock = [[NSRecursiveLock alloc] init];
	}
	return self;
}
@synthesize captureSize = _captureSize;
- (ECVIntegerSize)pixelSize
{
	return [_deinterlacingMode pixelSize];
}
@synthesize pixelFormat = _pixelFormat;
@synthesize frameRate = _frameRate;
- (size_t)bytesPerPixel
{
	return ECVPixelFormatBytesPerPixel(_pixelFormat);
}
@synthesize bytesPerRow = _bytesPerRow;
@synthesize bufferSize = _bufferSize;
- (NSUInteger)frameGroupSize
{
	return [_deinterlacingMode frameGroupSize];
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

- (ECVVideoFrame *)finishedFrameWithNextFieldType:(ECVFieldType)fieldType
{
	ECVMutablePixelBuffer *const buffer = [_deinterlacingMode finishedBufferWithNextFieldType:fieldType];
	return buffer ? [self finishedFrameWithFinishedBuffer:buffer] : nil;
}
- (void)drawPixelBuffer:(ECVPixelBuffer *)buffer atPoint:(ECVIntegerPoint)point
{
	[_deinterlacingMode drawPixelBuffer:buffer atPoint:point];
}

#pragma mark -NSObject

- (void)dealloc
{
	[_deinterlacingMode release];
	[_lock release];
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
