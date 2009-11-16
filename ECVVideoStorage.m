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
#import "ECVVideoStorage.h"

// Models
#import "ECVVideoFrame.h"

NS_INLINE size_t ECVPixelFormatTypeBytesPerPixel(OSType t)
{
	switch(t) {
		case k2vuyPixelFormat: return 2;
	}
	return 0;
}

@interface ECVVideoStorage(Private)

- (void)_dropFrames;

@end

@implementation ECVVideoStorage

#pragma mark -ECVVideoStorage

- (id)initWithNumberOfBuffers:(NSUInteger)count pixelFormatType:(OSType)formatType size:(ECVPixelSize)size frameRate:(QTTime)frameRate
{
	if((self = [super init])) {
		_numberOfBuffers = count;
		_pixelFormatType = formatType;
		_pixelSize = size;
		_frameRate = frameRate;
		_bytesPerRow = _pixelSize.width * ECVPixelFormatTypeBytesPerPixel(_pixelFormatType);
		_bufferSize = _bytesPerRow * _pixelSize.height;
		_allBufferData = [[NSMutableData alloc] initWithLength:_numberOfBuffers * _bufferSize];

		_lock = [[NSRecursiveLock alloc] init];
		_frames = CFArrayCreateMutable(kCFAllocatorDefault, 0, NULL);
		_unusedBufferIndexes = [[NSMutableIndexSet alloc] initWithIndexesInRange:NSMakeRange(0, _numberOfBuffers)];
	}
	return self;
}
@synthesize numberOfBuffers = _numberOfBuffers;
@synthesize pixelFormatType = _pixelFormatType;
@synthesize pixelSize = _pixelSize;
@synthesize frameRate = _frameRate;
@synthesize bytesPerRow = _bytesPerRow;
@synthesize bufferSize = _bufferSize;
- (void *)allBufferBytes
{
	return [_allBufferData mutableBytes];
}

#pragma mark -

- (void *)bufferBytesAtIndex:(NSUInteger)index
{
	return [_allBufferData mutableBytes] + _bufferSize * index;
}

#pragma mark -

- (ECVVideoFrame *)nextFrame
{
	[_lock lock];
	NSUInteger index = [_unusedBufferIndexes firstIndex];
	if(NSNotFound == index) {
		[self _dropFrames];
		index = [_unusedBufferIndexes firstIndex];
	}
	ECVVideoFrame *frame = nil;
	if(NSNotFound != index) {
		frame = [[[ECVVideoFrame alloc] initWithStorage:self bufferIndex:index] autorelease];
		CFArrayAppendValue(_frames, frame);
		[_unusedBufferIndexes removeIndex:index];
	}
	[_lock unlock];
	return frame;
}
- (void)removeFrame:(ECVVideoFrame *)frame
{
	if(!frame) return;
	[_lock lock];
	CFIndex const i = CFArrayGetFirstIndexOfValue(_frames, CFRangeMake(0, CFArrayGetCount(_frames)), frame);
	if(kCFNotFound != i) {
		CFArrayRemoveValueAtIndex(_frames, i);
		[_unusedBufferIndexes addIndex:[frame bufferIndex]];
	}
	[_lock unlock];
}

#pragma mark -ECVVideoStorage(Private)

- (void)_dropFrames
{
	CFIndex const count = CFArrayGetCount(_frames);
	NSUInteger const keep = count % 2;
	[[(NSArray *)_frames subarrayWithRange:NSMakeRange(0, count - keep)] makeObjectsPerformSelector:@selector(removeFromStorage)];
}

#pragma mark -NSObject

- (void)dealloc
{
	[_allBufferData release];
	[_lock release];
	CFRelease(_frames);
	[_unusedBufferIndexes release];
	[super dealloc];
}

@end
