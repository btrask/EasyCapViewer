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
#import <CoreVideo/CoreVideo.h>
#import <QTKit/QTKit.h>

// Models
@class ECVVideoStorage;
@class ECVVideoFrame;

// Other Sources
@class ECVAudioDevice;
@class ECVAudioPipe;

@interface ECVMovieRecordingOptions : NSObject
{
	@private
	NSURL *_URL;
	ECVVideoStorage *_videoStorage;
	ECVAudioDevice *_audioDevice;

	OSType _videoCodec;
	CGFloat _videoQuality;
	BOOL _stretchOutput;
	ECVIntegerSize _outputSize;
	NSRect _cropRect;
	BOOL _upconvertsFromMono;
	BOOL _recordsToRAM;
	BOOL _halfFrameRate;

	CGFloat _volume;
}

@property(copy) NSURL *URL;
@property(retain) ECVVideoStorage *videoStorage;
@property(retain) ECVAudioDevice *audioDevice;

// Video
@property(assign) OSType videoCodec;
@property(assign) CGFloat videoQuality;
@property(assign) BOOL stretchOutput;
@property(assign) ECVIntegerSize outputSize;
@property(assign) NSRect cropRect;
@property(assign) BOOL upconvertsFromMono;
@property(assign) BOOL recordsToRAM;
@property(assign) BOOL halfFrameRate;

@property(readonly) QTTime frameRate;
@property(readonly) NSDictionary *cleanAperatureDictionary;

// Audio
@property(assign) CGFloat volume;

@end

@interface ECVMovieRecorder : NSObject
{
	@private
	NSConditionLock *_lock;
	BOOL _stop;
	NSURL *_writeURL;

	ECVVideoStorage *_videoStorage;
	CVPixelBufferRef _pixelBuffer;
	NSMutableArray *_videoFrames;
	Media _videoMedia;
	ICMCompressionSessionRef _compressionSession;
	ICMEncodedFrameRef _encodedFrame;
	QTTime _frameRate;
	NSUInteger _frameSkipper;
	ECVIntegerSize _outputSize;

	Media _audioMedia;
	ECVAudioPipe *_audioPipe;
	SoundDescriptionHandle _audioDescriptionHandle;
	void *_audioBufferBytes;
	CGFloat _volume;
}

- (id)initWithOptions:(ECVMovieRecordingOptions *)options error:(out NSError **)outError;

- (void)addVideoFrame:(ECVVideoFrame *)frame;
- (void)addAudioBufferList:(AudioBufferList const *)bufferList;

- (void)stopRecording;

@end

#endif
