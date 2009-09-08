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
#import "ECVAudioDevice.h"
#import <IOKit/audio/IOAudioDefines.h>

// Other Sources
#import "ECVDebug.h"

AudioBufferList *ECVAudioBufferListCopy(AudioBufferList const *bufferList)
{
	UInt32 i;
	size_t totalDataSize = 0;
	for(i = 0; i < bufferList->mNumberBuffers; i++) totalDataSize += bufferList->mBuffers[i].mDataByteSize;
	size_t const listSize = sizeof(AudioBufferList) + sizeof(AudioBuffer) * (bufferList->mNumberBuffers - 1);
	AudioBufferList *const copy = malloc(listSize + totalDataSize);
	size_t dataOffset = listSize;
	copy->mNumberBuffers = bufferList->mNumberBuffers;
	for(i = 0; i < bufferList->mNumberBuffers; i++) {
		copy->mBuffers[i].mNumberChannels = bufferList->mBuffers[i].mNumberChannels;
		size_t const dataSize = bufferList->mBuffers[i].mDataByteSize;
		copy->mBuffers[i].mDataByteSize = dataSize;
		copy->mBuffers[i].mData = copy + dataOffset;
		memcpy(copy + dataOffset, bufferList->mBuffers[i].mData, dataSize);
		dataOffset += dataSize;
	}
	return copy;
}

static OSStatus ECVAudioDeviceIOProc(AudioDeviceID inDevice, const AudioTimeStamp *inNow, const AudioBufferList *inInputData, const AudioTimeStamp *inInputTime, AudioBufferList *outOutputData, const AudioTimeStamp *inOutputTime, ECVAudioDevice *device)
{
	NSAutoreleasePool *const pool = [[NSAutoreleasePool alloc] init];
	if(device.isInput) [device.delegate audioDevice:device didReceiveInput:inInputData atTime:inInputTime];
	else [device.delegate audioDevice:device didRequestOutput:outOutputData forTime:inOutputTime];
	[pool drain];
	return noErr;
}

@implementation ECVAudioDevice

#pragma mark +ECVAudioDevice

+ (id)defaultInputDevice
{
	AudioDeviceID deviceID = 0;
	UInt32 deviceIDSize = sizeof(deviceID);
	ECVOSStatus(AudioHardwareGetProperty(kAudioHardwarePropertyDefaultInputDevice, &deviceIDSize, &deviceID), ECVRetryDefault);
	return [[[self alloc] initWithDeviceID:deviceID input:YES] autorelease];
}
+ (id)defaultOutputDevice
{
	AudioDeviceID deviceID = 0;
	UInt32 deviceIDSize = sizeof(deviceID);
	ECVOSStatus(AudioHardwareGetProperty(kAudioHardwarePropertyDefaultOutputDevice, &deviceIDSize, &deviceID), ECVRetryDefault);
	return [[[self alloc] initWithDeviceID:deviceID input:NO] autorelease];
}
+ (id)deviceWithUID:(NSString *)UID input:(BOOL)flag
{
	NSParameterAssert(UID);
	AudioDeviceID deviceID = kAudioDeviceUnknown;
	AudioValueTranslation deviceUIDTranslation = {
		&UID,
		sizeof(UID),
		&deviceID,
		sizeof(deviceID)
	};
	UInt32 translationSize = sizeof(deviceUIDTranslation);
	ECVOSStatus(AudioHardwareGetProperty(kAudioHardwarePropertyDeviceForUID, &translationSize, &deviceUIDTranslation), ECVRetryDefault);
	return kAudioDeviceUnknown == deviceID ? nil : [[[self alloc] initWithDeviceID:deviceID input:flag] autorelease];
}
+ (id)deviceWithIODevice:(io_service_t)device input:(BOOL)flag
{
	io_iterator_t iterator = IO_OBJECT_NULL;
	io_service_t subservice = IO_OBJECT_NULL;
	ECVIOReturn(IORegistryEntryCreateIterator(device, kIOServicePlane, kIORegistryIterateRecursively, &iterator), ECVRetryDefault);
	while((subservice = IOIteratorNext(iterator))) if(IOObjectConformsTo(subservice, kIOAudioEngineClassName)) {
		NSString *const UID = [(NSString *)IORegistryEntryCreateCFProperty(subservice, CFSTR(kIOAudioEngineGlobalUniqueIDKey), kCFAllocatorDefault, 0) autorelease];
		return UID ? [self deviceWithUID:UID input:flag] : nil;
	}
ECVGenericError:
ECVNoDeviceError:
	return nil;
}

#pragma mark -ECVAudioDevice

