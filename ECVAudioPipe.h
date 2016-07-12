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
#if defined(ECV_ENABLE_AUDIO)
#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudio/CoreAudio.h>

#define ECVFramesPerPacket 1
#define ECVChannelsPerFrame 2
static AudioStreamBasicDescription const ECVStandardAudioStreamBasicDescription = {
	.mSampleRate = 48000.0f,
	.mFormatID = kAudioFormatLinearPCM,
	.mFormatFlags = kLinearPCMFormatFlagIsFloat | kLinearPCMFormatFlagIsPacked,
	.mBytesPerPacket = sizeof(Float32) * ECVChannelsPerFrame * ECVFramesPerPacket,
	.mFramesPerPacket = ECVFramesPerPacket,
	.mBytesPerFrame = sizeof(Float32) * ECVChannelsPerFrame,
	.mChannelsPerFrame = ECVChannelsPerFrame,
	.mBitsPerChannel = sizeof(Float32) * CHAR_BIT,
	.mReserved = 0,
};

@interface ECVAudioPipe : NSObject
{
	@private
	AudioStreamBasicDescription _inputStreamDescription;
	AudioStreamBasicDescription _outputStreamDescription;
	AudioConverterRef _converter;
	CGFloat _volume;
	BOOL _upconvertsFromMono;
	BOOL _dropsBuffers;
	NSLock *_lock;
	NSMutableArray *_unusedBuffers;
	NSMutableArray *_usedBuffers;
}

- (id)initWithInputDescription:(AudioStreamBasicDescription)inputDesc outputDescription:(AudioStreamBasicDescription)outputDesc upconvertFromMono:(BOOL)flag;
@property(readonly) AudioStreamBasicDescription inputStreamDescription;
@property(readonly) AudioStreamBasicDescription outputStreamDescription;
@property(readonly) BOOL upconvertsFromMono;
@property(assign) CGFloat volume;
@property(assign) BOOL dropsBuffers;

@property(readonly) BOOL hasReadyBuffers;
- (void)receiveInputBufferList:(AudioBufferList const *)inputBufferList;
- (void)requestOutputBufferList:(inout AudioBufferList *)outputBufferList;

@end
#endif
