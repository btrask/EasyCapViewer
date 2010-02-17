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

@interface ECVMovieRecorder : NSObject
{
	@private
	NSURL *_URL;
	ECVVideoStorage *_videoStorage;
	ECVAudioDevice *_audioDevice;

	OSType _videoCodec;
	CGFloat _videoQuality;
	ECVPixelSize _outputSize;
	NSRect _cropRect;
	NSDictionary *_cleanAperture;
	BOOL _upconvertsFromMono;
	BOOL _recordsDirectlyToDisk;

	CGFloat _volume;

	NSConditionLock *_lock;
	BOOL _stop;
	CVPixelBufferRef _pixelBuffer;
	NSMutableArray *_videoFrames;

	Media _videoMedia;
	ICMCompressionSessionRef _compressionSession;
	ICMEncodedFrameRef _encodedFrame;
	Media _audioMedia;
	ECVAudioPipe *_audioPipe;
	SoundDescriptionHandle _audioDescriptionHandle;
	void *_audioBufferBytes;
}

- (id)initWithURL:(NSURL *)URL videoStorage:(ECVVideoStorage *)videoStorage audioDevice:(ECVAudioDevice *)audioDevice;
@property(readonly) NSURL *URL;
@property(readonly) ECVVideoStorage *videoStorage;
@property(readonly) ECVAudioDevice *audioDevice;

@property(assign) OSType videoCodec;
@property(assign) CGFloat videoQuality;
@property(assign) ECVPixelSize outputSize;
@property(assign) NSRect cropRect;
@property(assign) BOOL upconvertsFromMono;
@property(assign) BOOL recordsDirectlyToDisk;

@property(assign) CGFloat volume;

- (BOOL)startRecordingError:(out NSError **)outError;
- (void)stopRecording;

- (void)addVideoFrame:(ECVVideoFrame *)frame;
- (void)addAudioBufferList:(AudioBufferList const *)bufferList;

@end

#endif
