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
#if defined(ECV_ENABLE_AUDIO)
#import "ECVAudioDevice.h"
#import "ECVAudioPipe.h"
#endif
#import "ECVDebug.h"

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

#define ECVCSOSetProperty(obj, prop, val) \
	ECVOSStatus({ \
		__typeof__(val) const __val = (val); \
		ICMCompressionSessionOptionsSetProperty( \
			obj, \
			kQTPropertyClass_ICMCompressionSessionOptions, \
			kICMCompressionSessionOptionsPropertyID_##prop, \
			sizeof(__val), \
			&__val); \
	}) // Be sure to cast val to the right type, since no implicit conversion occurs.

@protocol ECVCompressionDelegate

- (void)addEncodedFrame:(ICMEncodedFrameRef const)frame;

@end

static OSStatus ECVCompressionDelegateHandler(id<ECVCompressionDelegate> const movieRecorder, ICMCompressionSessionRef const session, OSStatus const error, ICMEncodedFrameRef const frame)
{
	[movieRecorder addEncodedFrame:noErr == error ? frame : NULL];
	return noErr;
}

@implementation ECVMovieRecordingOptions

#pragma mark -ECVMovieRecordingOptions

@synthesize URL = _URL;
@synthesize videoStorage = _videoStorage;
@synthesize audioInput = _audioInput;

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

#pragma mark -ECVMovieRecordingOptions(Private)

- (ECVFrameRateConverter *)_frameRateConverter
{
	return [[[ECVFrameRateConverter alloc] initWithSourceFrameRate:[_videoStorage frameRate] targetFrameRate:_frameRate] autorelease];
}
- (ECVIntegerSize)_outputSize
{
	return _stretchOutput ? _outputSize : [_videoStorage pixelSize];
}
- (ICMCompressionSessionRef)_compressionSessionWithDelegate:(id<ECVCompressionDelegate> const)delegate
{
	ICMCompressionSessionOptionsRef opts = NULL;
	ECVOSStatus(ICMCompressionSessionOptionsCreate(kCFAllocatorDefault, &opts));

	ECVCSOSetProperty(opts, DurationsNeeded, (Boolean)true);
	NSTimeInterval frameRateInterval = 0.0;
	if(QTGetTimeInterval(_frameRate, &frameRateInterval)) ECVCSOSetProperty(opts, ExpectedFrameRate, X2Fix(1.0 / frameRateInterval));
	ECVCSOSetProperty(opts, CPUTimeBudget, (UInt32)QTMakeTimeScaled(_frameRate, ECVMicrosecondsPerSecond).timeValue);
	ECVCSOSetProperty(opts, ScalingMode, (OSType)kICMScalingMode_StretchCleanAperture);
	ECVCSOSetProperty(opts, Quality, (CodecQ)round([self videoQuality] * codecMaxQuality));
	ECVCSOSetProperty(opts, Depth, [_videoStorage pixelFormat]);
	ICMEncodedFrameOutputRecord callback = {};
	callback.frameDataAllocator = kCFAllocatorDefault;
	callback.encodedFrameOutputCallback = (ICMEncodedFrameOutputCallback)ECVCompressionDelegateHandler;
	callback.encodedFrameOutputRefCon = delegate;

	ICMCompressionSessionRef compressionSession = NULL;
	ECVOSStatus(ICMCompressionSessionCreate(kCFAllocatorDefault, _outputSize.width, _outputSize.height, [self videoCodec], _frameRate.timeScale, opts, (CFDictionaryRef)[NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithUnsignedInteger:[_videoStorage pixelSize].width], kCVPixelBufferWidthKey,
		[NSNumber numberWithUnsignedInteger:[_videoStorage pixelSize].height], kCVPixelBufferHeightKey,
		[NSNumber numberWithUnsignedInt:[_videoStorage pixelFormat]], kCVPixelBufferPixelFormatTypeKey,
		[NSDictionary dictionaryWithObjectsAndKeys:
			[self cleanAperatureDictionary], kCVImageBufferCleanApertureKey,
			nil], kCVBufferNonPropagatedAttachmentsKey,
		nil], &callback, &compressionSession));

	ICMCompressionSessionOptionsRelease(opts);
	return compressionSession;
}
- (ECVAudioPipe *)_audioPipe
{
	ECVAudioStream *const inputStream = [[[_audioInput streams] objectEnumerator] nextObject];
	if(!inputStream) return nil;
	ECVAudioPipe *const pipe = [[[ECVAudioPipe alloc] initWithInputDescription:[inputStream basicDescription] outputDescription:ECVAudioRecordingOutputDescription upconvertFromMono:_upconvertsFromMono] autorelease];
	[pipe setDropsBuffers:NO];
	return pipe;
}

