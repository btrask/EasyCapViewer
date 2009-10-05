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
#import "ECVVideoTrack.h"
#import <CoreVideo/CoreVideo.h>

// Other Sources
#import "ECVDebug.h"
#import "ECVFrameReading.h"

@interface ECVVideoTrack(Private)

- (void)_addEncodedFrame:(ICMEncodedFrameRef)frame;

@end

static void ECVPixelBufferReleaseBytesCallback(id<ECVFrameReading> frame, const void *baseAddress)
{
	[frame unlock];
	[frame release];
}
static OSStatus ECVEncodedFrameOutputCallback(ECVVideoTrack *videoTrack, ICMCompressionSessionRef session, OSStatus error, ICMEncodedFrameRef frame)
{
	if(noErr == error) [videoTrack _addEncodedFrame:frame];
	return noErr;
}

@implementation ECVVideoTrack

#pragma mark +ECVVideoTrack

+ (id)videoTrackWithMovie:(QTMovie *)movie size:(NSSize)size codec:(CodecType)codec quality:(CGFloat)quality frameRate:(QTTime)frameRate
{
	NSParameterAssert([[[movie movieAttributes] objectForKey:QTMovieEditableAttribute] boolValue]);
	Track const track = NewMovieTrack([movie quickTimeMovie], FixRatio(roundf(size.width), 1), FixRatio(roundf(size.height), 1), kNoVolume);
	if(!track) return nil;
	Media const media = NewTrackMedia(track, VideoMediaType, frameRate.timeScale, NULL, 0);
	if(!media) {
		DisposeMovieTrack(track);
		return nil;
	}
	return [[[self alloc] initWithTrack:[QTTrack trackWithQuickTimeTrack:track error:NULL]  size:size codec:codec quality:quality frameRate:frameRate] autorelease];
}

#pragma mark -ECVVideoTrack

- (id)initWithTrack:(QTTrack *)track size:(NSSize)size codec:(CodecType)codec quality:(CGFloat)quality frameRate:(QTTime)frameRate
{
	if((self = [super init])) {
		_track = [track retain];
		ICMEncodedFrameOutputRecord callback = {};
		callback.frameDataAllocator = kCFAllocatorDefault;
		callback.encodedFrameOutputCallback = (ICMEncodedFrameOutputCallback)ECVEncodedFrameOutputCallback;
		callback.encodedFrameOutputRefCon = self;
		ECVOSStatus(ICMCompressionSessionCreate(kCFAllocatorDefault, roundf(size.width), roundf(size.height), codec, frameRate.timeScale, NULL, NULL, &callback, &_compressionSession));
		_timeValue = frameRate.timeValue;
	}
	return self;
}
@synthesize track = _track;

#pragma mark -

- (void)addFrame:(id<ECVFrameReading>)frame
{
	[frame lock];
	if(frame.isValid) {
		[frame retain];
		ECVPixelSize const size = frame.pixelSize;
		CVPixelBufferRef pixelBuffer = NULL;
		ECVCVReturn(CVPixelBufferCreateWithBytes(kCFAllocatorDefault, size.width, size.height, frame.pixelFormatType, frame.bufferBytes, frame.bytesPerRow, (CVPixelBufferReleaseBytesCallback)ECVPixelBufferReleaseBytesCallback, frame, NULL, &pixelBuffer));
		ECVOSStatus(ICMCompressionSessionEncodeFrame(_compressionSession, pixelBuffer, 0, _timeValue, kICMValidTime_DisplayDurationIsValid, NULL, NULL, NULL));
		CVPixelBufferRelease(pixelBuffer);
	} else {
		[frame unlock];
		[self _addEncodedFrame:_encodedFrame];
	}
}

#pragma mark -ECVVideoTrack(Private)

- (void)_addEncodedFrame:(ICMEncodedFrameRef)frame
{
	ImageDescriptionHandle desc = NULL;
	ECVOSStatus(ICMEncodedFrameGetImageDescription(frame, &desc));
	ECVOSStatus(AddMediaSample2([[_track media] quickTimeMedia], ICMEncodedFrameGetDataPtr(frame), ICMEncodedFrameGetDataSize(frame), _timeValue, 0, (SampleDescriptionHandle)desc, 1, ICMEncodedFrameGetMediaSampleFlags(frame), NULL));
	if(frame == _encodedFrame) return;
	ICMEncodedFrameRelease(_encodedFrame);
	_encodedFrame = ICMEncodedFrameRetain(frame);
}

#pragma mark -NSObject

- (void)dealloc
{
	[_track release];
	ICMCompressionSessionRelease(_compressionSession);
	ICMEncodedFrameRelease(_encodedFrame);
	[super dealloc];
}

@end
