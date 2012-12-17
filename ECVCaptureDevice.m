/* Copyright (c) 2009-2011, Ben Trask
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
#import "ECVCaptureDevice.h"
#import <IOKit/IOCFPlugIn.h>
#import <IOKit/IOMessage.h>
#import <mach/mach_time.h>

// Models
#import "ECVUSBTransferList.h"
#import "ECVVideoSource.h"
#import "ECVVideoFormat.h"
#import "ECVVideoStorage.h"
#import "ECVDeinterlacingMode.h"
#import "ECVVideoFrame.h"

// Controllers
#import "ECVController.h"

// Other Sources
#import "ECVDebug.h"
#import "ECVFoundationAdditions.h"

#define ECVNanosecondsPerMillisecond 1e6

NSString *const ECVDeinterlacingModeKey = @"ECVDeinterlacingMode";

NSString *const ECVBrightnessKey = @"ECVBrightness";
NSString *const ECVContrastKey = @"ECVContrast";
NSString *const ECVSaturationKey = @"ECVSaturation";
NSString *const ECVHueKey = @"ECVHue";

typedef struct {
	IOUSBLowLatencyIsocFrame *list;
	UInt8 *data;
} ECVTransfer;

@interface ECVCaptureDevice(Private)

- (UInt32)_microsecondsInFrame;
- (UInt64)_currentFrameNumber;
- (ECVUSBTransferList *)_transferListWithFrameRequestSize:(NSUInteger const)frameRequestSize;

- (void)_read;
- (BOOL)_keepReading;
- (BOOL)_readTransfer:(inout ECVUSBTransfer *)transfer numberOfMicroframes:(NSUInteger)numberOfMicroframes pipeRef:(UInt8)pipe frameNumber:(inout UInt64 *)frameNumber microsecondsInFrame:(UInt64)microsecondsInFrame millisecondInterval:(UInt8)millisecondInterval;
- (BOOL)_parseTransfer:(inout ECVUSBTransfer *)transfer numberOfMicroframes:(NSUInteger)numberOfMicroframes frameRequestSize:(NSUInteger)frameRequestSize millisecondInterval:(UInt8)millisecondInterval;
- (void)_parseFrame:(inout volatile IOUSBLowLatencyIsocFrame *)frame bytes:(void const *)bytes previousFrame:(IOUSBLowLatencyIsocFrame *)previous millisecondInterval:(UInt8)millisecondInterval;

#if !defined(ECV_NO_CONTROLLERS)
- (void)_startPlayingForControllers;
- (void)_stopPlayingForControllers;
#endif

@end

static NSMutableArray *ECVDeviceClasses = nil;
static NSDictionary *ECVDevicesDictionary = nil;

static void ECVDeviceRemoved(ECVCaptureDevice *device, io_service_t service, uint32_t messageType, void *messageArgument)
{
	if(kIOMessageServiceIsTerminated == messageType) [device performSelector:@selector(noteDeviceRemoved) withObject:nil afterDelay:0.0f inModes:[NSArray arrayWithObject:NSDefaultRunLoopMode]]; // Make sure we don't do anything during a special run loop mode (eg. NSModalPanelRunLoopMode).
}
static void ECVDoNothing(void *refcon, IOReturn result, void *arg0) {}

static IOReturn ECVGetPipeWithProperties(IOUSBInterfaceInterface **const interface, UInt8 *const outPipeIndex, UInt8 *const inoutDirection, UInt8 *const inoutTransferType, UInt16 *const inoutPacketSize, UInt8 *const outMillisecondInterval) // TODO: We should have a separate class for USB-specific devices, and this should probably be a method on it.
{
	IOReturn err = kIOReturnSuccess;
	UInt8 count = 0;
	err = (*interface)->GetNumEndpoints(interface, &count);
	if(err) return err;
	for(UInt8 i = 0; i <= count; ++i) {
		UInt8 direction, ignored, transferType, millisecondInterval;
		UInt16 packetSize;
		err = (*interface)->GetPipeProperties(interface, i, &direction, &ignored, &transferType, &packetSize, &millisecondInterval);
		if(err) continue;
		if(direction != *inoutDirection && direction != kUSBAnyDirn) continue;
		if(transferType != *inoutTransferType && transferType != kUSBAnyType) continue;
		if(packetSize < *inoutPacketSize) {
			err = kIOReturnNoBandwidth;
			continue;
		}
		*outPipeIndex = i;
		*inoutDirection = direction;
		*inoutTransferType = transferType;
		*inoutPacketSize = packetSize;
		*outMillisecondInterval = millisecondInterval;
		return kIOReturnSuccess;
	}
	return err ?: kIOReturnNotFound;
}

@implementation ECVCaptureDevice

#pragma mark +ECVCaptureDevice

+ (NSArray *)deviceClasses
{
	return [[ECVDeviceClasses copy] autorelease];
}
+ (void)registerDeviceClass:(Class const)cls
{
	if(!cls) return;
	if([ECVDeviceClasses indexOfObjectIdenticalTo:cls] != NSNotFound) return;
	[ECVDeviceClasses addObject:cls];
}
+ (void)unregisterDeviceClass:(Class const)cls
{
	if(!cls) return;
	[ECVDeviceClasses removeObjectIdenticalTo:cls];
}

#pragma mark -

+ (NSDictionary *)deviceDictionary
{
	return [ECVDevicesDictionary objectForKey:NSStringFromClass(self)];
}
+ (NSDictionary *)matchingDictionary
{
	NSDictionary *const deviceDict = [self deviceDictionary];
	if(!deviceDict) return nil;
	NSMutableDictionary *const matchingDict = [(NSMutableDictionary *)IOServiceMatching(kIOUSBDeviceClassName) autorelease];
	[matchingDict setObject:[deviceDict objectForKey:@"ECVVendorID"] forKey:[NSString stringWithUTF8String:kUSBVendorID]];
	[matchingDict setObject:[deviceDict objectForKey:@"ECVProductID"] forKey:[NSString stringWithUTF8String:kUSBProductID]];
	return matchingDict;
}
+ (NSArray *)devicesWithIterator:(io_iterator_t const)iterator
{
	NSMutableArray *const devices = [NSMutableArray array];
	io_service_t service = IO_OBJECT_NULL;
	while((service = IOIteratorNext(iterator))) {
		ECVCaptureDevice *const device = [[[self alloc] initWithService:service] autorelease];
		if(device) [devices addObject:device];
		IOObjectRelease(service);
	}
	return devices;
}

#pragma mark -

+ (IOUSBDeviceInterface320 **)USBDeviceWithService:(io_service_t const)service
{
	uint32_t busy;
	(void)ECVIOReturn2(IOServiceGetBusyState(service, &busy));
	if(busy) {
		ECVLog(ECVError, @"Device busy and cannot be accessed. (Try restarting.)");
		return NULL; // We can't solve it, so just bail.
	}

	SInt32 ignored = 0;
	IOCFPlugInInterface **devicePlugInInterface = NULL;
	if(kIOReturnSuccess != ECVIOReturn2(IOCreatePlugInInterfaceForService(service, kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID, &devicePlugInInterface, &ignored))) {
		return NULL;
	}

	IOUSBDeviceInterface320 **device = NULL;
	(*devicePlugInInterface)->QueryInterface(devicePlugInInterface, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID320), (LPVOID)&device);

	(*devicePlugInInterface)->Release(devicePlugInInterface);

	return device;
}
+ (IOUSBInterfaceInterface300 **)USBInterfaceWithDevice:(IOUSBDeviceInterface320 **const)device
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
	if(kIOReturnSuccess != ECVIOReturn2(IOCreatePlugInInterfaceForService(service, kIOUSBInterfaceUserClientTypeID, kIOCFPlugInInterfaceID, &interfacePlugInInterface, &ignored))) {
		IOObjectRelease(service);
		return NULL;
	}

	IOUSBInterfaceInterface300 **interface = NULL;
	(*interfacePlugInInterface)->QueryInterface(interfacePlugInInterface, CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID300), (LPVOID)&interface);

	(*interfacePlugInInterface)->Release(interfacePlugInInterface);
	IOObjectRelease(service);

	return interface;
}

#pragma mark +NSObject

+ (void)initialize
{
	if(!ECVDeviceClasses) ECVDeviceClasses = [[NSMutableArray alloc] init];
	if(!ECVDevicesDictionary) {
		ECVDevicesDictionary = [[NSDictionary alloc] initWithContentsOfFile:[[NSBundle bundleForClass:self] pathForResource:@"ECVDevices" ofType:@"plist"]];
		for(NSString *const name in ECVDevicesDictionary) [self registerDeviceClass:NSClassFromString(name)];
	}
}

#pragma mark -ECVCaptureDevice

- (id)initWithService:(io_service_t const)service
{
	if(!service) {
		[self release];
		return nil;
	}
	if((self = [super init])) {
		_service = service;
		IOObjectRetain(_service);


		_readThreadLock = [[NSLock alloc] init];
		_readLock = [[NSLock alloc] init];


		_pauseCount = 1;


		NSMutableDictionary *properties = nil;
		(void)ECVIOReturn2(IORegistryEntryCreateCFProperties(_service, (CFMutableDictionaryRef *)&properties, kCFAllocatorDefault, kNilOptions));
		[properties autorelease];
		_productName = [[properties objectForKey:[NSString stringWithUTF8String:kUSBProductString]] copy];
		if(![_productName length]) _productName = [NSLocalizedString(@"Capture Device", nil) retain];

		NSString *const mainSuiteName = [[[NSBundle bundleForClass:[self class]] infoDictionary] objectForKey:@"ECVMainSuiteName"];
		NSString *const deviceSuiteName = [NSString stringWithFormat:@"%@.%04x.%04x", mainSuiteName, [[properties objectForKey:[NSString stringWithUTF8String:kUSBVendorID]] unsignedIntegerValue], [[properties objectForKey:[NSString stringWithUTF8String:kUSBProductID]] unsignedIntegerValue]];
		_defaults = [[NSUserDefaults alloc] init];
		[_defaults addSuiteNamed:deviceSuiteName];
		[_defaults addSuiteNamed:mainSuiteName];
		[_defaults registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
			[NSNumber numberWithInteger:ECVLineDoubleHQ], ECVDeinterlacingModeKey,
			[NSNumber numberWithDouble:0.5f], ECVBrightnessKey,
			[NSNumber numberWithDouble:0.5f], ECVContrastKey,
			[NSNumber numberWithDouble:0.5f], ECVHueKey,
			[NSNumber numberWithDouble:0.5f], ECVSaturationKey,
			nil]];

		[self setDeinterlacingMode:[ECVDeinterlacingMode deinterlacingModeWithType:[[self defaults] integerForKey:ECVDeinterlacingModeKey]]];

		(void)ECVIOReturn2(IOServiceAddInterestNotification([[ECVController sharedController] notificationPort], service, kIOGeneralInterest, (IOServiceInterestCallback)ECVDeviceRemoved, self, &_deviceRemovedNotification));
	}
	return self;
}
- (void)noteDeviceRemoved
{
//	[self close];
	// TODO: Do something?
}

#pragma mark -

- (Class)deinterlacingMode
{
	return _deinterlacingMode;
}
- (void)setDeinterlacingMode:(Class const)mode
{
	if(mode == _deinterlacingMode) return;
	[self setPaused:YES];
	[_deinterlacingMode release];
	_deinterlacingMode = [mode copy];
	[self setPaused:NO];
	[[self defaults] setInteger:[mode deinterlacingModeType] forKey:ECVDeinterlacingModeKey];
}
- (NSUserDefaults *)defaults { return _defaults; }
- (ECVVideoStorage *)videoStorage { return _videoStorage; }

#pragma mark -

- (void)read
{
	UInt8 pipe = 0;
	UInt8 direction = kUSBIn;
	UInt8 transferType = kUSBIsoc;
	UInt16 frameRequestSize = 1;
	UInt8 millisecondInterval = 0;
	(void)ECVIOReturn2(ECVGetPipeWithProperties((void *)_USBInterface, &pipe, &direction, &transferType, &frameRequestSize, &millisecondInterval));

	UInt32 const microsecondsInFrame = [self _microsecondsInFrame];
	ECVUSBTransferList *const transferList = [self _transferListWithFrameRequestSize:frameRequestSize];
	NSUInteger const numberOfTransfers = [transferList numberOfTransfers];
	NSUInteger const microframesPerTransfer = [transferList microframesPerTransfer];
	ECVUSBTransfer *const transfers = [transferList transfers];

	UInt64 currentFrameNumber = 0;
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

#pragma mark -

- (BOOL)setAlternateInterface:(UInt8)alternateSetting
{
	IOReturn const error = (*_USBInterface)->SetAlternateInterface(_USBInterface, alternateSetting);
	switch(error) {
		case kIOReturnSuccess: return YES;
		case kIOReturnNoDevice:
		case kIOReturnNotResponding: return NO;
	}
	ECVIOReturn(error);
ECVGenericError:
ECVNoDeviceError:
	return NO;
}
- (BOOL)controlRequestWithType:(u_int8_t)type request:(UInt8 const)request value:(UInt16 const)v index:(UInt16 const)i length:(UInt16 const)length data:(inout void *const)data
{
	IOUSBDevRequest r = { type, request, v, i, length, data, 0 };
	IOReturn const error = (*_USBInterface)->ControlRequest(_USBInterface, 0, &r);
	if(r.wLenDone != r.wLength) return NO;
	switch(error) {
		case kIOReturnSuccess: return YES;
		case kIOUSBPipeStalled: ECVIOReturn((*_USBInterface)->ClearPipeStall(_USBInterface, 0)); return YES;
		case kIOReturnNotResponding: return NO;
	}
	ECVIOReturn(error);
ECVGenericError:
ECVNoDeviceError:
	return NO;
}
- (BOOL)readRequest:(UInt8 const)request value:(UInt16 const)v index:(UInt16 const)i length:(UInt16 const)length data:(out void *const)data
{
	return [self controlRequestWithType:USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice) request:request value:v index:i length:length data:data];
}
- (BOOL)writeRequest:(UInt8 const)request value:(UInt16 const)v index:(UInt16 const)i length:(UInt16 const)length data:(in void *const)data
{
	return [self controlRequestWithType:USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice) request:request value:v index:i length:length data:data];
}

#pragma mark -ECVCaptureDevice(Private)

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
- (ECVUSBTransferList *)_transferListWithFrameRequestSize:(NSUInteger const)frameRequestSize
{
	return [[[ECVUSBTransferList alloc] initWithInterface:_USBInterface numberOfTransfers:32 microframesPerTransfer:32 frameRequestSize:frameRequestSize] autorelease];
}

- (void)_read
{
	NSAutoreleasePool *const pool = [[NSAutoreleasePool alloc] init];
	[_readThreadLock lock];
	if([self _keepReading]) {
		ECVLog(ECVNotice, @"Starting device %@.", [self name]);

		IOReturn err = kIOReturnSuccess;
		err = err ?: ((_USBDevice = [[self class] USBDeviceWithService:[self service]]) ? kIOReturnSuccess : kIOReturnError);

		err = err ?: ECVIOReturn2((*_USBDevice)->USBDeviceOpen(_USBDevice));
		err = err ?: ECVIOReturn2((*_USBDevice)->ResetDevice(_USBDevice));

		IOUSBConfigurationDescriptorPtr configurationDescription = NULL;
		err = err ?: ECVIOReturn2((*_USBDevice)->GetConfigurationDescriptorPtr(_USBDevice, 0, &configurationDescription));
		err = err ?: ECVIOReturn2((*_USBDevice)->SetConfiguration(_USBDevice, configurationDescription->bConfigurationValue));

		err = err ?: ((_USBInterface = [[self class] USBInterfaceWithDevice:_USBDevice]) ? kIOReturnSuccess : kIOReturnError);

		err = err ?: ECVIOReturn2((*_USBInterface)->USBInterfaceOpenSeize(_USBInterface));

		CFRunLoopSourceRef eventSource = NULL;
		err = err ?: ECVIOReturn2((*_USBInterface)->CreateInterfaceAsyncEventSource(_USBInterface, &eventSource));

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

		ECVLog(ECVNotice, @"Stopping device %@.", [self name]);
	}
	[_readThreadLock unlock];
	[pool drain];
}
- (BOOL)_keepReading
{
	[_readLock lock];
	BOOL const read = _read;
	[_readLock unlock];
	return read;
}
- (BOOL)_readTransfer:(inout ECVUSBTransfer *)transfer numberOfMicroframes:(NSUInteger)numberOfMicroframes pipeRef:(UInt8)pipe frameNumber:(inout UInt64 *)frameNumber microsecondsInFrame:(UInt64)microsecondsInFrame millisecondInterval:(UInt8)millisecondInterval
{
	if(!*frameNumber) *frameNumber = [self _currentFrameNumber] + 10;
	switch(ECVIOReturn2((*_USBInterface)->LowLatencyReadIsochPipeAsync(_USBInterface, pipe, transfer->data, *frameNumber, numberOfMicroframes, millisecondInterval, transfer->frames, ECVDoNothing, NULL))) {
		case kIOReturnSuccess:
			*frameNumber += numberOfMicroframes / (kUSBFullSpeedMicrosecondsInFrame / microsecondsInFrame);
			return YES;
		case kIOReturnIsoTooOld:
			*frameNumber = 0;
			NSUInteger i;
			for(i = 0; i < numberOfMicroframes; ++i) transfer->frames[i].frStatus = kIOReturnInvalid;
			return YES;
	}
	return NO;
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
	[self writeBytes:bytes length:frame->frActCount toStorage:_videoStorage];
	frame->frStatus = kUSBLowLatencyIsochTransferKey;
}

#pragma mark -NSObject

- (void)dealloc
{
	IOObjectRelease(_service);
	IOObjectRelease(_deviceRemovedNotification);

	[_defaults release];
	[_productName release];

	[_deinterlacingMode release];
	[_videoSource release];
	[_videoFormat release];

	[super dealloc];
}







// Ongoing refactoring... This code is new, the above code is not.

- (NSUInteger)pauseCount
{
	return _pauseCount;
}
- (BOOL)isPaused
{
	return !!_pauseCount;
}
- (void)setPaused:(BOOL const)flag
{
	NSParameterAssert(flag || 0 != _pauseCount);
	if(flag) {
		if(1 == ++_pauseCount) [self stop];
	} else {
		if(0 == --_pauseCount) [self play];
	}
}
- (void)play
{
	[_readLock lock];
	_read = YES;
	_videoStorage = [[[ECVVideoStorage preferredVideoStorageClass] alloc] initWithVideoFormat:[self videoFormat] deinterlacingMode:[self deinterlacingMode] pixelFormat:[self pixelFormat]];
	[_readLock unlock];
	[NSThread detachNewThreadSelector:@selector(_read) toTarget:self withObject:nil];
}
- (void)stop
{
	[_readLock lock];
	_read = NO;
	[_videoStorage release];
	_videoStorage = nil;
	[_readLock unlock];
}


- (ECVVideoSource *)videoSource
{
	return [[_videoSource retain] autorelease];
}
- (void)setVideoSource:(ECVVideoSource *const)source
{
	if(BTEqualObjects(source, _videoSource)) return;
	[self setPaused:YES];
	[_videoSource release];
	_videoSource = [source retain];
	[self setPaused:NO];
	// TODO: Serialize.
}
- (ECVVideoFormat *)videoFormat
{
	return [[_videoFormat retain] autorelease];
}
- (void)setVideoFormat:(ECVVideoFormat *const)format
{
	if(BTEqualObjects(format, _videoFormat)) return;
	[self setPaused:YES];
	[_videoFormat release];
	_videoFormat = [format retain];
	[self setPaused:NO];
	// TODO: Save preference... Serialization?
}





- (NSString *)name
{
	return _productName;
}
- (io_service_t)service
{
	return _service;
}

- (void)finishedFrame:(ECVVideoFrame *const)frame // TODO: Part of the gradual split into two separate objects.
{
	if(!frame) return;
	// TODO: Notify document.
//#if !defined(ECV_NO_CONTROLLERS)
//	[_windowControllersLock readLock];
//	[_windowControllers2 makeObjectsPerformSelector:@selector(threaded_pushFrame:) withObject:frame];
//	[_windowControllersLock unlock];
//#endif
}

@end
