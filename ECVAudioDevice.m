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
#import "ECVAudioDevice.h"
#import <IOKit/audio/IOAudioDefines.h>

// Other Sources
#import "ECVDebug.h"

NSString *const ECVAudioHardwareDevicesDidChangeNotification = @"ECVAudioHardwareDevicesDidChange";

static OSStatus ECVAudioObjectPropertyListenerProc(AudioObjectID const inObjectID, UInt32 const inNumberAddresses, AudioObjectPropertyAddress const inAddresses[], id const obj)
{
	for(UInt32 i = 0; i < inNumberAddresses; ++i) {
		if(kAudioHardwarePropertyDevices != inAddresses[i].mSelector) continue;
		[[NSNotificationCenter defaultCenter] postNotificationName:ECVAudioHardwareDevicesDidChangeNotification object:obj];
		break;
	}
	return noErr;
}
static OSStatus ECVAudioDeviceIOProc(AudioDeviceID const inDevice, AudioTimeStamp const *const inNow, AudioBufferList const *const inInputData, AudioTimeStamp const *const inInputTime, AudioBufferList *const outOutputData, AudioTimeStamp const *const inOutputTime, id const device)
{
	NSAutoreleasePool *const pool = [[NSAutoreleasePool alloc] init];
	if([device isInput]) [[device delegate] audioInput:device didReceiveBufferList:inInputData atTime:inInputTime];
	else [[device delegate] audioOutput:device didRequestBufferList:outOutputData forTime:inOutputTime];
	[pool drain];
	return noErr;
}

@implementation ECVAudioDevice

#pragma mark +NSObject

+ (void)initialize
{
	if([ECVAudioDevice class] != self) return;
	AudioObjectPropertyAddress const addr = {
		.mSelector = kAudioHardwarePropertyDevices,
		.mScope = kAudioObjectPropertyScopeGlobal,
		.mElement = kAudioObjectPropertyElementMaster,
	};
	ECVOSStatus(AudioObjectAddPropertyListener(kAudioObjectSystemObject, &addr, (AudioObjectPropertyListenerProc)ECVAudioObjectPropertyListenerProc, self));
}
+ (id)allocWithZone:(NSZone *)zone
{
	NSAssert([self respondsToSelector:@selector(isInput)], @"ECVAudioDevice is abstract.");
	return [super allocWithZone:zone];
}

#pragma mark +ECVAudioDevice

+ (NSArray *)allDevices
{
	NSMutableArray *const devices = [NSMutableArray array];
	UInt32 size = 0;
	AudioObjectPropertyAddress const addr = {
		.mSelector = kAudioHardwarePropertyDevices,
		.mScope = [self isInput] ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,
		.mElement = kAudioObjectPropertyElementMaster,
	};
	ECVOSStatus(AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &addr, 0, NULL, &size));
	if(!size) return devices;
	AudioDeviceID *const deviceIDs = malloc(size);
	if(!deviceIDs) return devices;
	ECVOSStatus(AudioObjectGetPropertyData(kAudioObjectSystemObject, &addr, 0, NULL, &size, deviceIDs));
	NSUInteger i = 0;
	for(; i < size / sizeof(AudioDeviceID); i++) {
		ECVAudioDevice *const device = [[[self alloc] initWithDeviceID:deviceIDs[i]] autorelease];
		if(device) [devices addObject:device];
	}
	free(deviceIDs);
	return devices;
}
+ (id)defaultDevice
{
	AudioDeviceID deviceID = kAudioDeviceUnknown;
	UInt32 deviceIDSize = sizeof(deviceID);
	AudioObjectPropertyAddress const addr = {
		.mSelector = [self isInput] ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
		.mScope = [self isInput] ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,
		.mElement = kAudioObjectPropertyElementMaster,
	};
	ECVOSStatus(AudioObjectGetPropertyData(kAudioObjectSystemObject, &addr, 0, NULL, &deviceIDSize, &deviceID));
	return [[[self alloc] initWithDeviceID:deviceID] autorelease];
}
+ (id)deviceWithUID:(NSString *)UID
{
	NSParameterAssert(UID);
	AudioDeviceID deviceID = kAudioDeviceUnknown;
	AudioValueTranslation deviceUIDTranslation = {
		&UID,
		sizeof(UID),
		&deviceID,
		sizeof(deviceID),
	};
	UInt32 translationSize = sizeof(deviceUIDTranslation);
	AudioObjectPropertyAddress const addr = {
		.mSelector = kAudioHardwarePropertyDeviceForUID,
		.mScope = [self isInput] ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,
		.mElement = kAudioObjectPropertyElementMaster,
	};
	ECVOSStatus(AudioObjectGetPropertyData(kAudioObjectSystemObject, &addr, 0, NULL, &translationSize, &deviceUIDTranslation));
	return [[[self alloc] initWithDeviceID:deviceID] autorelease];
}
+ (id)deviceWithIODevice:(io_service_t)device
{
	io_iterator_t iterator = IO_OBJECT_NULL;
	io_service_t subservice = IO_OBJECT_NULL;
	ECVIOReturn(IORegistryEntryCreateIterator(device, kIOServicePlane, kIORegistryIterateRecursively, &iterator));
	while((subservice = IOIteratorNext(iterator))) if(IOObjectConformsTo(subservice, kIOAudioEngineClassName)) {
		NSString *const UID = [(NSString *)IORegistryEntryCreateCFProperty(subservice, CFSTR(kIOAudioEngineGlobalUniqueIDKey), kCFAllocatorDefault, 0) autorelease];
		return UID ? [self deviceWithUID:UID] : nil;
	}
ECVGenericError:
ECVNoDeviceError:
	return nil;
}

