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
#import "ECVAudioPipe.h"
#import <CoreAudio/CoreAudio.h>

// Other Sources
#import "ECVDebug.h"

static OSStatus ECVAudioConverterComplexInputDataProc(AudioConverterRef inAudioConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData, AudioStreamPacketDescription **outDataPacketDescription, ECVAudioPipe *pipe)
{
	NSAutoreleasePool *const pool = [[NSAutoreleasePool alloc] init];
	OSStatus const r = [pipe fillComplexBuffer:ioData numberOfPackets:ioNumberDataPackets] ? noErr : -1;
	[pool drain];
	return r;
}

@implementation ECVAudioPipe

#pragma mark -ECVAudioPipe

- (id)initWithInputDescription:(AudioStreamBasicDescription)inputDesc outputDescription:(AudioStreamBasicDescription)outputDesc
{
	if((self = [super init])) {
		_inputStreamDescription = inputDesc;
		ECVOSStatus(AudioConverterNew(&inputDesc, &outputDesc, &_converter), ECVRetryDefault);

		UInt32 quality = kAudioConverterQuality_Max;
		ECVOSStatus(AudioConverterSetProperty(_converter, kAudioConverterSampleRateConverterQuality, sizeof(quality), &quality), ECVRetryDefault);
		UInt32 primeMethod = kConverterPrimeMethod_None;
		ECVOSStatus(AudioConverterSetProperty(_converter, kAudioConverterPrimeMethod, sizeof(primeMethod), &primeMethod), ECVRetryDefault);

		UInt32 const bufferCount = 100; // Seems reasonable?
		_bufferList = malloc(sizeof(AudioBufferList) + sizeof(AudioBuffer) * (bufferCount - 1));
		_bufferList->mNumberBuffers = bufferCount;
	}
	return self;
}
- (void)clearBuffer
{
	UInt32 i = 0;
	for(; i < _bufferList->mNumberBuffers; i++) {
		_bufferList->mBuffers[i].mNumberChannels = 0;
		_bufferList->mBuffers[i].mDataByteSize = 0;
		_bufferList->mBuffers[i].mData = NULL;
	}
	_writeIndex = 0;
	_readIndex = 0;
}

#pragma mark -

- (BOOL)receiveInput:(AudioBufferList const *)bufferList atTime:(AudioTimeStamp const *)time
{
	UInt32 i = 0;
	for(; i < bufferList->mNumberBuffers; i++, _writeIndex = (_writeIndex + 1) % _bufferList->mNumberBuffers) {
		_bufferList->mBuffers[_writeIndex].mNumberChannels = bufferList->mBuffers[i].mNumberChannels;
		_bufferList->mBuffers[_writeIndex].mDataByteSize = bufferList->mBuffers[i].mDataByteSize;
		_bufferList->mBuffers[_writeIndex].mData = bufferList->mBuffers[i].mData;
	}
	return YES;
}
- (BOOL)requestOutput:(inout AudioBufferList *)bufferList forTime:(AudioTimeStamp const *)time
{
	if(!bufferList || !bufferList->mNumberBuffers) return NO;
	if(!_bufferList || !_bufferList->mNumberBuffers) return NO;
	UInt32 packetCount = bufferList->mBuffers[0].mDataByteSize / _inputStreamDescription.mBytesPerPacket;
	return AudioConverterFillComplexBuffer(_converter, (AudioConverterComplexInputDataProc)ECVAudioConverterComplexInputDataProc, self, &packetCount, bufferList, NULL) == noErr;
}
- (BOOL)fillComplexBuffer:(AudioBufferList *)bufferList numberOfPackets:(inout UInt32 *)count
{
	NSUInteger i = 0;
	for(; i < MIN(*count, bufferList->mNumberBuffers); i++, _readIndex = (_readIndex + 1) % _bufferList->mNumberBuffers) {
		bufferList->mBuffers[i].mDataByteSize = _bufferList->mBuffers[i].mDataByteSize;
		bufferList->mBuffers[i].mData = _bufferList->mBuffers[i].mData;
	}
	return YES;
}

#pragma mark -NSObject

- (void)dealloc
{
	ECVOSStatus(AudioConverterDispose(_converter), ECVRetryDefault);
	if(_bufferList) free(_bufferList);
	[super dealloc];
}

@end
