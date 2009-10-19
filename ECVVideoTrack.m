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

#if !__LP64__
@interface ECVVideoTrack(Private)

- (void)_addEncodedFrame:(ICMEncodedFrameRef)frame;

@end

static void ECVPixelBufferReleaseBytesCallback(id<ECVFrameReading> frame, const void *baseAddress)
{
	[frame markAsInvalid];
	[frame unlock];
	[frame release];
}
static OSStatus ECVEncodedFrameOutputCallback(ECVVideoTrack *videoTrack, ICMCompressionSessionRef session, OSStatus error, ICMEncodedFrameRef frame)
{
	[videoTrack _addEncodedFrame:noErr == error ? frame : NULL];
	return noErr;
}

@implementation ECVVideoTrack

#pragma mark +ECVVideoTrack

+ (id)videoTrackWithMovie:(QTMovie *)movie size:(NSSize)size cleanAperture:(CleanApertureImageDescriptionExtension)aperture codec:(CodecType)codec quality:(CGFloat)quality frameRate:(QTTime)frameRate
{
	NSParameterAssert([[[movie movieAttributes] objectForKey:QTMovieEditableAttribute] boolValue]);
	Track const track = NewMovieTrack([movie quickTimeMovie], X2Fix(roundf(size.width)), X2Fix(roundf(size.height)), kNoVolume);
	if(!track) return nil;
	Media const media = NewTrackMedia(track, VideoMediaType, frameRate.timeScale, NULL, 0);
	if(!media) {
		DisposeMovieTrack(track);
		return nil;
	}
	return [[[self alloc] initWithTrack:[QTTrack trackWithQuickTimeTrack:track error:NULL] size:size cleanAperture:aperture codec:codec quality:quality frameRate:frameRate] autorelease];
}

#pragma mark -ECVVideoTrack

- (id)initWithTrack:(QTTrack *)track size:(NSSize)size cleanAperture:(CleanApertureImageDescriptionExtension)aperture codec:(CodecType)codec quality:(CGFloat)quality frameRate:(QTTime)frameRate
{
	if((self = [super init])) {
		_track = [track retain];
		_frameDuration = frameRate.timeValue;

		ICMCompressionSessionOptionsRef options = NULL;
		ECVOSStatus(ICMCompressionSessionOptionsCreate(kCFAllocatorDefault, &options));
		Boolean const durationsNeeded = true;
		ECVOSStatus(ICMCompressionSessionOptionsSetProperty(options, kQTPropertyClass_ICMCompressionSessionOptions, kICMCompressionSessionOptionsPropertyID_DurationsNeeded, sizeof(durationsNeeded), &durationsNeeded));
		NSTimeInterval frameRateInterval = 0.0f;
		if(QTGetTimeInterval(frameRate, &frameRateInterval)) {
			Fixed const frameRateFixed = X2Fix(frameRateInterval);
			ECVOSStatus(ICMCompressionSessionOptionsSetProperty(options, kQTPropertyClass_ICMCompressionSessionOptions, kICMCompressionSessionOptionsPropertyID_ExpectedFrameRate, sizeof(frameRateFixed), &frameRateFixed));
		}
		UInt32 const frameRateMicroseconds = QTMakeTimeScaled(frameRate, ECVMicrosecondsPerSecond).timeValue;
		ECVOSStatus(ICMCompressionSessionOptionsSetProperty(options, kQTPropertyClass_ICMCompressionSessionOptions, kICMCompressionSessionOptionsPropertyID_CPUTimeBudget, sizeof(frameRateMicroseconds), &frameRateMicroseconds));
		OSType const scalingMode = kICMScalingMode_StretchCleanAperture;
		ECVOSStatus(ICMCompressionSessionOptionsSetProperty(options, kQTPropertyClass_ICMCompressionSessionOptions, kICMCompressionSessionOptionsPropertyID_ScalingMode, sizeof(scalingMode), &scalingMode));

		ICMEncodedFrameOutputRecord callback = {};
		callback.frameDataAllocator = kCFAllocatorDefault;
		callback.encodedFrameOutputCallback = (ICMEncodedFrameOutputCallback)ECVEncodedFrameOutputCallback;
		callback.encodedFrameOutputRefCon = self;
		ECVOSStatus(ICMCompressionSessionCreate(kCFAllocatorDefault, roundf(size.width), roundf(size.height), codec, frameRate.timeScale, options, NULL, &callback, &_compressionSession));

		ICMCompressionSessionOptionsRelease(options);

		_cleanApertureValue = [[NSDictionary alloc] initWithObjectsAndKeys:
			[NSNumber numberWithDouble:(double)aperture.horizOffN / aperture.horizOffD], kCVImageBufferCleanApertureHorizontalOffsetKey,
			[NSNumber numberWithDouble:(double)aperture.vertOffN / aperture.vertOffD], kCVImageBufferCleanApertureVerticalOffsetKey,
			[NSNumber numberWithDouble:(double)aperture.cleanApertureWidthN / aperture.cleanApertureWidthD], kCVImageBufferCleanApertureWidthKey,
			[NSNumber numberWithDouble:(double)aperture.cleanApertureHeightN / aperture.cleanApertureHeightD], kCVImageBufferCleanApertureHeightKey,
			nil];
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
		CVBufferSetAttachment(pixelBuffer, kCVImageBufferCleanApertureKey, _cleanApertureValue, kCVAttachmentMode_ShouldNotPropagate);
		ECVOSStatus(ICMCompressionSessionEncodeFrame(_compressionSession, pixelBuffer, 0, _frameDuration, kICMValidTime_DisplayDurationIsValid, NULL, NULL, NULL));
		CVPixelBufferRelease(pixelBuffer);
	} else {
		[frame unlock];
		[self _addEncodedFrame:NULL];
	}
}
- (void)finish
{
	ECVOSStatus(ICMCompressionSessionCompleteFrames(_compressionSession, true, 0, 0));
}

#pragma mark -ECVVideoTrack(Private)

- (void)_addEncodedFrame:(ICMEncodedFrameRef)frame
{
	if(frame && frame != _encodedFrame) {
		ICMEncodedFrameRelease(_encodedFrame);
		_encodedFrame = ICMEncodedFrameRetain(frame);
	}
	if(_encodedFrame) ECVOSStatus(AddMediaSampleFromEncodedFrame([[_track media] quickTimeMedia], _encodedFrame, NULL));
}

#pragma mark -NSObject

- (void)dealloc
{
	[_track release];
	[_cleanApertureValue release];
	ICMCompressionSessionRelease(_compressionSession);
	ICMEncodedFrameRelease(_encodedFrame);
	[super dealloc];
}

@end

#endif