- (id)initWithDeviceID:(AudioDeviceID)deviceID input:(BOOL)flag
{
	NSParameterAssert(kAudioDeviceUnknown != deviceID);
	if((self = [super init])) {
		_deviceID = deviceID;
		_input = flag;

		Float64 rate = 0.0f;
		UInt32 rateSize= sizeof(rate);
		ECVOSStatus(AudioDeviceGetProperty(self.deviceID, 0, self.isInput, kAudioDevicePropertyNominalSampleRate, &rateSize, &rate), ECVRetryDefault);

		AudioValueRange rateRange = {0.0f, 0.0f};
		UInt32 rangeSize = sizeof(rateRange);
		ECVOSStatus(AudioDeviceGetProperty(self.deviceID, 0, self.isInput, kAudioDevicePropertyBufferFrameSizeRange, &rangeSize, &rateRange), ECVRetryDefault);

		UInt32 const size = (UInt32)MIN(MAX(rateRange.mMinimum, roundf(rate / 100.0f)), rateRange.mMaximum); // Using either the minimum or the maximum frame size results in choppy audio. I don't know why the ideal buffer frame size is the 1% of the nominal sample rate, but it's what the MTCoreAudio framework uses and it works.
		ECVOSStatus(AudioDeviceSetProperty(self.deviceID, NULL, 0, self.isInput, kAudioDevicePropertyBufferFrameSize, sizeof(size), &size), ECVRetryDefault);
	}
	return self;
}

#pragma mark -

@synthesize delegate;
@synthesize deviceID = _deviceID;
@synthesize input = _input;

#pragma mark -

- (NSArray *)streams
{
	UInt32 streamIDsSize = 0;
	ECVOSStatus(AudioDeviceGetPropertyInfo(self.deviceID, 0, self.isInput, kAudioDevicePropertyStreams, &streamIDsSize, NULL), ECVRetryDefault);
	AudioStreamID *const streamIDs = malloc(streamIDsSize);
	ECVOSStatus(AudioDeviceGetProperty(self.deviceID, 0, self.isInput, kAudioDevicePropertyStreams, &streamIDsSize, streamIDs), ECVRetryDefault);

	NSUInteger i = 0;
	NSMutableArray *const streams = [NSMutableArray array];
	for(; i < streamIDsSize / sizeof(AudioStreamID); i++) {
		ECVAudioStream *const stream = [[[ECVAudioStream alloc] initWithStreamID:streamIDs[i]] autorelease];
		[streams addObject:stream];
	}

	free(streamIDs);
	return streams;
}

#pragma mark -

- (BOOL)start
{
	if(_procID) return YES;
	if(noErr == AudioDeviceCreateIOProcID(self.deviceID, (AudioDeviceIOProc)ECVAudioDeviceIOProc, self, &_procID)) {
		if(noErr == AudioDeviceStart(self.deviceID, _procID)) return YES;
		[self stop];
	}
	return NO;
}
- (void)stop
{
	if(!_procID) return;
	ECVOSStatus(AudioDeviceStop(self.deviceID, _procID), ECVRetryDefault);
	ECVOSStatus(AudioDeviceDestroyIOProcID(self.deviceID, _procID), ECVRetryDefault);
	_procID = NULL;
}

#pragma mark -<NSObject>

- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ %p: %d (%@)>", [self class], self, self.deviceID, self.isInput ? @"In" : @"Out"];
}

@end

@implementation NSObject(ECVAudioDeviceDelegate)

- (void)audioDevice:(ECVAudioDevice *)sender didReceiveInput:(AudioBufferList const *)bufferList atTime:(AudioTimeStamp const *)time {}
- (void)audioDevice:(ECVAudioDevice *)sender didRequestOutput:(inout AudioBufferList *)bufferList forTime:(AudioTimeStamp const *)time {}

@end

@implementation ECVAudioStream

#pragma mark -ECVAudioStream

- (id)initWithStreamID:(AudioStreamID)streamID
{
	if((self = [super init])) {
		_streamID = streamID;
	}
	return self;
}

#pragma mark -

@synthesize streamID = _streamID;

#pragma mark -

- (AudioStreamBasicDescription)basicDescription
{
	AudioStreamBasicDescription description;
	UInt32 descriptionSize = sizeof(description);
	ECVOSStatus(AudioStreamGetProperty(self.streamID, 0, kAudioStreamPropertyVirtualFormat, &descriptionSize, &description), ECVRetryDefault);
	return description;
}

#pragma mark -<NSObject>

- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ %p: %d>", [self class], self, self.streamID];
}

@end
