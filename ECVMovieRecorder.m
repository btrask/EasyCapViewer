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

@interface ECVBufferCopyOperation : NSOperation
{
	@private
	ECVMovieRecorder *_recorder;
	ECVVideoFrame *_frame;
	CVPixelBufferRef _pixelBuffer;
	BOOL _success;
}

- (id)initWithRecorder:(ECVMovieRecorder *)recorder frame:(ECVVideoFrame *)frame pixelBuffer:(CVPixelBufferRef)pixelBuffer;
@property(readonly) CVPixelBufferRef pixelBuffer;
@property(readonly) BOOL success;

@end

@interface ECVMovieRecorder(Private)

- (void)_threaded_recordToMovie:(QTMovie *)movie;

- (void)_videoOperationComplete:(ECVBufferCopyOperation *)op;
- (void)_recordVideoOperation:(ECVBufferCopyOperation *)op;
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

#pragma mark -

@synthesize volume = _volume;

#pragma mark -

- (BOOL)startRecordingError:(out NSError **)outError
{
	QTMovie *const movie = [[[QTMovie alloc] initToWritableFile:[_URL path] error:outError] autorelease];
	if(!movie) return NO;

	_videoOperations = [[NSMutableArray alloc] init];
	_completedVideoOperations = [[NSMutableSet alloc] init];

	ICMCompressionSessionOptionsRef options = NULL;
	ECVOSStatus(ICMCompressionSessionOptionsCreate(kCFAllocatorDefault, &options));
	ECVCSOSetProperty(options, kICMCompressionSessionOptionsPropertyID_DurationsNeeded, (Boolean)true);
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
		nil], &callback, &_compressionSession));
	ICMCompressionSessionOptionsRelease(options);
	_pixelBufferPool = ICMCompressionSessionGetPixelBufferPool(_compressionSession);

	ECVAudioStream *const inputStream = [[[_audioDevice streams] objectEnumerator] nextObject];
	if(inputStream) {
		_audioPipe = [[ECVAudioPipe alloc] initWithInputDescription:[inputStream basicDescription] outputDescription:ECVAudioRecordingOutputDescription];
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
	CVPixelBufferRef pixelBuffer = NULL;
	ECVCVReturn(CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, _pixelBufferPool, &pixelBuffer));
	ECVBufferCopyOperation *const op = [[[ECVBufferCopyOperation alloc] initWithRecorder:self frame:frame pixelBuffer:pixelBuffer] autorelease];
	CVPixelBufferRelease(pixelBuffer);
	[_videoOperations insertObject:op atIndex:0];
	[_lock unlock];
	[_videoStorage addFrameOperation:op];
}
- (void)addAudioBufferList:(AudioBufferList const *)bufferList
{
	[_audioPipe receiveInputBufferList:bufferList];
	[_lock lock];
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

	ECVOSStatus(QTSoundDescriptionCreate((AudioStreamBasicDescription *)&ECVAudioRecordingOutputDescription, NULL, 0, NULL, 0, kQTSoundDescriptionKind_Movie_AnyVersion, &_audioDescriptionHandle));
	_audioBufferBytes = malloc(ECVAudioBufferBytesSize);

	BOOL stop = NO;
	while(!stop) {
		NSAutoreleasePool *const innerPool = [[NSAutoreleasePool alloc] init];

		[_lock lockWhenCondition:ECVRecordThreadRun];
		ECVBufferCopyOperation *const op = [_completedVideoOperations member:[[[_videoOperations lastObject] retain] autorelease]];
		if(op) {
			[_videoOperations removeObjectIdenticalTo:op];
			[_completedVideoOperations removeObject:op];
		}
		BOOL const moreToDo = [_completedVideoOperations containsObject:[_videoOperations lastObject]] || [_audioPipe hasReadyBuffers];
		if(_stop && !moreToDo) stop = YES;
		[_lock unlockWithCondition:moreToDo ? ECVRecordThreadRun : ECVRecordThreadWait];

		if(op) [self _recordVideoOperation:op];
		[self _recordAudioBuffer];

		[innerPool release];
	}

	ECVOSStatus(ICMCompressionSessionCompleteFrames(_compressionSession, true, 0, 0));
	ECVOSErr(InsertMediaIntoTrack(GetMediaTrack(_videoMedia), 0, GetMediaDisplayStartTime(_videoMedia), GetMediaDisplayDuration(_videoMedia), fixed1));
	ECVOSErr(InsertMediaIntoTrack(GetMediaTrack(_audioMedia), 0, GetMediaDisplayStartTime(_audioMedia), GetMediaDisplayDuration(_audioMedia), fixed1));
	ECVOSErr(EndMediaEdits(_videoMedia));
	ECVOSErr(EndMediaEdits(_audioMedia));
	[movie updateMovieFile];

	if(_compressionSession) ICMCompressionSessionRelease(_compressionSession);
	_completedVideoOperations = NULL;
	if(_encodedFrame) ICMEncodedFrameRelease(_encodedFrame);
	_encodedFrame = NULL;
	_pixelBufferPool = NULL;

	[_audioPipe release];
	_audioPipe = nil;
	if(_audioDescriptionHandle) DisposeHandle((Handle)_audioDescriptionHandle);
	if(_audioBufferBytes) free(_audioBufferBytes);
	_audioBufferBytes = NULL;

	_videoMedia = NULL;
	_audioMedia = NULL;

	[_videoOperations release];
	_videoOperations = nil;
	[_completedVideoOperations release];
	_completedVideoOperations = nil;

	[movie detachFromCurrentThread];
	[QTMovie exitQTKitOnThread];
	[outerPool release];
}

#pragma mark -

- (void)_videoOperationComplete:(ECVBufferCopyOperation *)op
{
	[_lock lock];
	[_completedVideoOperations addObject:op];
	[_lock unlockWithCondition:ECVRecordThreadRun];
}
- (void)_recordVideoOperation:(ECVBufferCopyOperation *)op
{
	NSParameterAssert(op);
	if([op success]) {
		if(_cleanAperture) CVBufferSetAttachment([op pixelBuffer], kCVImageBufferCleanApertureKey, _cleanAperture, kCVAttachmentMode_ShouldNotPropagate);
		ECVOSStatus(ICMCompressionSessionEncodeFrame(_compressionSession, [op pixelBuffer], 0, [_videoStorage frameRate].timeValue, kICMValidTime_DisplayDurationIsValid, NULL, NULL, NULL));
	} else [self _addEncodedFrame:NULL];
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

@implementation ECVBufferCopyOperation

#pragma mark -ECVBufferCopyOperation

- (id)initWithRecorder:(ECVMovieRecorder *)recorder frame:(ECVVideoFrame *)frame pixelBuffer:(CVPixelBufferRef)pixelBuffer
{
	if((self = [super init])) {
		_recorder = [recorder retain];
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
	[_recorder _videoOperationComplete:self];
}

#pragma mark -NSObject

- (void)dealloc
{
	[_recorder release];
	[_frame release];
	CVPixelBufferRelease(_pixelBuffer);
	[super dealloc];
}

@end

#endif
