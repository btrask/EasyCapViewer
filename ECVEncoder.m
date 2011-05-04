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
#import "ECVEncoder.h"

// Models/Storages
#import "ECVStorage.h"

// Models/Storages/Video
#import "ECVVideoStorage.h"

// Models/Video
#import "ECVVideoFrame.h"

// Other Sources
#import "ECVDebug.h"

static enum PixelFormat ECVCodecIDFromPixelFormat(OSType pixelFormat)
{
	switch(pixelFormat) {
		case kCVPixelFormatType_422YpCbCr8: return PIX_FMT_UYVY422;
	}
	ECVCAssertNotReached(@"Unsupported pixel format.");
	return PIX_FMT_NONE;
}

@interface ECVStorage(ECVEncoding)

- (void)_addToEncoder:(ECVEncoder *)encoder;

@end

@interface ECVEncoder(Private)

- (AVStream *)_addStreamForStorage:(ECVStorage *)storage;

- (BOOL)_lockFormatContext;
- (NSData *)_unlockFormatContext;

@end

@implementation ECVEncoder

#pragma mark +ECVEncoder

+ (void)initialize
{
	if([ECVEncoder class] != self) return;
	av_register_all();
}

#pragma mark -ECVEncoder

- (id)initWithStorages:(NSArray *)storages
{
	if((self = [super init])) {
		if(!(_formatCtx = avformat_alloc_context())) goto bail;
		if(!(_formatCtx->oformat = av_guess_format("asf", NULL, NULL))) goto bail;
		_streamByStorage = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, NULL);
		[storages makeObjectsPerformSelector:@selector(_addToEncoder:) withObject:self];

		(void)av_set_parameters(_formatCtx, NULL);
		unsigned int i;
		for(i = 0; i < _formatCtx->nb_streams; ++i) {
			AVCodecContext *const codecCtx = _formatCtx->streams[i]->codec;
			AVCodec *const codec = avcodec_find_encoder(codecCtx->codec_id);
			if(!codec || avcodec_open(codecCtx, codec) < 0) goto bail;
		}
		if(![self _lockFormatContext]) goto bail;
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

- (NSData *)header
{
	return [[_header retain] autorelease];
}
- (NSData *)encodedDataWithVideoFrame:(ECVVideoFrame *)frame
{
	if(![self _lockFormatContext]) return nil;
	BOOL written = NO;
	if([frame lockIfHasBytes]) {
		AVStream *const stream = (AVStream *)CFDictionaryGetValue(_streamByStorage, [frame videoStorage]);
		AVPacket pkt;
		av_init_packet(&pkt);
		pkt.dts = _frameIndex;
		pkt.pts = AV_NOPTS_VALUE;
		pkt.flags |= AV_PKT_FLAG_KEY;
		pkt.stream_index = stream->index;
		pkt.data = (uint8_t *)[frame bytes];
		pkt.size = (int)[frame validRange].length;
		written = av_interleaved_write_frame(_formatCtx, &pkt) == 0;
		[frame unlock];
	}
	_frameIndex++;
	NSData *const data = [self _unlockFormatContext];
	return written ? data : nil;
}

#pragma mark -ECVEncoder(Private)

- (AVStream *)_addStreamForStorage:(ECVStorage *)storage
{
	AVStream *const stream = av_new_stream(_formatCtx, 0);
	AVCodecContext *const codecCtx = stream->codec;
	if(_formatCtx->oformat->flags & AVFMT_GLOBALHEADER) codecCtx->flags |= CODEC_FLAG_GLOBAL_HEADER;
	CFDictionarySetValue(_streamByStorage, storage, stream);
	return stream;
}

#pragma mark -

- (BOOL)_lockFormatContext
{
	return url_open_dyn_buf(&_formatCtx->pb) == 0;
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
	if(_streamByStorage) CFRelease(_streamByStorage);
	[_header release];
	[super dealloc];
}

@end

@implementation ECVVideoStorage(ECVEncoding)

- (void)_addToEncoder:(ECVEncoder *)encoder
{
	AVStream *const stream = [encoder _addStreamForStorage:self];
	AVCodecContext *const codecCtx = stream->codec;
	codecCtx->codec_type = AVMEDIA_TYPE_VIDEO;
	codecCtx->codec_id = CODEC_ID_RAWVIDEO;
	codecCtx->bit_rate = 400000; // TODO: Adjustable?

	ECVIntegerSize const size = [self pixelSize];
	codecCtx->width = size.width;
	codecCtx->height = size.height;

	QTTime const rate = [self frameRate];
	codecCtx->time_base = (AVRational){
		.num = rate.timeValue,
		.den = rate.timeScale,
	};

	ECVRational const ratio = [self pixelAspectRatio];
	stream->sample_aspect_ratio = codecCtx->sample_aspect_ratio = (AVRational){
		.num = ratio.numer,
		.den = ratio.denom,
	};

	codecCtx->gop_size = 12;
	codecCtx->pix_fmt = ECVCodecIDFromPixelFormat([self pixelFormat]);
}

@end
