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

@interface ECVVideoStorage(Private)

- (void)_read;
- (void)_readOneFrame;

@end

static void ECVReadOneFrame(CFRunLoopTimerRef timer, ECVVideoStorage *self)
{
	NSAutoreleasePool *const pool = [[NSAutoreleasePool alloc] init];
	[self _readOneFrame];
	[pool drain];
}

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
}
- (OSType)pixelFormat
{
	return _pixelFormat;
}
- (void)setPixelFormat:(OSType)format
{
	_pixelFormat = format;
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
	[pipe setOutputFrameRate:[self frameRate]];
	[pipe setOutputPixelSize:[pipe inputPixelSize]];
	[pipe setOutputPixelFormat:[self pixelFormat]];
	[self lock];
	[self addPipe:pipe];
	[self unlock];
}
- (void)removeVideoPipe:(ECVVideoPipe *)pipe
{
	[self lock];
	[self removePipe:pipe];
	[self unlock];
}

#pragma mark -ECVVideoStorage(Private)

- (void)_read
{
	NSAutoreleasePool *const pool = [[NSAutoreleasePool alloc] init];
	ECVLog(ECVNotice, @"Starting video storage thread.");
	NSTimeInterval interval = 0.0;
	(void)QTGetTimeInterval([self frameRate], &interval);
	NSAssert(interval, @"Video storage must have valid frame rate.");

	CFRunLoopTimerContext context = { .version = 0, .info = self };
	CFRunLoopTimerRef const timer = CFRunLoopTimerCreate(kCFAllocatorDefault, 0.0, interval, kNilOptions, 0, (CFRunLoopTimerCallBack)ECVReadOneFrame, &context);
	CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, kCFRunLoopDefaultMode);

	CFRunLoopRun();

	CFRunLoopTimerInvalidate(timer);
	CFRelease(timer);
	ECVLog(ECVNotice, @"Stopping video storage thread.");
	[pool drain];
}
- (void)_readOneFrame
{
	[self lock];
	ECVMutablePixelBuffer *const buffer = [self nextBuffer];
	NSArray *const pipes = [self pipes];
	[self unlock];

	for(ECVVideoPipe *const pipe in pipes) [pipe readIntoStorageBuffer:buffer];

	[self lock];
	ECVVideoFrame *const frame = [self finishedFrameWithFinishedBuffer:buffer];
	if(!_read) CFRunLoopStop(CFRunLoopGetCurrent());
	[self unlock];

	if(frame) [[self delegate] videoStorage:self didFinishFrame:frame];
}

#pragma mark -ECVStorage

- (void)play
{
	[self lock];
	_read = YES;
	[self unlock];
	[NSThread detachNewThreadSelector:@selector(_read) toTarget:self withObject:nil];
}
- (void)stop
{
	[self lock];
	_read = NO;
	[self unlock];
}

#pragma mark -NSObject

- (id)init
{
	if((self = [super init])) {
		_lock = [[NSRecursiveLock alloc] init];
	}
	return self;
}
- (void)dealloc
{
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
