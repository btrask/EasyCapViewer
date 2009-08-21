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
#import "ECVFrame.h"

@implementation ECVFrame

#pragma mark -ECVFrame

- (id)initWithData:(NSData *)buffer pixelSize:(ECVPixelSize)size pixelFormatType:(OSType)formatType bytesPerRow:(size_t)rowSize
{
	if((self = [super init])) {
		_bufferData = [buffer copy];
		_pixelSize = size;
		_pixelFormatType = formatType;
		_bytesPerRow = rowSize;
	}
	return self;
}
- (id)initWithFrameReadingObject:(id<ECVFrameReading>)frame
{
	return [self initWithData:frame.bufferData pixelSize:frame.pixelSize pixelFormatType:frame.pixelFormatType bytesPerRow:frame.bytesPerRow];
}
@synthesize time = _time;

#pragma mark -NSObject

- (void)dealloc
{
	[_bufferData release];
	[super dealloc];
}

#pragma mark -<ECVFrameReading>

@synthesize bufferData = _bufferData;
- (NSUInteger)bufferSize
{
	return [_bufferData length];
}
@synthesize pixelSize = _pixelSize;
@synthesize pixelFormatType = _pixelFormatType;
@synthesize bytesPerRow = _bytesPerRow;

#pragma mark -<NSCopying>

- (id)copyWithZone:(NSZone *)zone
{
	ECVFrame *const dupe = [[[self class] alloc] initWithFrameReadingObject:self];
	dupe.time = self.time;
	return dupe;
}

@end