#pragma mark -ECVAudioDevice

- (id)initWithDeviceID:(AudioDeviceID)deviceID
{
	if((self = [super init])) {
		if(kAudioDeviceUnknown == deviceID) {
			[self release];
			return nil;
		}

		_deviceID = deviceID;

		Float64 rate = 0.0f;
		UInt32 rateSize= sizeof(rate);
		AudioObjectPropertyAddress const sampleRateAddr = {
			.mSelector = kAudioDevicePropertyNominalSampleRate,
			.mScope = [self isInput] ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,
			.mElement = kAudioObjectPropertyElementMaster,
		};
		ECVOSStatus(AudioObjectGetPropertyData([self deviceID], &sampleRateAddr, 0, NULL, &rateSize, &rate));

		AudioValueRange rateRange = {0.0f, 0.0f};
		UInt32 rangeSize = sizeof(rateRange);
		AudioObjectPropertyAddress const bufferFrameSizeRangeAddr = {
			.mSelector = kAudioDevicePropertyBufferFrameSizeRange,
			.mScope = [self isInput] ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,
			.mElement = kAudioObjectPropertyElementMaster,
		};
		ECVOSStatus(AudioObjectGetPropertyData([self deviceID], &bufferFrameSizeRangeAddr, 0, NULL, &rangeSize, &rateRange));

		UInt32 const size = (UInt32)CLAMP(rateRange.mMinimum, roundf(rate / 100.0f), rateRange.mMaximum); // Using either the minimum or the maximum frame size results in choppy audio. I don't know why the ideal buffer frame size is the 1% of the nominal sample rate, but it's what the MTCoreAudio framework uses and it works.
		AudioObjectPropertyAddress const bufferFrameSizeAddr = {
			.mSelector = kAudioDevicePropertyBufferFrameSize,
			.mScope = [self isInput] ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,
			.mElement = kAudioObjectPropertyElementMaster,
		};
		ECVOSStatus(AudioObjectSetPropertyData([self deviceID], &bufferFrameSizeAddr, 0, NULL, sizeof(size), &size));

		if(![[self streams] count]) {
			[self release];
			return nil;
		}
	}
	return self;
}

#pragma mark -

- (NSObject<ECVAudioDeviceDelegate> *)delegate
{
	return delegate;
}
- (void)setDelegate:(NSObject<ECVAudioDeviceDelegate> *)obj
{
	delegate = obj;
}
- (AudioDeviceID)deviceID
{
	return _deviceID;
}
- (BOOL)isInput
{
	return [[self class] isInput];
}
- (NSString *)UID
{
	NSString *UID = nil;
	UInt32 UIDSize = sizeof(UID);
	AudioObjectPropertyAddress const addr = {
		.mSelector = kAudioDevicePropertyDeviceUID,
		.mScope = [self isInput] ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,
		.mElement = kAudioObjectPropertyElementMaster,
	};
	ECVOSStatus(AudioObjectGetPropertyData([self deviceID], &addr, 0, NULL, &UIDSize, &UID));
	return [UID autorelease];
}

#pragma mark -

