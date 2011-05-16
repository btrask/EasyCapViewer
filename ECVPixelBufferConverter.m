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
#import "ECVPixelBufferConverter.h"

// Models/Storages/Video
#import "ECVPixelBuffer.h"

// Other Sources
#import "ECVDebug.h"

@implementation ECVPixelBufferConverter

#pragma mark +ECVPixelBufferConverter

+ (enum PixelFormat)AVPixelFormatWithOSType:(OSType)pixelFormat
{
	switch(pixelFormat) {
		case kCVPixelFormatType_422YpCbCr8: return PIX_FMT_UYVY422;
		case kCVPixelFormatType_420YpCbCr8Planar: return PIX_FMT_YUV420P;
	}
	ECVCAssertNotReached(@"Unsupported pixel format.");
	return PIX_FMT_NONE;
}

#pragma mark -ECVPixelBufferConverter

- (id)initWithInputSize:(ECVIntegerSize)inSize pixelFormat:(OSType)inFormat outputSize:(ECVIntegerSize)outSize pixelFormat:(OSType)outFormat
{
	if((self = [super init])) {
		_inputPixelSize = inSize;
		_inputPixelFormat = inFormat;
		_outputPixelSize = outSize;
		_outputPixelFormat = outFormat;
		enum PixelFormat const inFormat2 = [[self class] AVPixelFormatWithOSType:inFormat];
		enum PixelFormat const outFormat2 = [[self class] AVPixelFormatWithOSType:outFormat];
		_converterCtx = sws_getContext(inSize.width, inSize.height, inFormat2, outSize.width, outSize.height, outFormat2, SWS_FAST_BILINEAR, NULL, NULL, NULL);
		_frame = avcodec_alloc_frame();
		_bufferSize = avpicture_get_size(outFormat2, outSize.width, outSize.height);
		uint8_t *const bytes = _bufferSize ? av_malloc(_bufferSize) : NULL;
		if(bytes) (void)avpicture_fill((AVPicture *)_frame, bytes, outFormat2, outSize.width, outSize.height);
		if(!_converterCtx || !_frame || !bytes) {
			[self release];
			return nil;
		}
	}
	return self;
}
- (ECVPixelBuffer *)convertedPixelBuffer:(ECVPixelBuffer *)buffer
{
	// TODO: Confirm that the buffer details match our input configuration.
	if(![buffer lockIfHasBytes]) return nil;
	[_buffer invalidate];
	[_buffer release];
	uint8_t const *const bytes = [buffer bytes];
	int const lineSize[4] = { [buffer bytesPerRow], 0, 0, 0 };
	sws_scale(_converterCtx, &bytes, lineSize, 0, [buffer pixelSize].height, _frame->data, _frame->linesize);
	[buffer unlock];
	_buffer = [[ECVPointerPixelBuffer alloc] initWithPixelSize:_outputPixelSize bytesPerRow:_frame->linesize[0] pixelFormat:_outputPixelFormat bytes:_frame->data[0] validRange:NSMakeRange(0, _bufferSize)];
	return [[_buffer retain] autorelease];
}

#pragma mark -ECVPixelBufferConverter(ECVDeprecated)

- (AVFrame *)currentFrame
{
	return _frame;
}

#pragma mark -NSObject

- (void)dealloc
{
	[_buffer invalidate];
	if(_converterCtx) sws_freeContext(_converterCtx);
	if(_frame) {
		if(_frame->data[0]) av_free(_frame->data[0]);
		av_free(_frame);
	}
	[_buffer release];
	[super dealloc];
}

@end
