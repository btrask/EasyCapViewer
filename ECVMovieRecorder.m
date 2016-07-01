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
#import "ECVVideoFormat.h"
#import "ECVVideoStorage.h"
#import "ECVVideoFrame.h"
#import "ECVFrameRateConverter.h"

// Other Sources
#if defined(ECV_ENABLE_AUDIO)
#import "ECVAudioDevice.h"
#import "ECVAudioPipe.h"
#endif
#import "ECVDebug.h"
#import "ECVICM.h"

#define ECVAudioBufferBytesSize (ECVStandardAudioStreamBasicDescription.mBytesPerPacket * 1000) // Should be more than enough to keep up with the incoming data.

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
@synthesize frameRate = _frameRate;

#pragma mark -

- (NSDictionary *)cleanAperatureDictionary
{
	NSRect const c = [self cropRect];
	ECVIntegerSize const s1 = [[_videoStorage videoFormat] frameSize];
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
	return [[[ECVFrameRateConverter alloc] initWithSourceFrameRate:[[_videoStorage videoFormat] frameRate] targetFrameRate:_frameRate] autorelease];
}
- (ECVIntegerSize)_outputSize
{
	return _stretchOutput ? _outputSize : [[_videoStorage videoFormat] frameSize];
}
- (ICMCompressionSessionRef)_compressionSessionWithDelegate:(id<ECVCompressionDelegate> const)delegate
{
	ICMCompressionSessionOptionsRef opts = NULL;
	ECVOSStatus(ICMCompressionSessionOptionsCreate(kCFAllocatorDefault, &opts));

	ECVICMCSOSetProperty(opts, DurationsNeeded, (Boolean)true);
	ECVICMCSOSetProperty(opts, AllowAsyncCompletion, (Boolean)true);
	NSTimeInterval frameRateInterval = 0.0;
	if(QTGetTimeInterval(_frameRate, &frameRateInterval)) ECVICMCSOSetProperty(opts, ExpectedFrameRate, X2Fix(1.0 / frameRateInterval));
	ECVICMCSOSetProperty(opts, CPUTimeBudget, (UInt32)QTMakeTimeScaled(_frameRate, ECVMicrosecondsPerSecond).timeValue);
	ECVICMCSOSetProperty(opts, ScalingMode, (OSType)kICMScalingMode_StretchCleanAperture);
	ECVICMCSOSetProperty(opts, Quality, (CodecQ)round([self videoQuality] * codecMaxQuality));
	ECVICMCSOSetProperty(opts, Depth, [_videoStorage pixelFormat]);
	ICMEncodedFrameOutputRecord callback = {};
	callback.frameDataAllocator = kCFAllocatorDefault;
	callback.encodedFrameOutputCallback = (ICMEncodedFrameOutputCallback)ECVCompressionDelegateHandler;
	callback.encodedFrameOutputRefCon = delegate;

	ECVIntegerSize const frameSize = [[_videoStorage videoFormat] frameSize];
	ICMCompressionSessionRef compressionSession = NULL;
	ECVOSStatus(ICMCompressionSessionCreate(kCFAllocatorDefault, _outputSize.width, _outputSize.height, [self videoCodec], _frameRate.timeScale, opts, (CFDictionaryRef)[NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithUnsignedInteger:frameSize.width], kCVPixelBufferWidthKey,
		[NSNumber numberWithUnsignedInteger:frameSize.height], kCVPixelBufferHeightKey,
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
	ECVAudioPipe *const pipe = [[[ECVAudioPipe alloc] initWithInputDescription:[inputStream basicDescription] outputDescription:ECVStandardAudioStreamBasicDescription upconvertFromMono:_upconvertsFromMono] autorelease];
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
	ECVThreadWait,
	ECVThreadRun,
	ECVThreadFinished,
};

@interface ECVMovieRecorder(Private)<ECVCompressionDelegate>

- (void)_thread_compress:(ECVMovieRecordingOptions *const)options;
- (void)_thread_record:(ECVMovieRecordingOptions *const)options;

- (void)_addEncodedFrame:(ICMEncodedFrameRef const)frame frameRateConverter:(ECVFrameRateConverter *const)frameRateConverter media:(Media const)media;
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

	_compressLock = [[NSConditionLock alloc] initWithCondition:ECVThreadWait];
	_compressQueue = [[NSMutableArray alloc] init];
	_recordLock = [[NSConditionLock alloc] initWithCondition:ECVThreadWait];
	_recordQueue = [[NSMutableArray alloc] init];
	_audioPipe = [[options _audioPipe] retain];

	[NSThread detachNewThreadSelector:@selector(_thread_compress:) toTarget:self withObject:options];
	[NSThread detachNewThreadSelector:@selector(_thread_record:) toTarget:self withObject:options];

	return self;
}

#pragma mark -

- (void)addVideoFrame:(ECVVideoFrame *const)frame
{
	[_compressLock lock];
	if(ECVThreadFinished == [_compressLock condition]) return [_compressLock unlock];
	[_compressQueue insertObject:frame atIndex:0];
	[_compressLock unlockWithCondition:ECVThreadRun];
}
- (void)addAudioBufferList:(AudioBufferList const *const)bufferList
{
	[_recordLock lock];
	if(ECVThreadFinished == [_recordLock condition]) return [_recordLock unlock];
	[_audioPipe receiveInputBufferList:bufferList];
	[_recordLock unlockWithCondition:ECVThreadRun];
}

#pragma mark -

- (void)stopRecording
{
	[_compressLock lock];
	[_recordLock lock];
	if(_stop) {
		[_recordLock unlock];
		[_compressLock unlock];
		return;
	}
	_stop = YES;
	[_recordLock unlockWithCondition:ECVThreadRun];
	[_compressLock unlockWithCondition:ECVThreadRun];
	[_recordLock lockWhenCondition:ECVThreadFinished];
	[_recordLock unlock];
}

#pragma mark -ECVMovieRecorder(Private)

- (void)_thread_compress:(ECVMovieRecordingOptions *const)options
{
	NSAutoreleasePool *const outerPool = [[NSAutoreleasePool alloc] init];
	ECVOSErr(EnterMoviesOnThread(kNilOptions));

	ICMCompressionSessionRef const compressionSession = [options _compressionSessionWithDelegate:self];
	CVPixelBufferRef pixelBuffer = NULL;
	ECVCVReturn(CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, ICMCompressionSessionGetPixelBufferPool(compressionSession), &pixelBuffer));

	for(;;) {
		NSAutoreleasePool *const innerPool = [[NSAutoreleasePool alloc] init];

		[_compressLock lockWhenCondition:ECVThreadRun];
		ECVVideoFrame *const frame = [[[_compressQueue lastObject] retain] autorelease];
		if(frame) [_compressQueue removeLastObject];
		BOOL const remaining = !![_compressQueue count];
		BOOL const stop = _stop;
		[_compressLock unlockWithCondition:remaining ? ECVThreadRun : ECVThreadWait];

		if([frame lockIfHasBytes]) {
			ECVCVPixelBuffer *const buffer = [[[ECVCVPixelBuffer alloc] initWithPixelBuffer:pixelBuffer] autorelease];
			[buffer lock];
			[buffer drawPixelBuffer:frame];
			[buffer unlock];
			[frame unlock];
			ECVOSStatus(ICMCompressionSessionEncodeFrame(compressionSession, pixelBuffer, 0, [options frameRate].timeValue, kICMValidTime_DisplayDurationIsValid, NULL, NULL, NULL));
		} else if(frame) {
			[self addEncodedFrame:NULL];
		}

		if(stop && !remaining) {
			[innerPool drain];
			break;
		}

		[innerPool release];
	}

	if(compressionSession) ECVOSStatus(ICMCompressionSessionCompleteFrames(compressionSession, true, 0, 0));
	if(compressionSession) ICMCompressionSessionRelease(compressionSession);
	CVPixelBufferRelease(pixelBuffer);

	ICMEncodedFrameRelease(_encodedFrame);
	_encodedFrame = NULL;

	[_compressLock lock];
	[_compressLock unlockWithCondition:ECVThreadFinished];

	ECVOSErr(ExitMoviesOnThread());
	[outerPool release];
}
- (void)_thread_record:(ECVMovieRecordingOptions *const)options
{
	NSAutoreleasePool *const outerPool = [[NSAutoreleasePool alloc] init];
	ECVOSErr(EnterMoviesOnThread(kNilOptions));

	Handle dataRef = NULL;
	OSType dataRefType = 0;

	Movie movie = NULL;
	DataHandler dataHandler = NULL;
	ECVOSErr(QTNewDataReferenceFromCFURL((CFURLRef)[options URL], kNilOptions, &dataRef, &dataRefType));
	ECVOSErr(CreateMovieStorage(dataRef, dataRefType, 'TVOD', smSystemScript, createMovieFileDeleteCurFile, &dataHandler, &movie));

	if(!movie) {
		ECVLog(ECVError, @"Movie could not be created.");
		goto bail;
	}

	ECVIntegerSize const outputSize = [options _outputSize];
	ECVVideoStorage *const videoStorage = [options videoStorage];
	ECVFrameRateConverter *const frameRateConverter = [options _frameRateConverter];

	Track const videoTrack = NewMovieTrack(movie, Long2Fix(outputSize.width), Long2Fix(outputSize.height), kNoVolume);
	Media const videoMedia = NewTrackMedia(videoTrack, VideoMediaType, [options frameRate].timeScale, NULL, 0);
	ECVOSErr(BeginMediaEdits(videoMedia));

	Track const audioTrack = _audioPipe ? NewMovieTrack(movie, 0, 0, (short)round([options volume] * kFullVolume)) : NULL;
	Media const audioMedia = audioTrack ? NewTrackMedia(audioTrack, SoundMediaType, ECVStandardAudioStreamBasicDescription.mSampleRate, NULL, 0) : NULL;
	SoundDescriptionHandle soundDescription = NULL;
	void *const audioBuffer = audioMedia ? malloc(ECVAudioBufferBytesSize) : NULL;
	if(audioMedia) {
		ECVOSErr(BeginMediaEdits(audioMedia));
		ECVOSStatus(QTSoundDescriptionCreate((AudioStreamBasicDescription *)&ECVStandardAudioStreamBasicDescription, NULL, 0, NULL, 0, kQTSoundDescriptionKind_Movie_AnyVersion, &soundDescription));
	}

	for(;;) {
		NSAutoreleasePool *const innerPool = [[NSAutoreleasePool alloc] init];

		[_recordLock lockWhenCondition:ECVThreadRun];
		ICMEncodedFrameRef const frame = (ICMEncodedFrameRef)[[[_recordQueue lastObject] retain] autorelease];
		if(frame) [_recordQueue removeLastObject];
		BOOL const remaining = [_recordQueue count] || [_audioPipe hasReadyBuffers];
		BOOL const stop = _stop;
		[_recordLock unlockWithCondition:remaining ? ECVThreadRun : ECVThreadWait];

		[self _addEncodedFrame:frame frameRateConverter:frameRateConverter media:videoMedia];
		[self _addAudioBufferFromPipe:_audioPipe description:soundDescription buffer:audioBuffer media:audioMedia];

		if(stop && !remaining) {
			[innerPool release];
			break;
		}

		[innerPool release];
	}

	[_compressLock lockWhenCondition:ECVThreadFinished];
	[_compressLock unlock];

	if(videoMedia) ECVOSErr(InsertMediaIntoTrack(GetMediaTrack(videoMedia), 0, GetMediaDisplayStartTime(videoMedia), GetMediaDisplayDuration(videoMedia), fixed1));
	if(audioMedia) ECVOSErr(InsertMediaIntoTrack(GetMediaTrack(audioMedia), 0, GetMediaDisplayStartTime(audioMedia), GetMediaDisplayDuration(audioMedia), fixed1));
	if(videoMedia) ECVOSErr(EndMediaEdits(videoMedia));
	if(audioMedia) ECVOSErr(EndMediaEdits(audioMedia));

	UpdateMovieInStorage(movie, dataHandler);
	CloseMovieStorage(dataHandler);

	if(soundDescription) DisposeHandle((Handle)soundDescription);
	if(audioBuffer) free(audioBuffer);

	if(videoMedia) DisposeTrackMedia(videoMedia);
	if(videoTrack) DisposeMovieTrack(videoTrack);

	if(audioMedia) DisposeTrackMedia(audioMedia);
	if(audioTrack) DisposeMovieTrack(audioTrack);

	DisposeMovie(movie);

bail:

	[_recordLock lock];
	[_recordLock unlockWithCondition:ECVThreadFinished];

	ECVOSErr(ExitMoviesOnThread());
	[outerPool release];
}

