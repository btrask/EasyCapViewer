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
#import "ECVPipe.h"

// Models/Pipes/Audio
@class ECVAudioConverter;

@interface ECVAudioPipe : ECVPipe
{
	@private
	ECVAudioConverter *_converter;
}

- (id)initWithAudioSource:(ECVAudioSource *)source;
@property(readonly) id audioSource;
@property(readonly) ECVAudioStorage *audioStorage;

// Input
@property(readonly) AudioStreamBasicDescription inputBasicDescription;

// Output
@property(readonly) AudioStreamBasicDescription outputBasicDescription;

// Options
@property(assign) CGFloat volume;
//@property(assign) BOOL upconvertsFromMono;
// TODO: An audio pipe should represent a SINGLE stream. So when the pipe is created, we should have options for choosing an input stream, and once it exists, we should be able to change which output stream it uses.

@end

@interface ECVAudioPipe(ECVFromSource)

@property(assign) AudioStreamBasicDescription inputBasicDescription;

@end

@interface ECVAudioPipe(ECVFromSource_Thread)

- (void)nextAudioPacket:(id)packet; // TODO: Some sort of input.

@end

@interface ECVAudioPipe(ECVFromStorage)

@property(assign) ECVAudioStorage *audioStorage;

@property(assign) AudioStreamBasicDescription outputBasicDescription;

@end
