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
#import "ECVMovieRecorder.h"

// Models
#import "ECVVideoStorage.h"
#import "ECVVideoFrame.h"

// Other Sources
#import "ECVAudioDevice.h"
#import "ECVAudioPipe.h"
#import "ECVDebug.h"

enum {
	ECVRecordThreadWait,
	ECVRecordThreadRun,
};

#define ECVCSOSetProperty(obj, prop, val) ECVOSStatus({ __typeof__(val) __val = (val); ICMCompressionSessionOptionsSetProperty(obj, kQTPropertyClass_ICMCompressionSessionOptions, (prop), sizeof(__val), &__val); }) // Be sure to cast val to the right type, since no implicit conversion occurs.

#define ECVFramesPerPacket 1
#define ECVChannelsPerFrame 2
#define ECVBitsPerByte 8
static AudioStreamBasicDescription const ECVAudioRecordingOutputDescription = {
	48000.0f,
	kAudioFormatLinearPCM,
	kLinearPCMFormatFlagIsFloat | kLinearPCMFormatFlagIsPacked,
	sizeof(Float32) * ECVChannelsPerFrame * ECVFramesPerPacket,
	ECVFramesPerPacket,
	sizeof(Float32) * ECVChannelsPerFrame,
	ECVChannelsPerFrame,
	sizeof(Float32) * ECVBitsPerByte,
	0,
};
#define ECVAudioBufferBytesSize (ECVAudioRecordingOutputDescription.mBytesPerPacket * 1000) // Should be more than enough to keep up with the incoming data.

@interface ECVMovieRecorder(Private)

- (void)_threaded_recordToMovie:(QTMovie *)movie;

- (void)_encodeFrame:(ECVVideoFrame *)frame;
- (void)_addEncodedFrame:(ICMEncodedFrameRef)frame;

- (void)_recordAudioBuffer;

@end

static OSStatus ECVEncodedFrameOutputCallback(ECVMovieRecorder *movieRecorder, ICMCompressionSessionRef session, OSStatus error, ICMEncodedFrameRef frame)
{
	[movieRecorder _addEncodedFrame:noErr == error ? frame : NULL];
	return noErr;
}

@implementation ECVMovieRecorder

#pragma mark -ECVMovieRecorder

- (id)initWithURL:(NSURL *)URL videoStorage:(ECVVideoStorage *)videoStorage audioDevice:(ECVAudioDevice *)audioDevice
{
	if((self = [super init])) {
		_URL = [URL copy];
		_videoStorage = [videoStorage retain];
		_audioDevice = [audioDevice retain];

		_videoCodec = kJPEGCodecType;
		_videoQuality = 0.5f;
		_outputSize = [_videoStorage originalSize];
		_cropRect = ECVUncroppedRect;
		_recordsDirectlyToDisk = YES;

		_volume = 1.0f;

		_lock = [[NSConditionLock alloc] initWithCondition:ECVRecordThreadWait];
	}
	return self;
}
@synthesize URL = _URL;
@synthesize videoStorage = _videoStorage;
@synthesize audioDevice = _audioDevice;

#pragma mark -

@synthesize videoCodec = _videoCodec;
@synthesize videoQuality = _videoQuality;
@synthesize outputSize = _outputSize;
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
@synthesize upconvertsFromMono = _upconvertsFromMono;
@synthesize recordsDirectlyToDisk = _recordsDirectlyToDisk;

#pragma mark -

@synthesize volume = _volume;

#pragma mark -

