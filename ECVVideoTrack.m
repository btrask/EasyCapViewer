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
#if !__LP64__
#import "ECVVideoTrack.h"
#import <CoreVideo/CoreVideo.h>

// Models
#import "ECVVideoStorage.h"
#import "ECVVideoFrame.h"

// Other Sources
#import "ECVDebug.h"

#define ECVCSOSetProperty(obj, prop, val) ECVOSStatus({ __typeof__(val) __val = (val); ICMCompressionSessionOptionsSetProperty(obj, kQTPropertyClass_ICMCompressionSessionOptions, (prop), sizeof(__val), &__val); }) // Be sure to cast val to the right type, since no implicit conversion occurs.

@interface ECVBufferCopyOperation : NSOperation
{
	@private
	ECVVideoTrack *_track;
	ECVVideoFrame *_frame;
	CVPixelBufferRef _pixelBuffer;
	BOOL _success;
}

- (id)initWithTrack:(ECVVideoTrack *)track frame:(ECVVideoFrame *)frame pixelBuffer:(CVPixelBufferRef)pixelBuffer;
@property(readonly) CVPixelBufferRef pixelBuffer;
@property(readonly) BOOL success;

@end

@interface ECVVideoTrack(Private)

- (void)_bufferCopyOperationComplete:(ECVBufferCopyOperation *)op;
- (void)_addEncodedFrame:(ICMEncodedFrameRef)frame;

@end

static OSStatus ECVEncodedFrameOutputCallback(ECVVideoTrack *videoTrack, ICMCompressionSessionRef session, OSStatus error, ICMEncodedFrameRef frame)
{
	[videoTrack _addEncodedFrame:noErr == error ? frame : NULL];
	return noErr;
}

@implementation ECVVideoTrack

#pragma mark -ECVVideoTrack

- (id)initWithTrack:(QTTrack *)track videoStorage:(ECVVideoStorage *)storage size:(ECVPixelSize)size codec:(OSType)codec quality:(CGFloat)quality
{
	if((self = [super initWithTrack:track])) {
		_videoStorage = [storage retain];
		_operations = [[NSMutableArray alloc] init];

		ICMCompressionSessionOptionsRef options = NULL;
		ECVOSStatus(ICMCompressionSessionOptionsCreate(kCFAllocatorDefault, &options));
		ECVCSOSetProperty(options, kICMCompressionSessionOptionsPropertyID_DurationsNeeded, (Boolean)true);
		NSTimeInterval frameRateInterval = 0.0f;
		if(QTGetTimeInterval([_videoStorage frameRate], &frameRateInterval)) ECVCSOSetProperty(options, kICMCompressionSessionOptionsPropertyID_ExpectedFrameRate, X2Fix(frameRateInterval));
		ECVCSOSetProperty(options, kICMCompressionSessionOptionsPropertyID_CPUTimeBudget, (UInt32)QTMakeTimeScaled([_videoStorage frameRate], ECVMicrosecondsPerSecond).timeValue);
		ECVCSOSetProperty(options, kICMCompressionSessionOptionsPropertyID_ScalingMode, (OSType)kICMScalingMode_StretchCleanAperture);
		ECVCSOSetProperty(options, kICMCompressionSessionOptionsPropertyID_Quality, (CodecQ)round(quality * codecMaxQuality));
		ECVCSOSetProperty(options, kICMCompressionSessionOptionsPropertyID_Depth, [_videoStorage pixelFormatType]);

		ICMEncodedFrameOutputRecord callback = {};
		callback.frameDataAllocator = kCFAllocatorDefault;
		callback.encodedFrameOutputCallback = (ICMEncodedFrameOutputCallback)ECVEncodedFrameOutputCallback;
		callback.encodedFrameOutputRefCon = self;
		ECVOSStatus(ICMCompressionSessionCreate(kCFAllocatorDefault, size.width, size.height, codec, [_videoStorage frameRate].timeScale, options, (CFDictionaryRef)[NSDictionary dictionaryWithObjectsAndKeys:
			[NSNumber numberWithUnsignedInteger:[_videoStorage pixelSize].width], kCVPixelBufferWidthKey,
			[NSNumber numberWithUnsignedInteger:[_videoStorage pixelSize].height], kCVPixelBufferHeightKey,
			nil], &callback, &_compressionSession));

		ICMCompressionSessionOptionsRelease(options);
	}
	return self;
}

#pragma mark -

- (NSRect)cropRect
{
	return _cropRect;
}
- (void)setCropRect:(NSRect)aRect
{
	_cropRect = aRect;
	NSRect const c = aRect;
	ECVPixelSize const s1 = [_videoStorage pixelSize];
	ECVPixelSize const s2 = (ECVPixelSize){round(NSWidth(c) * s1.width), round(NSHeight(c) * s1.height)};
	[_cleanAperture release];
	_cleanAperture = [[NSDictionary alloc] initWithObjectsAndKeys:
		[NSNumber numberWithDouble:s2.width], kCVImageBufferCleanApertureWidthKey,
		[NSNumber numberWithDouble:s2.height], kCVImageBufferCleanApertureHeightKey,
		[NSNumber numberWithDouble:round(NSMinX(c) * s1.width - (s1.width - s2.width) / 2.0f)], kCVImageBufferCleanApertureHorizontalOffsetKey,
		[NSNumber numberWithDouble:round(NSMinY(c) * s1.height - (s1.height - s2.height) / 2.0f)], kCVImageBufferCleanApertureVerticalOffsetKey,
		nil];
}

