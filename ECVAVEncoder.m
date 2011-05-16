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
#import "ECVAVEncoder.h"

// Models/Storages
#import "ECVStorage.h"

// Models/Storages/Video
#import "ECVVideoStorage.h"

// Models
#import "ECVPixelBufferConverter.h"

// Other Sources
#import "ECVDebug.h"

#define ECV_VIDEO_BUFFER_SIZE 200000 // Arbitrary, but recommended by libavformat.

@interface ECVAVEncoder(Private)

- (AVStream *)_addStreamForStreamEncoder:(ECVStreamEncoder *)encoder;

- (AVFormatContext *)_formatContext;
- (void)_lockFormatContext;
- (NSData *)_unlockFormatContext;

@end

@interface ECVVideoStreamEncoder(Private)

- (NSData *)_encodedData;

@end

@implementation ECVAVEncoder

#pragma mark +ECVAVEncoder

+ (void)initialize
{
	if([ECVAVEncoder class] != self) return;
	av_register_all();
}

#pragma mark -ECVAVEncoder

- (id)initWithStorages:(NSArray *)storages
{
	if((self = [super init])) {
		if(!(_formatCtx = avformat_alloc_context())) goto bail;
		if(!(_formatCtx->oformat = av_guess_format("asf", NULL, NULL))) goto bail;
		_encoderByStorage = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
		[storages makeObjectsPerformSelector:@selector(streamEncoderForEncoder:) withObject:self];

		(void)av_set_parameters(_formatCtx, NULL);
		unsigned int i;
		for(i = 0; i < _formatCtx->nb_streams; ++i) {
			AVCodecContext *const codecCtx = _formatCtx->streams[i]->codec;
			AVCodec *const codec = avcodec_find_encoder(codecCtx->codec_id);
			if(!codec || avcodec_open(codecCtx, codec) < 0) goto bail;
		}
		[self _lockFormatContext];
		if(av_write_header(_formatCtx) != 0) {
			(void)[self _unlockFormatContext];
			goto bail;
		}
		_header = [[self _unlockFormatContext] copy];
	}
	return self;
bail:
	[self release];
	return nil;
}

#pragma mark -

- (NSString *)MIMEType
{
	char const *const type = _formatCtx->oformat->mime_type;
	return type ? [NSString stringWithUTF8String:type] : @"application/x-octet-stream";
}
- (NSData *)header
{
	return [[_header retain] autorelease];
}
- (NSData *)encodedDataWithVideoFrame:(ECVVideoFrame *)frame
{
	return [(ECVVideoStreamEncoder *)CFDictionaryGetValue(_encoderByStorage, [frame videoStorage]) encodedDataWithVideoFrame:frame];
}

#pragma mark -ECVAVEncoder(Private)

- (AVStream *)_addStreamForStreamEncoder:(ECVStreamEncoder *)encoder
{
	AVStream *const stream = av_new_stream(_formatCtx, 0);
	AVCodecContext *const codecCtx = stream->codec;
	if(_formatCtx->oformat->flags & AVFMT_GLOBALHEADER) codecCtx->flags |= CODEC_FLAG_GLOBAL_HEADER;
	CFDictionarySetValue(_encoderByStorage, [encoder storage], encoder);
	return stream;
}

#pragma mark -

- (AVFormatContext *)_formatContext
{
	return _formatCtx;
}
- (void)_lockFormatContext
{
	if(url_open_dyn_buf(&_formatCtx->pb) != 0) ECVAssertNotReached(@"Lock format context failed.");
}
- (NSData *)_unlockFormatContext
{
	uint8_t *bytes = NULL;
	int const length = url_close_dyn_buf(_formatCtx->pb, &bytes);
	CFAllocatorContext allocator = {
		.version = 0,
		.allocate = (CFAllocatorAllocateCallBack)av_malloc, // Unused but necessary anyway.
		.deallocate = (CFAllocatorDeallocateCallBack)av_free,
	};
	CFAllocatorRef const deallocator = CFAllocatorCreate(kCFAllocatorUseContext, &allocator);
	NSData *const data = [(NSData *)CFDataCreateWithBytesNoCopy(kCFAllocatorDefault, bytes, length, deallocator) autorelease];
	CFRelease(deallocator);
	return data;
}

#pragma mark -NSObject

- (void)dealloc
{
	if(_formatCtx) {
		av_write_trailer(_formatCtx);
		unsigned int i;
		for(i = 0; i < _formatCtx->nb_streams; ++i) {
			avcodec_close(_formatCtx->streams[i]->codec);
			av_freep(_formatCtx->streams[i]->codec);
			av_freep(_formatCtx->streams[i]);
		}
		av_free(_formatCtx);
	}
	if(_encoderByStorage) CFRelease(_encoderByStorage);
	[_header release];
	[super dealloc];
}

@end

@implementation ECVStreamEncoder

#pragma mark -ECVStreamEncoder

- (id)initWithEncoder:(ECVAVEncoder *)encoder storage:(id)storage
{
	if((self = [super init])) {
		_encoder = encoder;
		_storage = [storage retain];
		_formatCtx = [_encoder _formatContext];
		_stream = [_encoder _addStreamForStreamEncoder:self];
	}
	return self;
}

#pragma mark -