#pragma mark -

- (void)_addEncodedFrame:(ICMEncodedFrameRef const)frame frameRateConverter:(ECVFrameRateConverter *const)frameRateConverter media:(Media const)media
{
	if(!frame) return;

	UInt8 const *const dataPtr = ICMEncodedFrameGetDataPtr(frame);
	ByteCount const bufferSize = ICMEncodedFrameGetDataSize(frame);
	TimeValue64 const decodeDuration = ICMEncodedFrameGetDecodeDuration(frame);
	TimeValue64 const displayOffset = ICMEncodedFrameGetDisplayOffset(frame);
	ImageDescriptionHandle descriptionHandle = NULL;
	ECVOSStatus(ICMEncodedFrameGetImageDescription(frame, &descriptionHandle));
	MediaSampleFlags const mediaSampleFlags = ICMEncodedFrameGetMediaSampleFlags(frame);

	NSUInteger const count = [frameRateConverter nextFrameRepeatCount];

	for(NSUInteger i = 0; i < count; ++i) {
		ECVOSStatus(AddMediaSample2(media, dataPtr, bufferSize, decodeDuration, displayOffset, (SampleDescriptionHandle)descriptionHandle, 1, mediaSampleFlags, NULL));
	}
}
- (void)_addAudioBufferFromPipe:(ECVAudioPipe *const)audioPipe description:(SoundDescriptionHandle const)description buffer:(void *const)buffer media:(Media const)media
{
	if(![audioPipe hasReadyBuffers]) return;
	AudioBufferList outputBufferList = {1, {2, ECVAudioBufferBytesSize, buffer}};
	[audioPipe requestOutputBufferList:&outputBufferList];
	ByteCount const size = outputBufferList.mBuffers[0].mDataByteSize;
	if(!size || !outputBufferList.mBuffers[0].mData) return;
	AddMediaSample2(media, outputBufferList.mBuffers[0].mData, size, 1, 0, (SampleDescriptionHandle)description, size / ECVStandardAudioStreamBasicDescription.mBytesPerFrame, 0, NULL);
}

#pragma mark -ECVMovieRecorder(Private)<ECVCompressionDelegate>

- (void)addEncodedFrame:(ICMEncodedFrameRef const)frame
{
	if(frame && frame != _encodedFrame) {
		ICMEncodedFrameRelease(_encodedFrame);
		_encodedFrame = ICMEncodedFrameRetain(frame);
	}
	if(!_encodedFrame) return;
	[_recordLock lock];
	[_recordQueue insertObject:(id)_encodedFrame atIndex:0];
	[_recordLock unlockWithCondition:ECVThreadRun];
}

#pragma mark -NSObject

- (void)dealloc
{
	[_compressLock release];
	[_compressQueue release];
	[_recordLock release];
	[_recordQueue release];
	[_audioPipe release];
	[super dealloc];
}

@end

#endif
