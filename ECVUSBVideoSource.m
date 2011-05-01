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
#import "ECVUSBVideoSource.h"
#import <IOKit/IOCFPlugIn.h>
#import <IOKit/IOMessage.h>
#import <mach/mach_time.h>

// Models/Devices/Video/USB
#import "ECVUSBTransferList.h"

// Other Sources
#import "ECVDebug.h"

#define ECVNanosecondsPerMillisecond 1e6

#define OR(a, b) ({__typeof__(a) __a = (a); (__a ? __a : (b));})

typedef struct {
	UInt8 direction;
	UInt8 pipeNumber;
	UInt8 transferType;
	UInt16 frameRequestSize;
	UInt8 millisecondInterval;
} ECVPipeProperties;

static IONotificationPortRef ECVNotificationPort = NULL;
static NSMutableArray *ECVRegisteredClasses = nil;
static NSMutableArray *ECVNotifications = nil;

static void ECVSourceAdded(Class sourceClass, io_iterator_t iterator)
{
	io_service_t service = IO_OBJECT_NULL;
	while((service = IOIteratorNext(iterator))) {
		ECVUSBVideoSource *const source = [[[sourceClass alloc] initWithService:service] autorelease]; // TODO: Find an existing inactive source, if possible. kUSBSerialNumberStringIndex might help.
		[source setActive:YES];
		IOObjectRelease(service);
	}
}
static void ECVDoNothing(void *refcon, IOReturn result, void *arg0) {}

@interface ECVUSBVideoSource(Private)

+ (void)_workspaceDidWake:(NSNotification *)aNotif;
+ (void)_registerClass;

- (ECVPipeProperties)_propertiesForPipe:(UInt8)pipeRef;
- (UInt32)_microsecondsInFrame;
- (UInt64)_currentFrameNumber;

- (BOOL)_keepReading;
- (void)_read;
- (BOOL)_readTransfer:(inout ECVUSBTransfer *)transfer numberOfMicroframes:(NSUInteger)numberOfMicroframes pipeRef:(UInt8)pipe frameNumber:(inout UInt64 *)frameNumber microsecondsInFrame:(UInt64)microsecondsInFrame millisecondInterval:(UInt8)millisecondInterval;
- (BOOL)_parseTransfer:(inout ECVUSBTransfer *)transfer numberOfMicroframes:(NSUInteger)numberOfMicroframes frameRequestSize:(NSUInteger)frameRequestSize millisecondInterval:(UInt8)millisecondInterval;
- (void)_parseFrame:(inout volatile IOUSBLowLatencyIsocFrame *)frame bytes:(void const *)bytes previousFrame:(IOUSBLowLatencyIsocFrame *)previous millisecondInterval:(UInt8)millisecondInterval;

@end

@implementation ECVUSBVideoSource

#pragma mark +ECVUSBVideoSource

+ (NSDictionary *)matchingDictionary
{
	NSMutableDictionary *const matchingDict = [(NSMutableDictionary *)IOServiceMatching(kIOUSBDeviceClassName) autorelease];
	[matchingDict addEntriesFromDictionary:[[self sourceDictionary] objectForKey:@"ECVMatchingDictionary"]];
	return matchingDict;
}
+ (IOUSBDeviceInterface320 **)USBDeviceWithService:(io_service_t)service
{
	uint32_t busy;
	(void)ECVIOReturn2(IOServiceGetBusyState(service, &busy));
	if(busy) {
		ECVLog(ECVError, @"Device busy and cannot be accessed. (Try restarting.)");
		return NULL; // We can't solve it, so just bail.
	}

	SInt32 ignored = 0;
	IOCFPlugInInterface **devicePlugInInterface = NULL;
	(void)ECVIOReturn2(IOCreatePlugInInterfaceForService(service, kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID, &devicePlugInInterface, &ignored));

	IOUSBDeviceInterface320 **device = NULL;
	(*devicePlugInInterface)->QueryInterface(devicePlugInInterface, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID320), (LPVOID)&device);

	(*devicePlugInInterface)->Release(devicePlugInInterface);

	return device;
}
+ (IOUSBInterfaceInterface300 **)USBInterfaceWithDevice:(IOUSBDeviceInterface320 **)device
{
	IOUSBFindInterfaceRequest interfaceRequest = {
		kIOUSBFindInterfaceDontCare,
		kIOUSBFindInterfaceDontCare,
		kIOUSBFindInterfaceDontCare,
		kIOUSBFindInterfaceDontCare,
	};
	io_iterator_t interfaceIterator = IO_OBJECT_NULL;
	(void)ECVIOReturn2((*device)->CreateInterfaceIterator(device, &interfaceRequest, &interfaceIterator));
	io_service_t const service = IOIteratorNext(interfaceIterator);
	NSParameterAssert(service);

	SInt32 ignored = 0;
	IOCFPlugInInterface **interfacePlugInInterface = NULL;
	(void)ECVIOReturn2(IOCreatePlugInInterfaceForService(service, kIOUSBInterfaceUserClientTypeID, kIOCFPlugInInterfaceID, &interfacePlugInInterface, &ignored));

	IOUSBInterfaceInterface300 **interface = NULL;
	(*interfacePlugInInterface)->QueryInterface(interfacePlugInInterface, CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID300), (LPVOID)&interface);

	(*interfacePlugInInterface)->Release(interfacePlugInInterface);
	IOObjectRelease(service);

	return interface;
}

