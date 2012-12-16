/* Copyright (c) 2011, Ben Trask
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
#import "ECVIndependentVideoStorage.h"
#import "ECVVideoFrame.h"
#import "ECVVideoFormat.h"

@interface ECVIndependentVideoFrame : ECVVideoFrame
{
	@private
	NSMutableData *_data;
}

- (id)initWithVideoStorage:(ECVVideoStorage *)storage data:(NSMutableData *)data;

@end

@implementation ECVIndependentVideoStorage

#pragma mark -ECVVideoStorage(ECVAbstract)

- (ECVVideoFrame *)currentFrame
{
	[self lock];
	ECVVideoFrame *const frame = [[_currentFrame retain] autorelease];
	[self unlock];
	return frame;
}

#pragma mark -

- (ECVMutablePixelBuffer *)nextBuffer
{
	NSMutableData *const data = [NSMutableData dataWithLength:[self bufferSize]];
	ECVMutablePixelBuffer *const buffer = [[[ECVDataPixelBuffer alloc] initWithPixelSize:[[self videoFormat] frameSize] bytesPerRow:[self bytesPerRow] pixelFormat:[self pixelFormat] data:data offset:0] autorelease];
	return buffer;
}
- (ECVVideoFrame *)finishedFrameWithFinishedBuffer:(id)buffer
{
	[self lock];
	[_currentFrame release];
	_currentFrame = [[ECVIndependentVideoFrame alloc] initWithVideoStorage:self data:[buffer mutableData]];
	ECVVideoFrame *const frame = [[_currentFrame retain] autorelease];
	[self unlock];
	return frame;
}

@end

@implementation ECVIndependentVideoFrame

#pragma mark -ECVIndependentVideoFrame

- (id)initWithVideoStorage:(ECVVideoStorage *)storage data:(NSMutableData *)data
{
	if((self = [super initWithVideoStorage:storage])) {
		_data = [data retain];
	}
	return self;
}

#pragma mark -ECVVideoFrame(ECVAbstract)

- (void const *)bytes
{
	return [_data bytes];
}

#pragma mark -

- (BOOL)hasBytes
{
	return YES;
}
- (BOOL)lockIfHasBytes
{
	return YES;
}

#pragma mark -ECVVideoFrame(ECVAbstract) <NSLocking>

- (void)lock {}
- (void)unlock {}

#pragma mark -NSObject

- (void)dealloc
{
	[_data release];
	[super dealloc];
}

@end
