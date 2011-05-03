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

// Models/Pipes/Video
#import "ECVVideoPipe.h"

// Other Sources
#import "ECVDebug.h"

@implementation ECVVideoStorage

#pragma mark +NSObject

+ (id)allocWithZone:(NSZone *)zone
{
	if([ECVVideoStorage class] != self) return [super allocWithZone:zone];
	Class const dependentVideoStorage = NSClassFromString(@"ECVDependentVideoStorage");
	if(dependentVideoStorage) return [dependentVideoStorage allocWithZone:zone];
	Class const independentVideoStorage = NSClassFromString(@"ECVIndependentVideoStorage");
	if(independentVideoStorage) return [independentVideoStorage allocWithZone:zone];
	ECVAssertNotReached(@"No video storage class found.");
	return nil;
}

#pragma mark -ECVVideoStorage

@synthesize delegate = _delegate;
- (ECVIntegerSize)pixelSize
{
	return _pixelSize;
}
- (void)setPixelSize:(ECVIntegerSize)size
{
	_pixelSize = size;
	[_pendingBuffer release];
	_pendingBuffer = nil;
}
- (OSType)pixelFormat
{
	return _pixelFormat;
}
- (void)setPixelFormat:(OSType)format
{
	_pixelFormat = format;
	[_pendingBuffer release];
	_pendingBuffer = nil;
}
- (QTTime)frameRate
{
	return _frameRate;
}
- (void)setFrameRate:(QTTime)rate
{
	_frameRate = rate;
}
- (ECVRational)pixelAspectRatio
{
	return _pixelAspectRatio;
}
- (void)setPixelAspectRatio:(ECVRational)ratio
{
	_pixelAspectRatio = ratio;
}

#pragma mark -

- (size_t)bytesPerPixel
{
	return ECVPixelFormatBytesPerPixel(_pixelFormat);
}
- (size_t)bytesPerRow
{
	return [self pixelSize].width * [self bytesPerPixel];
}
- (size_t)bufferSize
{
	return [self pixelSize].height * [self bytesPerRow];
}

#pragma mark -

- (void)addVideoPipe:(ECVVideoPipe *)pipe
{
	[self addPipe:pipe];
	[_pendingPipes addObject:pipe];
}
- (void)removeVideoPipe:(ECVVideoPipe *)pipe
{
	[_pendingPipes removeObjectIdenticalTo:pipe];
	[self removePipe:pipe];
}

#pragma mark -

- (void)videoPipeDidFinishFrame:(ECVVideoPipe *)pipe
{
	[_pendingPipes removeObjectIdenticalTo:pipe];
	if([_pendingPipes count]) return;
	[_pendingPipes addObjectsFromArray:[self pipes]];
	for(ECVVideoPipe *const p in _pendingPipes) [p nextOutputFrame];
	if(_pendingBuffer) [[self delegate] videoStorage:self didFinishFrame:[self finishedFrameWithFinishedBuffer:[_pendingBuffer autorelease]]];
	_pendingBuffer = [[self nextBuffer] retain];
}
- (void)videoPipe:(ECVVideoPipe *)pipe drawPixelBuffer:(ECVPixelBuffer *)buffer
{
	[_pendingBuffer drawPixelBuffer:buffer options:kNilOptions atPoint:[pipe position]];
}

#pragma mark -NSObject

- (id)init
{
	if((self = [super init])) {
		_lock = [[NSRecursiveLock alloc] init];
		_pendingPipes = [[NSMutableArray alloc] init];
	}
	return self;
}
- (void)dealloc
{
	[_lock release];
	[_pendingPipes release];
	[_pendingBuffer release];
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