#pragma mark +ECVUSBVideoSource(Private)

+ (void)_workspaceDidWake:(NSNotification *)aNotif
{
	for(NSNumber *const notif in ECVNotifications) IOObjectRelease([notif unsignedIntValue]);
	[ECVNotifications removeAllObjects];
	for(Class const class in ECVRegisteredClasses) [class _registerClass];
}
+ (void)_registerClass
{
	NSDictionary *const matchingDict = [self matchingDictionary];
	io_iterator_t iterator = IO_OBJECT_NULL;
	(void)ECVIOReturn2(IOServiceAddMatchingNotification(ECVNotificationPort, kIOFirstMatchNotification, (CFDictionaryRef)[matchingDict retain], (IOServiceMatchingCallback)ECVSourceAdded, self, &iterator));
	ECVSourceAdded(self, iterator);
	[ECVNotifications addObject:[NSNumber numberWithUnsignedInt:iterator]];
}

#pragma mark +ECVSource

+ (void)registerClass
{
	if([ECVRegisteredClasses indexOfObjectIdenticalTo:self] == NSNotFound) {
		[ECVRegisteredClasses addObject:self];
		[self _registerClass];
	}
	[super registerClass];
}

#pragma mark +NSObject

+ (void)initialize
{
	if([ECVUSBVideoSource class] != self) return;
	ECVNotificationPort = IONotificationPortCreate(kIOMasterPortDefault);
	ECVNotifications = [[NSMutableArray alloc] init];
	ECVRegisteredClasses = [[NSMutableArray alloc] init];
	CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(ECVNotificationPort), kCFRunLoopDefaultMode);
	[[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(_workspaceDidWake:) name:NSWorkspaceDidWakeNotification object:[NSWorkspace sharedWorkspace]];
}

#pragma mark -ECVUSBVideoSource

- (id)initWithService:(io_service_t)service
{
	if((self = [super init])) {
		_service = service;
		IOObjectRetain(_service);
		(void)ECVIOReturn2(IORegistryEntryCreateCFProperties(_service, (CFMutableDictionaryRef *)&_properties, kCFAllocatorDefault, kNilOptions));
		_readThreadLock = [[NSLock alloc] init];
		_readLock = [[NSLock alloc] init];
		// TODO: Watch for the source being disconnected.
	}
	return self;
}

#pragma mark -

@synthesize service = _service;
@synthesize USBDevice = _USBDevice;
@synthesize USBInterface = _USBInterface;

#pragma mark -

- (ECVUSBTransferList *)transferListWithFrameRequestSize:(NSUInteger)frameRequestSize
{
	return [[[ECVUSBTransferList alloc] initWithInterface:[self USBInterface] numberOfTransfers:32 microframesPerTransfer:32 frameRequestSize:frameRequestSize] autorelease];
}
- (id)valueForProperty:(char const *)nullTerminatedCString
{
	return [_properties objectForKey:[NSString stringWithUTF8String:nullTerminatedCString]];
}

#pragma mark -

- (BOOL)setAlternateInterface:(UInt8)alternateSetting
{
	IOReturn const err = (*_USBInterface)->SetAlternateInterface(_USBInterface, alternateSetting);
	switch(err) {
		case kIOReturnSuccess: return YES;
		case kIOReturnNoDevice:
		case kIOReturnNotResponding: return NO;
	}
	(void)ECVIOReturn2(err);
	return NO;
}
- (BOOL)controlRequestWithType:(u_int8_t)type request:(u_int8_t)request value:(u_int16_t)v index:(u_int16_t)i length:(u_int16_t)length data:(void *)data
{
	IOUSBDevRequest r = { type, request, v, i, length, data, 0 };
	IOReturn const err = (*_USBInterface)->ControlRequest(_USBInterface, 0, &r);
	switch(err) {
		case kIOReturnSuccess: return YES;
		case kIOUSBPipeStalled: (void)ECVIOReturn2((*_USBInterface)->ClearPipeStall(_USBInterface, 0)); return YES;
		case kIOReturnNotResponding: return NO;
	}
	(void)ECVIOReturn2(err);
	return NO;
}
- (BOOL)writeIndex:(u_int16_t)i value:(u_int16_t)v
{
	return [self controlRequestWithType:USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice) request:kUSBRqClearFeature value:v index:i length:0 data:NULL];
}
- (BOOL)readIndex:(u_int16_t)i value:(out u_int8_t *)outValue
{
	u_int8_t v = 0;
	BOOL const r = [self controlRequestWithType:USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice) request:kUSBRqGetStatus value:0 index:i length:sizeof(v) data:&v];
	if(outValue) *outValue = v;
	return r;
}
- (BOOL)setFeatureAtIndex:(u_int16_t)i
{
	return [self controlRequestWithType:USBmakebmRequestType(kUSBOut, kUSBStandard, kUSBDevice) request:kUSBRqSetFeature value:0 index:i length:0 data:NULL];
}

