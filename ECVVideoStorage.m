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
	[self lock];
	[self addPipe:pipe];
	CFSetAddValue(_pendingPipes, pipe);
	[self unlock];
}
- (void)removeVideoPipe:(ECVVideoPipe *)pipe
{
	[self lock];
	CFSetRemoveValue(_pendingPipes, pipe);
	[self removePipe:pipe];
	[self unlock];
}

#pragma mark -ECVVideoStorage(ECVFromPipe_Thread)

- (void)videoPipeDidFinishFrame:(ECVVideoPipe *)pipe
{
	BOOL finishedFrame = NO;
	ECVVideoFrame *frame = nil;
	[self lock];
	CFSetRemoveValue(_pendingPipes, pipe);
	if(!CFSetGetCount(_pendingPipes)) {
		[(NSMutableSet *)_pendingPipes addObjectsFromArray:[self pipes]];
		finishedFrame = YES;
		if(_pendingBuffer) {
			frame = [self finishedFrameWithFinishedBuffer:_pendingBuffer];
			[_pendingBuffer release];
		}
		_pendingBuffer = [[self nextBuffer] retain];
	}
	[self unlock];
	if(finishedFrame) for(ECVVideoPipe *const p in (NSSet *)_pendingPipes) [p nextOutputFrame];
	if(frame) [[self delegate] videoStorage:self didFinishFrame:frame];
}
- (void)videoPipe:(ECVVideoPipe *)pipe drawPixelBuffer:(ECVPixelBuffer *)buffer
{
	// We don't need to lock because _pendingBuffer only changes once every frame is done drawing to it.
	// We don't need to expose the drawing options because by this point, the buffer should already be deinterlaced.
	[_pendingBuffer drawPixelBuffer:buffer options:ECVDrawToHighField | ECVDrawToLowField atPoint:[pipe position]]; // TODO: We should use kNilOptions once we have deinterlacing.
}

#pragma mark -NSObject

- (id)init
{
	if((self = [super init])) {
		_lock = [[NSRecursiveLock alloc] init];
		_pendingPipes = CFSetCreateMutable(kCFAllocatorDefault, 0, NULL);
	}
	return self;
}
- (void)dealloc
{
	[_lock release];
	if(_pendingPipes) CFRelease(_pendingPipes);
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

@implementation ECVVideoFrame

#pragma mark -ECVVideoFrame

- (id)initWithVideoStorage:(ECVVideoStorage *)storage
{
	if((self = [super init])) {
		_videoStorage = storage;
	}
	return self;
}
@synthesize videoStorage = _videoStorage;

#pragma mark -ECVPixelBuffer(ECVAbstract)

- (ECVIntegerSize)pixelSize
{
	return [_videoStorage pixelSize];
}
- (size_t)bytesPerRow
{
	return [_videoStorage bytesPerRow];
}
- (OSType)pixelFormat
{
	return [_videoStorage pixelFormat];
}

#pragma mark -

- (NSRange)validRange
{
	return NSMakeRange(0, [self hasBytes] ? [[self videoStorage] bufferSize] : 0);
}

@end