#pragma mark -NSObject

- (id)init
{
	if((self = [super init])) {
		_videoCodec = kJPEGCodecType;
		_videoQuality = 0.5f;
		_stretchOutput = YES;
		_cropRect = ECVUncroppedRect;

		_volume = 1.0f;
	}
	return self;
}
- (void)dealloc
{
	[_URL release];
	[_videoStorage release];
	[_audioInput release];
	[super dealloc];
}

@end

enum {
	ECVRecordThreadWait,
	ECVRecordThreadRun,
	ECVRecordThreadFinished,
};

@interface ECVMovieRecorder(Private)<ECVCompressionDelegate>

- (void)_threaded_record:(ECVMovieRecordingOptions *const)options;

- (void)_addFrame:(ECVVideoFrame *const)frame withCompressionSession:(ICMCompressionSessionRef const)compressionSession pixelBuffer:(CVPixelBufferRef const)pixelBuffer displayDuration:(TimeValue64 const)displayDuration;
- (void)_addAudioBufferFromPipe:(ECVAudioPipe *const)audioPipe description:(SoundDescriptionHandle const)description buffer:(void *const)buffer media:(Media const)media;

@end

@implementation ECVMovieRecorder

#pragma mark +NSObject

+ (void)initialize
{
	if([ECVMovieRecorder class] == self) ECVOSErr(EnterMovies());
}

#pragma mark -ECVMovieRecorder

- (id)initWithOptions:(ECVMovieRecordingOptions *const)options error:(out NSError **const)outError
{
	if(outError) *outError = nil;
	if(!(self = [super init])) return nil;

	_lock = [[NSConditionLock alloc] initWithCondition:ECVRecordThreadWait];
	_videoFrames = [[NSMutableArray alloc] init];
	_frameRateConverter = [[options _frameRateConverter] retain];
	_audioPipe = [[options _audioPipe] retain];

	[NSThread detachNewThreadSelector:@selector(_threaded_record:) toTarget:self withObject:options];

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
	if(ECVRecordThreadFinished == [_lock condition]) return [_lock unlock];
	_stop = YES;
	[_lock unlockWithCondition:ECVRecordThreadRun];
	[_lock lockWhenCondition:ECVRecordThreadFinished];
	[_lock unlock];
}

#pragma mark -ECVMovieRecorder(Private)