#pragma mark -ECVUSBVideoSource(Private)

- (ECVPipeProperties)_propertiesForPipe:(UInt8)pipeRef
{
	ECVPipeProperties p = {
		.direction = kUSBNone,
		.pipeNumber = 0,
		.transferType = kUSBAnyType,
		.frameRequestSize = 0,
		.millisecondInterval = 0,
	};
	(void)ECVIOReturn2((*_USBInterface)->GetPipeProperties(_USBInterface, pipeRef, &p.direction, &p.pipeNumber, &p.transferType, &p.frameRequestSize, &p.millisecondInterval));
	return p;
}
- (UInt32)_microsecondsInFrame
{
	UInt32 microsecondsInFrame = 0;
	(void)ECVIOReturn2((*_USBInterface)->GetFrameListTime(_USBInterface, &microsecondsInFrame));
	return microsecondsInFrame;
}
- (UInt64)_currentFrameNumber
{
	UInt64 currentFrameNumber = 0;
	AbsoluteTime atTimeIgnored;
	(void)ECVIOReturn2((*_USBInterface)->GetBusFrameNumber(_USBInterface, &currentFrameNumber, &atTimeIgnored));
	return currentFrameNumber;
}

#pragma mark -

- (BOOL)_keepReading
{
	[_readLock lock];
	BOOL const read = _read;
	[_readLock unlock];
	return read;
}
- (void)_read
{
	NSAutoreleasePool *const pool = [[NSAutoreleasePool alloc] init];
	[_readThreadLock lock];
	if([self _keepReading]) {
		ECVLog(ECVNotice, @"Starting.");

		IOReturn err = kIOReturnSuccess;
		err = OR(err, (_USBDevice = [[self class] USBDeviceWithService:[self service]]) ? kIOReturnSuccess : kIOReturnError);

		err = OR(err, ECVIOReturn2((*_USBDevice)->USBDeviceOpen(_USBDevice)));
		err = OR(err, ECVIOReturn2((*_USBDevice)->ResetDevice(_USBDevice)));

		IOUSBConfigurationDescriptorPtr configurationDescription = NULL;
		err = OR(err, ECVIOReturn2((*_USBDevice)->GetConfigurationDescriptorPtr(_USBDevice, 0, &configurationDescription)));
		err = OR(err, ECVIOReturn2((*_USBDevice)->SetConfiguration(_USBDevice, configurationDescription->bConfigurationValue)));

		err = OR(err, (_USBInterface = [[self class] USBInterfaceWithDevice:_USBDevice]) ? kIOReturnSuccess : kIOReturnError);

		err = OR(err, ECVIOReturn2((*_USBInterface)->USBInterfaceOpenSeize(_USBInterface)));

		CFRunLoopSourceRef eventSource = NULL;
		err = OR(err, ECVIOReturn2((*_USBInterface)->CreateInterfaceAsyncEventSource(_USBInterface, &eventSource)));

		if(err) {
			// Do nothing.
		} else if([self _microsecondsInFrame] > [self maximumMicrosecondsInFrame]) {
			ECVLog(ECVError, @"USB bus too slow (%lu > %lu).", (unsigned long)[self _microsecondsInFrame], (unsigned long)[self maximumMicrosecondsInFrame]);
		} else {
			[self read];
		}

		if(eventSource) CFRelease(eventSource);
		if(_USBInterface) (*_USBInterface)->Release(_USBInterface);
		if(_USBDevice) (*_USBDevice)->USBDeviceClose(_USBDevice);
		if(_USBDevice) (*_USBDevice)->Release(_USBDevice);
		_USBInterface = NULL;
		_USBDevice = NULL;

		ECVLog(ECVNotice, @"Stopping.");
	}
	[_readThreadLock unlock];
	[pool drain];
}
- (BOOL)_readTransfer:(inout ECVUSBTransfer *)transfer numberOfMicroframes:(NSUInteger)numberOfMicroframes pipeRef:(UInt8)pipe frameNumber:(inout UInt64 *)frameNumber microsecondsInFrame:(UInt64)microsecondsInFrame millisecondInterval:(UInt8)millisecondInterval
{
	if(kIOReturnSuccess != ECVIOReturn2((*_USBInterface)->LowLatencyReadIsochPipeAsync(_USBInterface, pipe, transfer->data, *frameNumber, numberOfMicroframes, millisecondInterval, transfer->frames, ECVDoNothing, NULL))) return NO;
	*frameNumber += numberOfMicroframes / (kUSBFullSpeedMicrosecondsInFrame / microsecondsInFrame);
	return YES;
}
- (BOOL)_parseTransfer:(inout ECVUSBTransfer *)transfer numberOfMicroframes:(NSUInteger)numberOfMicroframes frameRequestSize:(NSUInteger)frameRequestSize millisecondInterval:(UInt8)millisecondInterval
{
	NSUInteger i;
	for(i = 0; i < numberOfMicroframes; ++i) {
		IOUSBLowLatencyIsocFrame *const frame = transfer->frames + i;
		UInt8 const *const bytes = transfer->data + i * frameRequestSize;
		IOUSBLowLatencyIsocFrame *const previous = i ? transfer->frames + i - 1 : NULL;
		[self _parseFrame:frame bytes:bytes previousFrame:previous millisecondInterval:millisecondInterval];
	}
	return YES;
}
- (void)_parseFrame:(inout volatile IOUSBLowLatencyIsocFrame *)frame bytes:(UInt8 const *)bytes previousFrame:(IOUSBLowLatencyIsocFrame *)previous millisecondInterval:(UInt8)millisecondInterval
{
	if(previous && kUSBLowLatencyIsochTransferKey == frame->frStatus) {
		UInt64 const previousTime = UnsignedWideToUInt64(AbsoluteToNanoseconds(previous->frTimeStamp));
		Nanoseconds const nextUpdateTime = UInt64ToUnsignedWide(previousTime + millisecondInterval * ECVNanosecondsPerMillisecond);
		mach_wait_until(UnsignedWideToUInt64(NanosecondsToAbsolute(nextUpdateTime)));
	}
	while(kUSBLowLatencyIsochTransferKey == frame->frStatus) usleep(100); // In case we haven't slept long enough already.
	[self readBytes:bytes length:frame->frActCount];
	frame->frStatus = kUSBLowLatencyIsochTransferKey;
}

