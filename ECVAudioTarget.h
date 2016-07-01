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
#import "ECVAVTarget.h"
#import "ECVAudioDevice.h"
#import "ECVCaptureDevice.h"
@class ECVAudioPipe;
@class ECVCaptureDocument;

extern NSString *const ECVCaptureDeviceVolumeDidChangeNotification;

@interface ECVAudioTarget : NSObject <ECVAVTarget, ECVAudioDeviceDelegate>
{
	@private
	ECVCaptureDocument *_captureDocument;
	ECVAudioOutput *_audioOutput;
	AudioStreamBasicDescription _inputDescription;
	BOOL _muted;
	CGFloat _volume;
	BOOL _upconvertsFromMono;

	ECVAudioPipe *_audioPipe;
}

- (ECVCaptureDocument *)captureDocument;
- (void)setCaptureDocument:(ECVCaptureDocument *const)doc;

- (ECVAudioOutput *)audioOutput;
- (void)setAudioOutput:(ECVAudioOutput *const)output;
- (void)setInputBasicDescription:(AudioStreamBasicDescription const)desc;
- (BOOL)isMuted;
- (void)setMuted:(BOOL)flag;
- (CGFloat)volume;
- (void)setVolume:(CGFloat)value;
- (BOOL)upconvertsFromMono;
- (void)setUpconvertsFromMono:(BOOL)flag;

- (void)play;
- (void)stop;

- (void)pushAudioBufferListValue:(NSValue *const)bufferListValue;

@end

@interface ECVCaptureDevice(ECVAudio)

- (ECVAudioInput *)builtInAudioInput;

@end
