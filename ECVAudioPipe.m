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
#import <vecLib/vecLib.h>

// Other Sources
#import "ECVDebug.h"

@interface ECVAudioPipe(Private)

- (void)_fillOutput:(AudioBufferList *)bufferList;

@end

static OSStatus ECVAudioConverterComplexInputDataProc(AudioConverterRef inAudioConverter, UInt32 *ioNumberDataPackets, AudioBufferList *bufferList, AudioStreamPacketDescription **outDataPacketDescription, ECVAudioPipe *pipe)
{
	[pipe _fillOutput:bufferList];
	return noErr;
}

@implementation ECVAudioPipe

#pragma mark -ECVAudioPipe

- (id)initWithInputDescription:(AudioStreamBasicDescription)inputDesc outputDescription:(AudioStreamBasicDescription)outputDesc
{
	if((self = [super init])) {
		_inputStreamDescription = inputDesc;
		_volume = 1.0f;
		_unusedBuffers = [[NSMutableArray alloc] init];
		_usedBuffers = [[NSMutableArray alloc] init];

		ECVOSStatus(AudioConverterNew(&inputDesc, &outputDesc, &_converter));
		UInt32 quality = kAudioConverterQuality_Max;
		ECVOSStatus(AudioConverterSetProperty(_converter, kAudioConverterSampleRateConverterQuality, sizeof(quality), &quality));
		UInt32 primeMethod = kConverterPrimeMethod_Normal;
		ECVOSStatus(AudioConverterSetProperty(_converter, kAudioConverterPrimeMethod, sizeof(primeMethod), &primeMethod));
	}
	return self;
}
@synthesize volume = _volume;
- (void)clearBuffer
{
	[_unusedBuffers removeAllObjects];
}

#pragma mark -

- (BOOL)receiveInput:(AudioBufferList const *)bufferList atTime:(AudioTimeStamp const *)time
{
	NSUInteger i = 0;
	float const volume = pow(_volume, 2);
	for(; i < bufferList->mNumberBuffers; i++) {
		size_t const length = bufferList->mBuffers[i].mDataByteSize;
		if(!length) continue;
		void *const bytes = malloc(length);
		if(!bytes) continue;
		vDSP_vsmul(bufferList->mBuffers[i].mData, 1, &volume, bytes, 1, length / sizeof(float));
		[_unusedBuffers insertObject:[NSMutableData dataWithBytesNoCopy:bytes length:length freeWhenDone:YES] atIndex:0];
	}
	return YES;
}
- (BOOL)requestOutput:(inout AudioBufferList *)bufferList forTime:(AudioTimeStamp const *)time
{
	[_usedBuffers removeAllObjects];
	if(!bufferList || !bufferList->mNumberBuffers) return NO;
	UInt32 packetCount = bufferList->mBuffers[0].mDataByteSize / _inputStreamDescription.mBytesPerPacket;
	return AudioConverterFillComplexBuffer(_converter, (AudioConverterComplexInputDataProc)ECVAudioConverterComplexInputDataProc, self, &packetCount, bufferList, NULL) == noErr;
}

#pragma mark -ECVAudioPipe(Private)

- (void)_fillOutput:(AudioBufferList *)bufferList
{
	NSUInteger i = 0;
	for(; i < bufferList->mNumberBuffers; i++) {
		NSMutableData *const data = [_unusedBuffers lastObject];
		bufferList->mBuffers[i].mDataByteSize = [data length];
		bufferList->mBuffers[i].mData = [data mutableBytes];
		if(!data) continue;
		[_usedBuffers addObject:data];
		[_unusedBuffers removeLastObject];
	}
}

#pragma mark -NSObject

- (void)dealloc
{
	ECVOSStatus(AudioConverterDispose(_converter));
	[_unusedBuffers release];
	[_usedBuffers release];
	[super dealloc];
}

@end