#pragma mark -ECVUSBVideoSource(ECVRead_Thread)

- (void)read
{
	UInt8 const pipe = [self pipeRef];
	UInt32 const microsecondsInFrame = [self _microsecondsInFrame];
	ECVPipeProperties const pipeProperties = [self _propertiesForPipe:pipe];
	UInt8 const millisecondInterval = CLAMP(1, pipeProperties.millisecondInterval, 8);
	NSUInteger const frameRequestSize = pipeProperties.frameRequestSize;
	ECVUSBTransferList *const transferList = [self transferListWithFrameRequestSize:frameRequestSize];
	NSUInteger const numberOfTransfers = [transferList numberOfTransfers];
	NSUInteger const microframesPerTransfer = [transferList microframesPerTransfer];
	ECVUSBTransfer *const transfers = [transferList transfers];

	UInt64 currentFrameNumber = [self _currentFrameNumber] + 10;
	BOOL read = YES;
	while(read) {
		NSAutoreleasePool *const pool = [[NSAutoreleasePool alloc] init];
		NSUInteger i;
		for(i = 0; i < numberOfTransfers; ++i) {
			ECVUSBTransfer *const transfer = transfers + i;
			read = read && [self _parseTransfer:transfer numberOfMicroframes:microframesPerTransfer frameRequestSize:frameRequestSize millisecondInterval:millisecondInterval];
			read = read && [self _readTransfer:transfer numberOfMicroframes:microframesPerTransfer pipeRef:pipe frameNumber:&currentFrameNumber microsecondsInFrame:microsecondsInFrame millisecondInterval:millisecondInterval];
		}
		if(![self keepReading]) read = NO;
		[pool drain];
	}
}
- (BOOL)keepReading
{
	return [self _keepReading];
}

#pragma mark -ECVSource

- (void)play
{
	[_readLock lock];
	_read = YES;
	[_readLock unlock];
	[NSThread detachNewThreadSelector:@selector(_read) toTarget:self withObject:nil];
}
- (void)stop
{
	[_readLock lock];
	_read = NO;
	[_readLock unlock];
}

#pragma mark -ECVSource(ECVAbstract)

- (NSString *)name
{
	return [self valueForProperty:kUSBProductString];
}

#pragma mark -NSObject

- (void)dealloc
{
	IOObjectRelease(_service);
	[_properties release];
	[_readThreadLock release];
	[_readLock release];
	[super dealloc];
}

@end
