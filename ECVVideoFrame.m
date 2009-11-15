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
#import "ECVVideoFrame.h"

// Views
#import "ECVVideoView.h"

@implementation ECVVideoFrame

#pragma mark -ECVAttachedFrame

- (id)initWithVideoView:(ECVVideoView *)view bufferIndex:(NSUInteger)index
{
	if((self = [super init])) {
		_videoView = view;
		_bufferIndex = index;
		_videoViewLock = [[NSLock alloc] init];
	}
	return self;
}
- (NSUInteger)bufferIndex
{
	return _bufferIndex;
}
- (void)invalidateWait:(BOOL)wait
{
	if(wait) [_videoViewLock lock];
	else if(![_videoViewLock tryLock]) return;
	[self markAsInvalid];
	[_videoViewLock unlock];
}
- (void)invalidate
{
	[self invalidateWait:YES];
}
- (void)tryToInvalidate
{
	[self invalidateWait:NO];
}

#pragma mark -NSObject

- (void)dealloc
{
	NSParameterAssert(!_videoView);
	[_videoViewLock release];
	[super dealloc];
}

#pragma mark -<ECVFrameReading>

- (BOOL)isValid
{
	return !!_videoView;
}
- (void *)bufferBytes
{
	return [_videoView bufferBytesAtIndex:_bufferIndex];
}
- (NSUInteger)bufferSize
{
	return _videoView.bufferSize;
}
- (ECVPixelSize)pixelSize
{
	return _videoView.pixelSize;
}
- (OSType)pixelFormatType
{
	return _videoView.pixelFormatType;
}
- (size_t)bytesPerRow
{
	return _videoView.bytesPerRow;
}
- (void)markAsInvalid
{
	[_videoView invalidateFrame:self];
	_videoView = nil;
}

#pragma mark -<NSLocking>

- (void)lock
{
	[_videoViewLock lock];
}
- (void)unlock
{
	[_videoViewLock unlock];
}

@end
