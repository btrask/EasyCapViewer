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
#import "ECVVideoFrame.h"

// Models
#import "ECVVideoFormat.h"
#import "ECVVideoStorage.h"

// Other Sources
#import "ECVDebug.h"
#import "ECVFoundationAdditions.h"

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
	return [[_videoStorage videoFormat] frameSize];
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
