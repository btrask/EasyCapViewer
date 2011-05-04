/* Copyright (c) 2011, Ben Trask
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
// Storages/Audio
//#import "ECVAudioStorage.h"

// Models/Sources/Video
#import "ECVVideoSource.h"

// Models/Pipes/Video
#import "ECVVideoPipe.h"

// Models/Storages/Video
#import "ECVVideoStorage.h"

// Other Sources
@class ECVReadWriteLock;

@interface ECVCaptureDocument : NSDocument </*ECVAudioStorageDelegate, */ECVVideoStorageDelegate>
{
	@private
//	ECVAudioStorage *_audioStorage;
	ECVVideoStorage *_videoStorage;
	ECVReadWriteLock *_lock;
	NSMutableArray *_receivers;
}

@property(assign, getter=isPlaying) BOOL playing;

//@property(readonly) ECVAudioStorage *audioStorage;
@property(readonly) ECVVideoStorage *videoStorage;

- (void)play; // Do not call directly.
- (void)stop;

@end

@protocol ECVAVReceiving

- (void)play;
- (void)stop;
// TODO: Audio.
- (void)receiveVideoFrame:(ECVVideoFrame *)frame;

@end