- (NSString *)name
{
	if(_name) return [[_name retain] autorelease];
	NSString *name = nil;
	UInt32 nameSize = sizeof(name);
	AudioObjectPropertyAddress const addr = {
		.mSelector = kAudioDevicePropertyDeviceNameCFString,
		.mScope = [self isInput] ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,
		.mElement = kAudioObjectPropertyElementMaster,
	};
	ECVOSStatus(AudioObjectGetPropertyData([self deviceID], &addr, 0, NULL, &nameSize, &name));
	return [name autorelease];
}
- (void)setName:(NSString *)name
{
	if(BTEqualObjects(_name, name)) return;
	[_name release];
	_name = [name copy];
}
- (NSArray *)streams
{
	UInt32 streamIDsSize = 0;
	AudioObjectPropertyAddress const addr = {
		.mSelector = kAudioDevicePropertyStreams,
		.mScope = [self isInput] ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,
		.mElement = kAudioObjectPropertyElementMaster,
	};
	ECVOSStatus(AudioObjectGetPropertyDataSize([self deviceID], &addr, 0, NULL, &streamIDsSize));
	AudioStreamID *const streamIDs = malloc(streamIDsSize);
	ECVOSStatus(AudioObjectGetPropertyData([self deviceID], &addr, 0, NULL, &streamIDsSize, streamIDs));
	NSUInteger i = 0;
	NSMutableArray *const streams = [NSMutableArray array];
	for(; i < streamIDsSize / sizeof(AudioStreamID); i++) {
		ECVAudioStream *const stream = [[[ECVAudioStream alloc] initWithStreamID:streamIDs[i]] autorelease];
		[streams addObject:stream];
	}
	free(streamIDs);
	return streams;
}
- (ECVAudioStream *)stream
{
	NSArray *const streams = [self streams];
	return [streams count] ? [streams objectAtIndex:0] : nil;
}

#pragma mark -

- (BOOL)start
{
	if(_procID) return YES;
	if(noErr == AudioDeviceCreateIOProcID([self deviceID], (AudioDeviceIOProc)ECVAudioDeviceIOProc, self, &_procID)) {
		if(noErr == AudioDeviceStart([self deviceID], _procID)) return YES;
		[self stop];
	}
	return NO;
}
- (void)stop
{
	if(!_procID) return;
	ECVOSStatus(AudioDeviceStop([self deviceID], _procID));
	ECVOSStatus(AudioDeviceDestroyIOProcID([self deviceID], _procID));
	_procID = NULL;
}

#pragma mark -NSObject

- (void)dealloc
{
	[self stop];
	[_name release];
	[super dealloc];
}

#pragma mark -<NSObject>

- (NSUInteger)hash
{
	return [[self class] hash] ^ _deviceID;
}
- (BOOL)isEqual:(id)obj
{
	return [obj isMemberOfClass:[self class]] && [(ECVAudioDevice *)obj deviceID] == [self deviceID];
}

#pragma mark -

- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ %p: %@ (%ld, %@)>", [self class], self, [self name], [self deviceID], [self isInput] ? @"In" : @"Out"];
}

@end

@implementation ECVAudioInput

#pragma mark +ECVAudioDevice(ECVAbstract)

+ (BOOL)isInput
{
	return YES;
}

@end

@implementation ECVAudioOutput

#pragma mark +ECVAudioDevice(ECVAbstract)

+ (BOOL)isInput
{
	return NO;
}

@end

@implementation NSObject(ECVAudioDeviceDelegate)

- (void)audioInput:(ECVAudioInput *const)sender didReceiveBufferList:(AudioBufferList const *const)bufferList atTime:(AudioTimeStamp const *const)t {}
- (void)audioOutput:(ECVAudioOutput *const)sender didRequestBufferList:(inout AudioBufferList *const)bufferList forTime:(AudioTimeStamp const *const)t {}

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
- (AudioStreamID)streamID
{
	return _streamID;
}

#pragma mark -

- (AudioStreamBasicDescription)basicDescription
{
	AudioStreamBasicDescription description;
	UInt32 descriptionSize = sizeof(description);
	AudioObjectPropertyAddress const addr = {
		.mSelector = kAudioStreamPropertyVirtualFormat,
		.mScope = kAudioObjectPropertyScopeGlobal,
		.mElement = kAudioObjectPropertyElementMaster,
	};
	ECVOSStatus(AudioObjectGetPropertyData([self streamID], &addr, 0, NULL, &descriptionSize, &description));
	return description;
}

#pragma mark -<NSObject>

- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ %p: %ld>", [self class], self, [self streamID]];
}

@end