#pragma mark -

- (void)addFrame:(ECVVideoFrame *)frame
{
	CVPixelBufferRef pixelBuffer = NULL;
	ECVCVReturn(CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, ICMCompressionSessionGetPixelBufferPool(_compressionSession), &pixelBuffer));
	if(!pixelBuffer) return [self _addEncodedFrame:NULL];
	ECVBufferCopyOperation *const op = [[[ECVBufferCopyOperation alloc] initWithTrack:self frame:frame pixelBuffer:pixelBuffer] autorelease];
	[_operations insertObject:op atIndex:0];
	[_videoStorage addFrameOperation:op];
	CVPixelBufferRelease(pixelBuffer);
}
- (void)finish
{
	[_operations removeAllObjects]; // FIXME: These frames just get dropped.
	ECVOSStatus(ICMCompressionSessionCompleteFrames(_compressionSession, true, 0, 0));
}

#pragma mark -ECVVideoTrack(Private)

- (void)_bufferCopyOperationComplete:(ECVBufferCopyOperation *)op
{
	if([_operations lastObject] != op) return;
	[_operations removeLastObject];
	if([op success]) {
		if(_cleanAperture) CVBufferSetAttachment([op pixelBuffer], kCVImageBufferCleanApertureKey, _cleanAperture, kCVAttachmentMode_ShouldNotPropagate);
		ECVOSStatus(ICMCompressionSessionEncodeFrame(_compressionSession, [op pixelBuffer], 0, [_videoStorage frameRate].timeValue, kICMValidTime_DisplayDurationIsValid, NULL, NULL, NULL));
	} else [self _addEncodedFrame:NULL];
	if([_operations count]) [self performSelector:_cmd withObject:[_operations lastObject] afterDelay:0.0f inModes:[NSArray arrayWithObject:(NSString *)kCFRunLoopCommonModes]];
}
- (void)_addEncodedFrame:(ICMEncodedFrameRef)frame
{
	if(frame && frame != _encodedFrame) {
		ICMEncodedFrameRelease(_encodedFrame);
		_encodedFrame = ICMEncodedFrameRetain(frame);
	}
	if(_encodedFrame) ECVOSStatus(AddMediaSampleFromEncodedFrame([[[self track] media] quickTimeMedia], _encodedFrame, NULL));
}

#pragma mark -NSObject

- (void)dealloc
{
	[_videoStorage release];
	[_operations release];
	[_cleanAperture release];
	ICMCompressionSessionRelease(_compressionSession);
	ICMEncodedFrameRelease(_encodedFrame);
	[super dealloc];
}

@end

@implementation QTMovie(ECVVideoTrackCreation)

- (ECVVideoTrack *)ECV_videoTrackVideoStorage:(ECVVideoStorage *)storage size:(ECVPixelSize)size codec:(OSType)codec quality:(CGFloat)quality
{
	NSParameterAssert([[[self movieAttributes] objectForKey:QTMovieEditableAttribute] boolValue]);
	Track const track = NewMovieTrack([self quickTimeMovie], Long2Fix(size.width), Long2Fix(size.height), kNoVolume);
	if(!track) return nil;
	Media const media = NewTrackMedia(track, VideoMediaType, [storage frameRate].timeScale, NULL, 0);
	if(!media) {
		DisposeMovieTrack(track);
		return nil;
	}
	return [[[ECVVideoTrack alloc] initWithTrack:[QTTrack trackWithQuickTimeTrack:track error:NULL] videoStorage:storage size:size codec:codec quality:quality] autorelease];
}

@end

@implementation ECVBufferCopyOperation

#pragma mark -ECVBufferCopyOperation

- (id)initWithTrack:(ECVVideoTrack *)track frame:(ECVVideoFrame *)frame pixelBuffer:(CVPixelBufferRef)pixelBuffer
{
	if((self = [super init])) {
		_track = [track retain];
		_frame = [frame retain];
		_pixelBuffer = CVPixelBufferRetain(pixelBuffer);
	}
	return self;
}
@synthesize pixelBuffer = _pixelBuffer;
@synthesize success = _success;

#pragma mark -NSOperation

- (void)main
{
	if([self isCancelled]) return;
	if([_frame lockIfHasBuffer]) {
		[_frame copyToPixelBuffer:_pixelBuffer];
		[_frame unlock];
		_success = YES;
	}
	[_track performSelectorOnMainThread:@selector(_bufferCopyOperationComplete:) withObject:self waitUntilDone:NO];
}

#pragma mark -NSObject

- (void)dealloc
{
	[_track release];
	[_frame release];
	CVPixelBufferRelease(_pixelBuffer);
	[super dealloc];
}

@end

#endif