- (void)_threaded_record:(ECVMovieRecordingOptions *const)options
{
	NSAutoreleasePool *const outerPool = [[NSAutoreleasePool alloc] init];
	ECVOSErr(EnterMoviesOnThread(kNilOptions));

	Handle dataRef = NULL;
	OSType dataRefType = 0;

	Movie movie = NULL;
	DataHandler dataHandler = NULL;
	if([options recordsToRAM]) {
		ECVLog(ECVError, @"Record to RAM option is temporarily not supported.");
		// I've spent too many hours trying to figure this out.
	} else {
		ECVOSErr(QTNewDataReferenceFromCFURL((CFURLRef)[options URL], kNilOptions, &dataRef, &dataRefType));
		ECVOSErr(CreateMovieStorage(dataRef, dataRefType, 'TVOD', smSystemScript, createMovieFileDeleteCurFile, &dataHandler, &movie));
	}

	if(!movie) {
		ECVLog(ECVError, @"Movie could not be created.");
		goto bail;
	}

	ECVIntegerSize const outputSize = [options _outputSize];
	ICMCompressionSessionRef const compressionSession = [options _compressionSessionWithDelegate:self];
	ECVVideoStorage *const videoStorage = [options videoStorage];

	Track const videoTrack = NewMovieTrack(movie, Long2Fix(outputSize.width), Long2Fix(outputSize.height), kNoVolume);
	Media const videoMedia = _videoMedia = NewTrackMedia(videoTrack, VideoMediaType, [_frameRateConverter targetFrameRate].timeScale, NULL, 0);
	ECVOSErr(BeginMediaEdits(videoMedia));

	CVPixelBufferRef pixelBuffer = NULL;
	ECVCVReturn(CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, ICMCompressionSessionGetPixelBufferPool(compressionSession), &pixelBuffer));

	Track const audioTrack = _audioPipe ? NewMovieTrack(movie, 0, 0, (short)round([options volume] * kFullVolume)) : NULL;
	Media const audioMedia = audioTrack ? NewTrackMedia(audioTrack, SoundMediaType, ECVAudioRecordingOutputDescription.mSampleRate, NULL, 0) : NULL;
	SoundDescriptionHandle soundDescription = NULL;
	void *const audioBuffer = audioMedia ? malloc(ECVAudioBufferBytesSize) : NULL;
	if(audioMedia) {
		ECVOSErr(BeginMediaEdits(audioMedia));
		ECVOSStatus(QTSoundDescriptionCreate((AudioStreamBasicDescription *)&ECVAudioRecordingOutputDescription, NULL, 0, NULL, 0, kQTSoundDescriptionKind_Movie_AnyVersion, &soundDescription));
	}

	BOOL stop = NO;
	while(!stop) {
		NSAutoreleasePool *const innerPool = [[NSAutoreleasePool alloc] init];

		[_lock lockWhenCondition:ECVRecordThreadRun];
		NSUInteger dropCount = [videoStorage dropFramesFromArray:_videoFrames];
		ECVVideoFrame *const frame = [[[_videoFrames lastObject] retain] autorelease];
		if(frame) [_videoFrames removeLastObject];
		BOOL const moreToDo = [_videoFrames count] || [_audioPipe hasReadyBuffers];
		if(_stop && !moreToDo) stop = YES;
		[_lock unlockWithCondition:moreToDo ? ECVRecordThreadRun : ECVRecordThreadWait];

		while(dropCount--) [self addEncodedFrame:NULL];
		[self _addFrame:frame withCompressionSession:compressionSession pixelBuffer:pixelBuffer displayDuration:[_frameRateConverter targetFrameRate].timeValue];
		[self _addAudioBufferFromPipe:_audioPipe description:soundDescription buffer:audioBuffer media:audioMedia];

		[innerPool release];
	}

	if(compressionSession) ECVOSStatus(ICMCompressionSessionCompleteFrames(compressionSession, true, 0, 0));
	if(videoMedia) ECVOSErr(InsertMediaIntoTrack(GetMediaTrack(videoMedia), 0, GetMediaDisplayStartTime(videoMedia), GetMediaDisplayDuration(videoMedia), fixed1));
	if(audioMedia) ECVOSErr(InsertMediaIntoTrack(GetMediaTrack(audioMedia), 0, GetMediaDisplayStartTime(audioMedia), GetMediaDisplayDuration(audioMedia), fixed1));
	if(videoMedia) ECVOSErr(EndMediaEdits(videoMedia));
	if(audioMedia) ECVOSErr(EndMediaEdits(audioMedia));

	if([options recordsToRAM]) {
		// TODO: Implement.
	} else {
		UpdateMovieInStorage(movie, dataHandler);
		CloseMovieStorage(dataHandler);
	}

	if(compressionSession) ICMCompressionSessionRelease(compressionSession);
	CVPixelBufferRelease(pixelBuffer);

	if(soundDescription) DisposeHandle((Handle)soundDescription);
	if(audioBuffer) free(audioBuffer);

	if(videoMedia) DisposeTrackMedia(videoMedia);
	if(videoTrack) DisposeMovieTrack(videoTrack);

	if(audioMedia) DisposeTrackMedia(audioMedia);
	if(audioTrack) DisposeMovieTrack(audioTrack);

	_videoMedia = NULL;
	if(_encodedFrame) ICMEncodedFrameRelease(_encodedFrame);
	_encodedFrame = NULL;

	DisposeMovie(movie);