- (BOOL)startRecordingError:(out NSError **)outError
{
	QTMovie *const movie = [[self recordsDirectlyToDisk] ? [[QTMovie alloc] initToWritableFile:[[self URL] path] error:outError] : [[QTMovie alloc] initToWritableData:[NSMutableData data] error:outError] autorelease];
	if(!movie) return NO;

	_videoFrames = [[NSMutableArray alloc] init];

	ICMCompressionSessionOptionsRef options = NULL;
	ECVOSStatus(ICMCompressionSessionOptionsCreate(kCFAllocatorDefault, &options));
	ECVOSStatus(ICMCompressionSessionOptionsSetDurationsNeeded(options, true));
	NSTimeInterval frameRateInterval = 0.0f;
	if(QTGetTimeInterval([_videoStorage frameRate], &frameRateInterval)) ECVCSOSetProperty(options, kICMCompressionSessionOptionsPropertyID_ExpectedFrameRate, X2Fix(frameRateInterval));
	ECVCSOSetProperty(options, kICMCompressionSessionOptionsPropertyID_CPUTimeBudget, (UInt32)QTMakeTimeScaled([_videoStorage frameRate], ECVMicrosecondsPerSecond).timeValue);
	ECVCSOSetProperty(options, kICMCompressionSessionOptionsPropertyID_ScalingMode, (OSType)kICMScalingMode_StretchCleanAperture);
	ECVCSOSetProperty(options, kICMCompressionSessionOptionsPropertyID_Quality, (CodecQ)round(_videoQuality * codecMaxQuality));
	ECVCSOSetProperty(options, kICMCompressionSessionOptionsPropertyID_Depth, [_videoStorage pixelFormatType]);
	ICMEncodedFrameOutputRecord callback = {};
	callback.frameDataAllocator = kCFAllocatorDefault;
	callback.encodedFrameOutputCallback = (ICMEncodedFrameOutputCallback)ECVEncodedFrameOutputCallback;
	callback.encodedFrameOutputRefCon = self;
	ECVOSStatus(ICMCompressionSessionCreate(kCFAllocatorDefault, _outputSize.width, _outputSize.height, _videoCodec, [_videoStorage frameRate].timeScale, options, (CFDictionaryRef)[NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithUnsignedInteger:[_videoStorage pixelSize].width], kCVPixelBufferWidthKey,
		[NSNumber numberWithUnsignedInteger:[_videoStorage pixelSize].height], kCVPixelBufferHeightKey,
		[NSNumber numberWithUnsignedInt:[_videoStorage pixelFormatType]], kCVPixelBufferPixelFormatTypeKey,
		nil], &callback, &_compressionSession));
	ICMCompressionSessionOptionsRelease(options);

	ECVAudioStream *const inputStream = [[[_audioDevice streams] objectEnumerator] nextObject];
	if(inputStream) {
		_audioPipe = [[ECVAudioPipe alloc] initWithInputDescription:[inputStream basicDescription] outputDescription:ECVAudioRecordingOutputDescription upconvertFromMono:[self upconvertsFromMono]];
		[_audioPipe setDropsBuffers:NO];
	}

	[movie detachFromCurrentThread];
	[NSThread detachNewThreadSelector:@selector(_threaded_recordToMovie:) toTarget:self withObject:movie];
	return YES;
}
- (void)stopRecording
{
	[_lock lock];
	_stop = YES;
	[_lock unlockWithCondition:ECVRecordThreadRun];
}

#pragma mark -

- (void)addVideoFrame:(ECVVideoFrame *)frame
{
	[_lock lock];
	[_videoFrames insertObject:frame atIndex:0];
	[_lock unlockWithCondition:ECVRecordThreadRun];
}
- (void)addAudioBufferList:(AudioBufferList const *)bufferList
{
	[_lock lock];
	[_audioPipe receiveInputBufferList:bufferList];
	[_lock unlockWithCondition:ECVRecordThreadRun];
}

#pragma mark -ECVMovieRecorder(Private)

