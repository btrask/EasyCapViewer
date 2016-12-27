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
#import <CoreVideo/CoreVideo.h>
#import <QTKit/QTKit.h>

// Models
@class ECVVideoStorage;
@class ECVVideoFrame;
@class ECVFrameRateConverter;

// Other Sources
@class ECVAudioInput;
@class ECVAudioPipe;

@interface ECVMovieRecordingOptions : NSObject
{
	@private
	NSURL *_URL;
	ECVVideoStorage *_videoStorage;
	ECVAudioInput *_audioInput;

	OSType _videoCodec;
	CGFloat _videoQuality;
	BOOL _stretchOutput;
	ECVIntegerSize _outputSize;
	NSRect _cropRect;
	BOOL _upconvertsFromMono;
	CMTime _frameRate;

	CGFloat _volume;
}

@property(copy) NSURL *URL;
@property(retain) ECVVideoStorage *videoStorage;
@property(retain) ECVAudioInput *audioInput;

// Video
@property(assign) OSType videoCodec;
@property(assign) CGFloat videoQuality;
@property(assign) BOOL stretchOutput;
@property(assign) ECVIntegerSize outputSize;
@property(assign) NSRect cropRect;
@property(assign) BOOL upconvertsFromMono;
@property(assign) CMTime frameRate;

@property(readonly) NSDictionary *cleanAperatureDictionary;

// Audio
@property(assign) CGFloat volume;

@end

@interface ECVMovieRecorder : NSObject
{
	@private
	NSConditionLock *_compressLock;
	NSMutableArray *_compressQueue;
	NSConditionLock *_recordLock;
	NSMutableArray *_recordQueue;
	ECVAudioPipe *_audioPipe;
	BOOL _stop;

	ICMEncodedFrameRef _encodedFrame;
}

- (id)initWithOptions:(ECVMovieRecordingOptions *const)options error:(out NSError **const)outError;

- (void)addVideoFrame:(ECVVideoFrame *const)frame;
- (void)addAudioBufferList:(AudioBufferList const *const)bufferList;

- (void)stopRecording;

@end

#endif
