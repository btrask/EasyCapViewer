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
#import "ECVVideoPipe.h"

// Models/Sources/Video
#import "ECVVideoSource.h"

// Models/Storages/Video
#import "ECVVideoStorage.h"

// Models
#import "ECVPixelBufferConverter.h"

@implementation ECVVideoPipe

#pragma mark -ECVVideoPipe

- (id)initWithVideoSource:(ECVVideoSource *)source
{
	if((self = [super initWithSource:source])) {
		_lock = [[NSLock alloc] init];
	}
	return self;
}
- (id)videoSource
{
	return [self source];
}
- (ECVVideoStorage *)videoStorage
{
	return (ECVVideoStorage *)[self storage];
}

#pragma mark -

- (QTTime)inputFrameRate
{
	return _inputFrameRate;
}
- (ECVIntegerSize)inputPixelSize
{
	return _inputPixelSize;
}
- (OSType)inputPixelFormat
{
	return _inputPixelFormat;
}

#pragma mark -

- (QTTime)outputFrameRate
{
	return _outputFrameRate;
}
- (ECVIntegerSize)outputPixelSize
{
	return _outputPixelSize;
}
- (OSType)outputPixelFormat
{
	return _outputPixelFormat;
}

#pragma mark -

- (ECVIntegerPoint)position
{
	return _position;
}
- (void)setPosition:(ECVIntegerPoint)point
{
	[_lock lock];
	_position = point;
	[_lock unlock];
}

#pragma mark -ECVVideoPipe(ECVFromSource)

- (void)setInputFrameRate:(QTTime)rate
{
	[_lock lock];
	_inputFrameRate = rate;
	[_converter release];
	_converter = nil;
	[_lock unlock];
}
- (void)setInputPixelSize:(ECVIntegerSize)size
{
	[_lock lock];
	_inputPixelSize = size;
	[_converter release];
	_converter = nil;
	[_lock unlock];
}
- (void)setInputPixelFormat:(OSType)format
{
	[_lock lock];
	_inputPixelFormat = format;
	[_converter release];
	_converter = nil;
	[_lock unlock];
}

#pragma mark -ECVVideoPipe(ECVFromSource_Threaded)

- (void)writeField:(ECVPixelBuffer *)buffer type:(ECVFieldType)fieldType
{
	if(ECVHighField != fieldType) return;
	[_lock lock];
	[_buffer release];
	_buffer = [buffer retain];
	[_lock unlock];
}

#pragma mark -ECVVideoPipe(ECVFromStorage)

- (void)setVideoStorage:(ECVVideoStorage *)videoStorage
{
	[self setStorage:videoStorage];
}

#pragma mark -

- (void)setOutputFrameRate:(QTTime)rate
{
	[_lock lock];
	_outputFrameRate = rate;
	[_converter release];
	_converter = nil;
	[_lock unlock];
}
- (void)setOutputPixelSize:(ECVIntegerSize)size
{
	[_lock lock];
	_outputPixelSize = size;
	[_converter release];
	_converter = nil;
	[_lock unlock];
}
- (void)setOutputPixelFormat:(OSType)format
{
	[_lock lock];
	_outputPixelFormat = format;
	[_converter release];
	_converter = nil;
	[_lock unlock];
}

#pragma mark -ECVVideoPipe(ECVFromStorage_Threaded)

- (void)readIntoStorageBuffer:(ECVMutablePixelBuffer *)buffer
{
	[_lock lock];
	if(!_converter) _converter = [[ECVPixelBufferConverter alloc] initWithInputSize:[self inputPixelSize] pixelFormat:[self inputPixelFormat] outputSize:[self outputPixelSize] pixelFormat:[self outputPixelFormat]];
	ECVPixelBuffer *const current = [[_buffer retain] autorelease];
	ECVIntegerPoint const position = [self position];
	ECVPixelBufferConverter *const converter = [[_converter retain] autorelease];
	[_lock unlock];
	ECVPixelBuffer *const convertedCurrentBuffer = [converter convertedPixelBuffer:current];
	if([convertedCurrentBuffer lockIfHasBytes]) {
		[buffer drawPixelBuffer:convertedCurrentBuffer options:kNilOptions atPoint:position];
		[convertedCurrentBuffer unlock];
	}
}

#pragma mark -NSObject

- (void)dealloc
{
	[_lock release];
	[_buffer release];
	[_converter release];
	[super dealloc];
}

@end
