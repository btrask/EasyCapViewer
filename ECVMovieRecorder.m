/* Copyright (c) 2009, Ben Trask
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
#if !__LP64__
#import "ECVMovieRecorder.h"

// Models
#import "ECVVideoStorage.h"
#import "ECVVideoFrame.h"
#import "ECVFrameRateConverter.h"

// Other Sources
#import "ECVAudioDevice.h"
#import "ECVAudioPipe.h"
#import "ECVDebug.h"

@implementation ECVMovieRecordingOptions

#pragma mark -ECVMovieRecordingOptions

@synthesize URL = _URL;
@synthesize videoStorage = _videoStorage;
@synthesize audioDevice = _audioDevice;

#pragma mark -

@synthesize videoCodec = _videoCodec;
@synthesize videoQuality = _videoQuality;
@synthesize stretchOutput = _stretchOutput;
@synthesize outputSize = _outputSize;
@synthesize cropRect = _cropRect;
@synthesize upconvertsFromMono = _upconvertsFromMono;
@synthesize recordsToRAM = _recordsToRAM;
@synthesize frameRate = _frameRate;

#pragma mark -

- (NSDictionary *)cleanAperatureDictionary
{
	NSRect const c = [self cropRect];
	ECVIntegerSize const s1 = [_videoStorage pixelSize];
	ECVIntegerSize const s2 = (ECVIntegerSize){round(NSWidth(c) * s1.width), round(NSHeight(c) * s1.height)};
	return [NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithDouble:s2.width], kCVImageBufferCleanApertureWidthKey,
		[NSNumber numberWithDouble:s2.height], kCVImageBufferCleanApertureHeightKey,
		[NSNumber numberWithDouble:round(NSMinX(c) * s1.width - (s1.width - s2.width) / 2.0)], kCVImageBufferCleanApertureHorizontalOffsetKey,
		[NSNumber numberWithDouble:round(NSMinY(c) * s1.height - (s1.height - s2.height) / 2.0)], kCVImageBufferCleanApertureVerticalOffsetKey,
		nil];
}

#pragma mark -

@synthesize volume = _volume;

#pragma mark -NSObject

- (id)init
{
	if((self = [super init])) {
		_videoCodec = kJPEGCodecType;
		_videoQuality = 0.5f;
		_stretchOutput = YES;
		_outputSize = [_videoStorage originalSize];
		_cropRect = ECVUncroppedRect;

		_volume = 1.0f;
	}
	return self;
}
- (void)dealloc
{
	[_URL release];
	[_videoStorage release];
	[_audioDevice release];
	[super dealloc];
}

@end

enum {
	ECVRecordThreadWait,
	ECVRecordThreadRun,
	ECVRecordThreadFinished,
};

#define ECVCSOSetProperty(obj, prop, val) ECVOSStatus({ __typeof__(val) const __val = (val); ICMCompressionSessionOptionsSetProperty(obj, kQTPropertyClass_ICMCompressionSessionOptions, (prop), sizeof(__val), &__val); }) // Be sure to cast val to the right type, since no implicit conversion occurs.

#define ECVFramesPerPacket 1
#define ECVChannelsPerFrame 2
static AudioStreamBasicDescription const ECVAudioRecordingOutputDescription = {
	48000.0f,
	kAudioFormatLinearPCM,
	kLinearPCMFormatFlagIsFloat | kLinearPCMFormatFlagIsPacked,
	sizeof(Float32) * ECVChannelsPerFrame * ECVFramesPerPacket,
	ECVFramesPerPacket,
	sizeof(Float32) * ECVChannelsPerFrame,
	ECVChannelsPerFrame,
	sizeof(Float32) * CHAR_BIT,
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

- (id)initWithOptions:(ECVMovieRecordingOptions *)options error:(out NSError **)outError
{
	if(!(self = [super init])) return nil;

	QTMovie *const movie = [[options recordsToRAM] ? [[QTMovie alloc] initToWritableData:[NSMutableData data] error:outError] : [[QTMovie alloc] initToWritableFile:[[options URL] path] error:outError] autorelease];
	if(!movie) {
		[self release];
		return nil;
	}

	_lock = [[NSConditionLock alloc] initWithCondition:ECVRecordThreadWait];
	_writeURL = [options recordsToRAM] ? [[options URL] copy] : nil;
	_videoStorage = [[options videoStorage] retain];
	_videoFrames = [[NSMutableArray alloc] init];
	_frameRateConverter = [[ECVFrameRateConverter alloc] initWithSourceFrameRate:[_videoStorage frameRate] targetFrameRate:[options frameRate]];
	_outputSize = [options stretchOutput] ? [options outputSize] : [_videoStorage pixelSize];
	_volume = [options volume];

	ICMCompressionSessionOptionsRef ICMOpts = NULL;
	ECVOSStatus(ICMCompressionSessionOptionsCreate(kCFAllocatorDefault, &ICMOpts));
	ECVOSStatus(ICMCompressionSessionOptionsSetDurationsNeeded(ICMOpts, true));
	NSTimeInterval frameRateInterval = 0.0;
	if(QTGetTimeInterval([_frameRateConverter targetFrameRate], &frameRateInterval)) ECVCSOSetProperty(ICMOpts, kICMCompressionSessionOptionsPropertyID_ExpectedFrameRate, X2Fix(1.0 / frameRateInterval));
	ECVCSOSetProperty(ICMOpts, kICMCompressionSessionOptionsPropertyID_CPUTimeBudget, (UInt32)QTMakeTimeScaled([_frameRateConverter targetFrameRate], ECVMicrosecondsPerSecond).timeValue);
	ECVCSOSetProperty(ICMOpts, kICMCompressionSessionOptionsPropertyID_ScalingMode, (OSType)kICMScalingMode_StretchCleanAperture);
	ECVCSOSetProperty(ICMOpts, kICMCompressionSessionOptionsPropertyID_Quality, (CodecQ)round([options videoQuality] * codecMaxQuality));
	ECVCSOSetProperty(ICMOpts, kICMCompressionSessionOptionsPropertyID_Depth, [_videoStorage pixelFormatType]);
	ICMEncodedFrameOutputRecord callback = {};
	callback.frameDataAllocator = kCFAllocatorDefault;
	callback.encodedFrameOutputCallback = (ICMEncodedFrameOutputCallback)ECVEncodedFrameOutputCallback;
	callback.encodedFrameOutputRefCon = self;
	ECVOSStatus(ICMCompressionSessionCreate(kCFAllocatorDefault, _outputSize.width, _outputSize.height, [options videoCodec], [_frameRateConverter targetFrameRate].timeScale, ICMOpts, (CFDictionaryRef)[NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithUnsignedInteger:[_videoStorage pixelSize].width], kCVPixelBufferWidthKey,
		[NSNumber numberWithUnsignedInteger:[_videoStorage pixelSize].height], kCVPixelBufferHeightKey,
		[NSNumber numberWithUnsignedInt:[_videoStorage pixelFormatType]], kCVPixelBufferPixelFormatTypeKey,
		[NSDictionary dictionaryWithObjectsAndKeys:
			[options cleanAperatureDictionary], kCVImageBufferCleanApertureKey,
			nil], kCVBufferNonPropagatedAttachmentsKey,
		nil], &callback, &_compressionSession));
	ICMCompressionSessionOptionsRelease(ICMOpts);

	ECVAudioStream *const inputStream = [[[[options audioDevice] streams] objectEnumerator] nextObject];
	if(inputStream) {
		_audioPipe = [[ECVAudioPipe alloc] initWithInputDescription:[inputStream basicDescription] outputDescription:ECVAudioRecordingOutputDescription upconvertFromMono:[options upconvertsFromMono]];
		[_audioPipe setDropsBuffers:NO];
	}

	[movie detachFromCurrentThread];
	[NSThread detachNewThreadSelector:@selector(_threaded_recordToMovie:) toTarget:self withObject:movie];

	return self;
}

#pragma mark -

- (void)addVideoFrame:(ECVVideoFrame *)frame
{
	[_lock lock];
	if(ECVRecordThreadFinished == [_lock condition]) return [_lock unlock];
	NSUInteger const count = [_frameRateConverter nextFrameRepeatCount];
	if(!count) return [_lock unlock];
	NSUInteger i;
	for(i = 0; i < count; ++i) [_videoFrames insertObject:frame atIndex:0];
	[_lock unlockWithCondition:ECVRecordThreadRun];
}
- (void)addAudioBufferList:(AudioBufferList const *)bufferList
{
	[_lock lock];
	if(ECVRecordThreadFinished == [_lock condition]) return [_lock unlock];
	[_audioPipe receiveInputBufferList:bufferList];
	[_lock unlockWithCondition:ECVRecordThreadRun];
}

#pragma mark -

- (void)stopRecording
{
	[_lock lock];
	_stop = YES;
	[_lock unlockWithCondition:ECVRecordThreadRun];
	[_lock lockWhenCondition:ECVRecordThreadFinished];
	[_lock unlock];
}

#pragma mark -ECVMovieRecorder(Private)

- (void)_threaded_recordToMovie:(QTMovie *)movie
{
	NSAutoreleasePool *const outerPool = [[NSAutoreleasePool alloc] init];
	[QTMovie enterQTKitOnThread];
	[movie attachToCurrentThread];

	Track const videoTrack = NewMovieTrack([movie quickTimeMovie], Long2Fix(_outputSize.width), Long2Fix(_outputSize.height), kNoVolume);
	Track const audioTrack = NewMovieTrack([movie quickTimeMovie], 0, 0, (short)round(_volume * kFullVolume));
	_videoMedia = NewTrackMedia(videoTrack, VideoMediaType, [_frameRateConverter targetFrameRate].timeScale, NULL, 0);
	_audioMedia = NewTrackMedia(audioTrack, SoundMediaType, ECVAudioRecordingOutputDescription.mSampleRate, NULL, 0);
	ECVOSErr(BeginMediaEdits(_videoMedia));
	ECVOSErr(BeginMediaEdits(_audioMedia));

	ECVCVReturn(CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, ICMCompressionSessionGetPixelBufferPool(_compressionSession), &_pixelBuffer));

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

	ECVOSStatus(ICMCompressionSessionCompleteFrames(_compressionSession, true, 0, 0));
	ECVOSErr(InsertMediaIntoTrack(GetMediaTrack(_videoMedia), 0, GetMediaDisplayStartTime(_videoMedia), GetMediaDisplayDuration(_videoMedia), fixed1));
	ECVOSErr(InsertMediaIntoTrack(GetMediaTrack(_audioMedia), 0, GetMediaDisplayStartTime(_audioMedia), GetMediaDisplayDuration(_audioMedia), fixed1));
	ECVOSErr(EndMediaEdits(_videoMedia));
	ECVOSErr(EndMediaEdits(_audioMedia));
	if(_writeURL) [movie writeToFile:[_writeURL path] withAttributes:nil];
	else [movie updateMovieFile];

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

	[_lock lock];
	[_lock unlockWithCondition:ECVRecordThreadFinished];

	[outerPool release];
}

#pragma mark -

- (void)_encodeFrame:(ECVVideoFrame *)frame
{
	if(!frame) return;
	if(![frame lockIfHasBuffer]) return [self _addEncodedFrame:NULL];
	[frame copyToPixelBuffer:_pixelBuffer];
	[frame unlock];
	ECVOSStatus(ICMCompressionSessionEncodeFrame(_compressionSession, _pixelBuffer, 0, [_frameRateConverter targetFrameRate].timeValue, kICMValidTime_DisplayDurationIsValid, NULL, NULL, NULL));
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
	[_lock release];
	[_writeURL release];
	[_videoStorage release];
	[_videoFrames release];
	[_frameRateConverter release];
	[_audioPipe release];
	[super dealloc];
}

@end

#endif