- (void)_threaded_recordToMovie:(QTMovie *)movie
{
	NSAutoreleasePool *const outerPool = [[NSAutoreleasePool alloc] init];
	[QTMovie enterQTKitOnThread];
	[movie attachToCurrentThread];

	Track const videoTrack = NewMovieTrack([movie quickTimeMovie], Long2Fix(_outputSize.width), Long2Fix(_outputSize.height), kNoVolume);
	Track const audioTrack = NewMovieTrack([movie quickTimeMovie], 0, 0, (short)round(_volume * kFullVolume));
	_videoMedia = NewTrackMedia(videoTrack, VideoMediaType, [_videoStorage frameRate].timeScale, NULL, 0);
	_audioMedia = NewTrackMedia(audioTrack, SoundMediaType, ECVAudioRecordingOutputDescription.mSampleRate, NULL, 0);
	ECVOSErr(BeginMediaEdits(_videoMedia));
	ECVOSErr(BeginMediaEdits(_audioMedia));
	ECVCVReturn(CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, ICMCompressionSessionGetPixelBufferPool(_compressionSession), &_pixelBuffer));
	if(_cleanAperture) CVBufferSetAttachment(_pixelBuffer, kCVImageBufferCleanApertureKey, _cleanAperture, kCVAttachmentMode_ShouldNotPropagate);

	ECVOSStatus(QTSoundDescriptionCreate((AudioStreamBasicDescription *)&ECVAudioRecordingOutputDescription, NULL, 0, NULL, 0, kQTSoundDescriptionKind_Movie_AnyVersion, &_audioDescriptionHandle));
	_audioBufferBytes = malloc(ECVAudioBufferBytesSize);

	BOOL stop = NO;
	while(!stop) {
		NSAutoreleasePool *const innerPool = [[NSAutoreleasePool alloc] init];

		[_lock lockWhenCondition:ECVRecordThreadRun];
		NSUInteger dropCount = [_videoStorage dropFramesFromArray:_videoFrames];
		ECVVideoFrame *const frame = [[[_videoFrames lastObject] retain] autorelease];
		if(frame) [_videoFrames removeLastObject];
		BOOL const moreToDo = [_videoFrames count] || [_audioPipe hasReadyBuffers];
		if(_stop && !moreToDo) stop = YES;
		[_lock unlockWithCondition:moreToDo ? ECVRecordThreadRun : ECVRecordThreadWait];

		while(dropCount--) [self _addEncodedFrame:NULL];
		[self _encodeFrame:frame];
		[self _recordAudioBuffer];

		[innerPool release];
	}

	[_lock lock];
	[_videoFrames release];
	_videoFrames = nil;
	[_audioPipe release];
	_audioPipe = nil;
	[_lock unlock];

	ECVOSStatus(ICMCompressionSessionCompleteFrames(_compressionSession, true, 0, 0));
	ECVOSErr(InsertMediaIntoTrack(GetMediaTrack(_videoMedia), 0, GetMediaDisplayStartTime(_videoMedia), GetMediaDisplayDuration(_videoMedia), fixed1));
	ECVOSErr(InsertMediaIntoTrack(GetMediaTrack(_audioMedia), 0, GetMediaDisplayStartTime(_audioMedia), GetMediaDisplayDuration(_audioMedia), fixed1));
	ECVOSErr(EndMediaEdits(_videoMedia));
	ECVOSErr(EndMediaEdits(_audioMedia));
	if([self recordsDirectlyToDisk]) [movie updateMovieFile];
	else [movie writeToFile:[[self URL] path] withAttributes:nil];

	if(_compressionSession) ICMCompressionSessionRelease(_compressionSession);
	if(_encodedFrame) ICMEncodedFrameRelease(_encodedFrame);
	_encodedFrame = NULL;
	CVPixelBufferRelease(_pixelBuffer);
	_pixelBuffer = NULL;

	if(_audioDescriptionHandle) DisposeHandle((Handle)_audioDescriptionHandle);
	if(_audioBufferBytes) free(_audioBufferBytes);
	_audioBufferBytes = NULL;

	DisposeTrackMedia(_videoMedia);
	DisposeTrackMedia(_audioMedia);
	DisposeMovieTrack(videoTrack);
	DisposeMovieTrack(audioTrack);
	_videoMedia = NULL;
	_audioMedia = NULL;

	[movie detachFromCurrentThread];
	[QTMovie exitQTKitOnThread];
	[outerPool release];
}

#pragma mark -

- (void)_encodeFrame:(ECVVideoFrame *)frame
{
	if(!frame) return;
	if(![frame lockIfHasBuffer]) return [self _addEncodedFrame:NULL];
	[frame copyToPixelBuffer:_pixelBuffer];
	[frame unlock];
	ECVOSStatus(ICMCompressionSessionEncodeFrame(_compressionSession, _pixelBuffer, 0, [_videoStorage frameRate].timeValue, kICMValidTime_DisplayDurationIsValid, NULL, NULL, NULL));
}
- (void)_addEncodedFrame:(ICMEncodedFrameRef)frame
{
	if(frame && frame != _encodedFrame) {
		ICMEncodedFrameRelease(_encodedFrame);
		_encodedFrame = ICMEncodedFrameRetain(frame);
	}
	if(_encodedFrame) ECVOSStatus(AddMediaSampleFromEncodedFrame(_videoMedia, _encodedFrame, NULL));
}

#pragma mark -

- (void)_recordAudioBuffer
{
	if(![_audioPipe hasReadyBuffers]) return;
	AudioBufferList outputBufferList = {1, {2, ECVAudioBufferBytesSize, _audioBufferBytes}};
	[_audioPipe requestOutputBufferList:&outputBufferList];
	ByteCount const size = outputBufferList.mBuffers[0].mDataByteSize;
	if(!size || !outputBufferList.mBuffers[0].mData) return;
	AddMediaSample2(_audioMedia, outputBufferList.mBuffers[0].mData, size, 1, 0, (SampleDescriptionHandle)_audioDescriptionHandle, size / ECVAudioRecordingOutputDescription.mBytesPerFrame, 0, NULL);
}

#pragma mark -NSObject

- (void)dealloc
{
	[_URL release];
	[_videoStorage release];
	[_audioDevice release];

	[_cleanAperture release];

	[_lock release];
	[super dealloc];
}

@end

#endif
