/* Copyright (c) 2012, Ben Trask
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE AUTHORS ''AS IS'' AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. */
#import "ECVAudioDevice.h"
#import "ECVCaptureDevice.h"
#import "ECVConfigController.h"

@class ECVAudioInput;
@class ECVAudioOutput;
@class ECVAudioPipe;
@class ECVCaptureDevice;
@class ECVReadWriteLock;

@interface ECVCaptureDocument : NSDocument <ECVCaptureDocumentConfiguring, ECVAudioDeviceDelegate>
{
	@private
	BOOL _paused;

	ECVCaptureDevice *_videoSource;

	ECVReadWriteLock *_windowControllersLock;
	NSMutableArray *_windowControllers2;

	ECVAudioInput *_audioInput;
	ECVAudioOutput *_audioOutput;
	ECVAudioPipe *_audioPreviewingPipe;
	BOOL _muted;
	CGFloat _volume;
	BOOL _upconvertsFromMono;
}

- (ECVCaptureDevice *)videoSource;
- (void)setVideoSource:(ECVCaptureDevice *const)source;
- (NSUserDefaults *)defaults;

- (BOOL)isPaused;
- (void)setPaused:(BOOL const)flag;
- (void)togglePaused;
- (void)play;
- (void)stop;

- (void)workspaceWillSleep:(NSNotification *const)aNotif;

- (ECVAudioInput *)audioInput;
- (void)setAudioInput:(ECVAudioInput *const)target;
- (ECVAudioOutput *)audioOutput;
- (void)setAudioOutput:(ECVAudioOutput *const)output;
- (BOOL)startAudio; // TODO: Use play/stop, merge with video play/stopping.
- (void)stopAudio;

@end

@interface ECVCaptureDevice(ECVAudio)

- (ECVAudioInput *)builtInAudioInput;

@end