bail:

	ECVOSErr(ExitMoviesOnThread());

	[_lock lock];
	[_lock unlockWithCondition:ECVRecordThreadFinished];

	[outerPool release];
}

#pragma mark -

- (void)_addFrame:(ECVVideoFrame *const)frame withCompressionSession:(ICMCompressionSessionRef const)compressionSession pixelBuffer:(CVPixelBufferRef const)pixelBuffer displayDuration:(TimeValue64 const)displayDuration
{
	if(!frame) return;
	if(![frame lockIfHasBytes]) return [self addEncodedFrame:NULL];
	ECVCVPixelBuffer *const buffer = [[[ECVCVPixelBuffer alloc] initWithPixelBuffer:pixelBuffer] autorelease];
	[buffer lock];
	[buffer drawPixelBuffer:frame];
	[buffer unlock];
	[frame unlock];
	ECVOSStatus(ICMCompressionSessionEncodeFrame(compressionSession, pixelBuffer, 0, displayDuration, kICMValidTime_DisplayDurationIsValid, NULL, NULL, NULL));
}
- (void)_addAudioBufferFromPipe:(ECVAudioPipe *const)audioPipe description:(SoundDescriptionHandle const)description buffer:(void *const)buffer media:(Media const)media
{
	if(![audioPipe hasReadyBuffers]) return;
	AudioBufferList outputBufferList = {1, {2, ECVAudioBufferBytesSize, buffer}};
	[audioPipe requestOutputBufferList:&outputBufferList];
	ByteCount const size = outputBufferList.mBuffers[0].mDataByteSize;
	if(!size || !outputBufferList.mBuffers[0].mData) return;
	AddMediaSample2(media, outputBufferList.mBuffers[0].mData, size, 1, 0, (SampleDescriptionHandle)description, size / ECVAudioRecordingOutputDescription.mBytesPerFrame, 0, NULL);
}

#pragma mark -ECVMovieRecorder(Private)<ECVCompressionDelegate>

- (void)addEncodedFrame:(ICMEncodedFrameRef const)frame
{
	if(frame && frame != _encodedFrame) {
		ICMEncodedFrameRelease(_encodedFrame);
		_encodedFrame = ICMEncodedFrameRetain(frame);
	}
	if(!_encodedFrame) return;

	UInt8 const *const dataPtr = ICMEncodedFrameGetDataPtr(_encodedFrame);
	ByteCount const bufferSize = ICMEncodedFrameGetDataSize(_encodedFrame);
	TimeValue64 const decodeDuration = ICMEncodedFrameGetDecodeDuration(_encodedFrame);
	TimeValue64 const displayOffset = ICMEncodedFrameGetDisplayOffset(_encodedFrame);
	ImageDescriptionHandle descriptionHandle = NULL;
	ECVOSStatus(ICMEncodedFrameGetImageDescription(_encodedFrame, &descriptionHandle));
	MediaSampleFlags const mediaSampleFlags = ICMEncodedFrameGetMediaSampleFlags(_encodedFrame);

	ECVOSStatus(AddMediaSample2(_videoMedia, dataPtr, bufferSize, decodeDuration, displayOffset, (SampleDescriptionHandle)descriptionHandle, 1, mediaSampleFlags, NULL));
}

#pragma mark -NSObject

- (void)dealloc
{
	[_lock release];
	[_videoFrames release];
	[_audioPipe release];
	[_frameRateConverter release];
	[super dealloc];
}

@end

#endif