- (ECVAVEncoder *)encoder
{
	return _encoder;
}
- (id)storage
{
	return _storage;
}

#pragma mark -

- (AVFormatContext *)formatContext
{
	return _formatCtx;
}
- (AVStream *)stream
{
	return _stream;
}
- (AVCodecContext *)codecContext
{
	return _stream->codec;
}
- (AVCodec *)codec
{
	return _stream->codec->codec;
}

#pragma mark -

- (void)lockFormatContext
{
	[_encoder _lockFormatContext];
}
- (NSData *)unlockFormatContext
{
	return [_encoder _unlockFormatContext];
}

#pragma mark -NSObject

- (void)dealloc
{
	// TODO: Remove the stream from the format context. (Important in case an initializer fails.)
	[_storage release];
	[super dealloc];
}

@end

@implementation ECVVideoStreamEncoder

#pragma mark -ECVVideoStreamEncoder

- (NSData *)encodedDataWithVideoFrame:(ECVVideoFrame *)frame
{
	if(![_converter convertedPixelBuffer:frame]) return nil;

	if(1 == _frameRepeatCount) return [self _encodedData];

	NSMutableData *const data = [NSMutableData data];
	NSUInteger i = _frameRepeatCount;
	while(i--) [data appendData:[self _encodedData]];
	return data;
}

#pragma mark -ECVVideoStreamEncoder(Private)

- (NSData *)_encodedData
{
	AVFrame *const frame = [_converter currentFrame];
	[self lockFormatContext];
	AVPacket pkt;
	av_init_packet(&pkt);
	pkt.stream_index = [self stream]->index;
	if(AVFMT_RAWPICTURE & [self formatContext]->oformat->flags) {
		pkt.data = (uint8_t *)frame;
		pkt.size = sizeof(AVPicture);
		pkt.flags |= AV_PKT_FLAG_KEY;
		if(av_interleaved_write_frame([self formatContext], &pkt) == 0) return [self unlockFormatContext];
	} else {
		frame->quality = 1;
		int size = avcodec_encode_video([self codecContext], _convertedBuffer, ECV_VIDEO_BUFFER_SIZE, frame);
		if(size > 0) {
			AVFrame *const codedFrame = [self codecContext]->coded_frame;
			if((uint64_t)codedFrame->pts != AV_NOPTS_VALUE) pkt.pts= av_rescale_q(codedFrame->pts, [self codecContext]->time_base, [self stream]->time_base);
			if(codedFrame->key_frame) pkt.flags |= AV_PKT_FLAG_KEY;
			pkt.data = _convertedBuffer;
			pkt.size = size;
			if(av_interleaved_write_frame([self formatContext], &pkt) == 0) return [self unlockFormatContext];
		}
	}
	(void)[self unlockFormatContext];
	return nil;
}

#pragma mark -ECVStreamEncoder

- (id)initWithEncoder:(ECVAVEncoder *)encoder storage:(id)storage
{
	if((self = [super initWithEncoder:encoder storage:storage])) {
		ECVVideoStorage *const vs = storage;
		AVStream *const stream = [self stream];
		AVCodecContext *const codecCtx = [self codecContext];
		OSType const targetPixelFormat = kCVPixelFormatType_420YpCbCr8Planar;

		codecCtx->codec_type = AVMEDIA_TYPE_VIDEO;
		codecCtx->codec_id = CODEC_ID_MPEG1VIDEO;
		codecCtx->bit_rate = 400000; // TODO: Adjustable?
		codecCtx->gop_size = 12;
		codecCtx->pix_fmt = [ECVPixelBufferConverter AVPixelFormatWithOSType:targetPixelFormat];

		ECVRational const ratio = [vs pixelAspectRatio];
		ECVIntegerSize const inputSize = [vs pixelSize];
		ECVIntegerSize const outputSize = (ECVIntegerSize){round((double)inputSize.width / ratio.numer * ratio.denom), inputSize.height};
		codecCtx->width = outputSize.width;
		codecCtx->height = outputSize.height;

		QTTime rate = [vs frameRate];
		_frameRepeatCount = 1;
		if(QTTimeCompare(rate, QTMakeTime(1001, 15000)) == NSOrderedSame) { // FIXME: We should find a list of supported frame rates and convert automatically or something.
			rate = QTMakeTime(1001, 30000);
			_frameRepeatCount = 2;
		}
		codecCtx->time_base = (AVRational){
			.num = rate.timeValue,
			.den = rate.timeScale,
		};

		_converter = [[ECVPixelBufferConverter alloc] initWithInputSize:inputSize pixelFormat:[vs pixelFormat] outputSize:outputSize pixelFormat:targetPixelFormat];
		if(!(_convertedBuffer = av_malloc(ECV_VIDEO_BUFFER_SIZE))) {
			[self release];
			return nil;
		}
	}
	return self;
}

#pragma mark -NSObject

- (void)dealloc
{
	[_converter release];
	[super dealloc];
}

@end

@implementation ECVVideoStorage(ECVEncoding)

- (ECVStreamEncoder *)streamEncoderForEncoder:(ECVAVEncoder *)encoder
{
	return [[[ECVVideoStreamEncoder alloc] initWithEncoder:encoder storage:self] autorelease];
}

@end
