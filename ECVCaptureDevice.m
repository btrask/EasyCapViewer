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
#import "ECVCaptureDocument.h"
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

static NSString *const ECVVideoSourceKey = @"ECVVideoSource";
static NSString *const ECVVideoFormatKey = @"ECVVideoFormat";

typedef struct {
	IOUSBLowLatencyIsocFrame *list;
	UInt8 *data;
} ECVTransfer;

@interface ECVCaptureDevice(Private)

- (void)_updateVideoStorage;

- (UInt32)_microsecondsInFrame;
- (UInt64)_currentFrameNumber;
- (ECVUSBTransferList *)_transferListWithFrameRequestSize:(NSUInteger const)frameRequestSize;

- (void)_read;
- (BOOL)_keepReading;
- (BOOL)_readTransfer:(inout ECVUSBTransfer *)transfer numberOfMicroframes:(NSUInteger)numberOfMicroframes pipeRef:(UInt8)pipe frameNumber:(inout UInt64 *)frameNumber microsecondsInFrame:(UInt64)microsecondsInFrame millisecondInterval:(UInt8)millisecondInterval;
- (BOOL)_parseTransfer:(inout ECVUSBTransfer *)transfer numberOfMicroframes:(NSUInteger)numberOfMicroframes frameRequestSize:(NSUInteger)frameRequestSize millisecondInterval:(UInt8)millisecondInterval;
- (void)_parseFrame:(inout volatile IOUSBLowLatencyIsocFrame *)frame bytes:(UInt8 const *)bytes previousFrame:(IOUSBLowLatencyIsocFrame *)previous millisecondInterval:(UInt8)millisecondInterval;

@end

static NSMutableArray *ECVDeviceClasses = nil;
static NSDictionary *ECVDevicesDictionary = nil;

static void ECVDeviceRemoved(ECVCaptureDevice *device, io_service_t service, uint32_t messageType, void *messageArgument)
{
	if(kIOMessageServiceIsTerminated == messageType) [device performSelector:@selector(invalidate) withObject:nil afterDelay:0.0f inModes:[NSArray arrayWithObject:NSDefaultRunLoopMode]]; // Make sure we don't do anything during a special run loop mode (eg. NSModalPanelRunLoopMode).
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
	mach_timespec_t delay = {
		.tv_sec = 1,
		.tv_nsec = 0,
	};
	if(kIOReturnTimeout == IOServiceWaitQuiet(service, &delay)) {
		ECVLog(ECVError, @"Device busy and cannot be accessed. (Try restarting.)");
		return NULL; // We can't solve it, so just bail.
	}

	SInt32 ignored = 0;
	IOCFPlugInInterface **devicePlugInInterface = NULL;
	if(kIOReturnSuccess != ECVIOReturn(IOCreatePlugInInterfaceForService(service, kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID, &devicePlugInInterface, &ignored))) {
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
	(void)ECVIOReturn((*device)->CreateInterfaceIterator(device, &interfaceRequest, &interfaceIterator));
	io_service_t const service = IOIteratorNext(interfaceIterator);
	NSParameterAssert(service);

	SInt32 ignored = 0;
	IOCFPlugInInterface **interfacePlugInInterface = NULL;
	if(kIOReturnSuccess != ECVIOReturn(IOCreatePlugInInterfaceForService(service, kIOUSBInterfaceUserClientTypeID, kIOCFPlugInInterfaceID, &interfacePlugInInterface, &ignored))) {
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

		NSMutableDictionary *properties = nil;
		(void)ECVIOReturn(IORegistryEntryCreateCFProperties(_service, (CFMutableDictionaryRef *)&properties, kCFAllocatorDefault, kNilOptions));
		[properties autorelease];
		_productName = [[[properties objectForKey:[NSString stringWithUTF8String:kUSBProductString]] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
		if(![_productName length]) _productName = [NSLocalizedString(@"Capture Device", nil) retain];

		NSString *const mainSuiteName = [[[NSBundle bundleForClass:[self class]] infoDictionary] objectForKey:@"ECVMainSuiteName"];
		NSString *const deviceSuiteName = [NSString stringWithFormat:@"%@.%04x.%04x", mainSuiteName, [[properties objectForKey:[NSString stringWithUTF8String:kUSBVendorID]] unsignedIntegerValue], [[properties objectForKey:[NSString stringWithUTF8String:kUSBProductID]] unsignedIntegerValue]];
		NSUserDefaults *const d = [NSUserDefaults standardUserDefaults];
		[d registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
			[NSNumber numberWithInteger:ECVLineDoubleHQ], ECVDeinterlacingModeKey,
			[NSNumber numberWithDouble:0.5f], ECVBrightnessKey,
			[NSNumber numberWithDouble:0.5f], ECVContrastKey,
			[NSNumber numberWithDouble:0.5f], ECVHueKey,
			[NSNumber numberWithDouble:0.5f], ECVSaturationKey,
			nil]];

		[self setDeinterlacingMode:[ECVDeinterlacingMode deinterlacingModeWithType:[d integerForKey:ECVDeinterlacingModeKey]]];
		[self loadPreferredVideoSource];
		[self loadPreferredVideoFormat]; // FIXME: Devices that use SAA711XChip must load it before they invoke [super initWithSerivce:], which is a bit ugly/nonstandard. Maybe they shouldn't override -initWithService: at all, but instead override a custom method.

		IOReturn err = kIOReturnSuccess;
		err = err ?: ((_USBDevice = [[self class] USBDeviceWithService:[self service]]) ? kIOReturnSuccess : kIOReturnError);

		err = err ?: ECVIOReturn((*_USBDevice)->USBDeviceOpen(_USBDevice));
		err = err ?: ECVIOReturn((*_USBDevice)->ResetDevice(_USBDevice));

		IOUSBConfigurationDescriptorPtr configurationDescription = NULL;
		err = err ?: ECVIOReturn((*_USBDevice)->GetConfigurationDescriptorPtr(_USBDevice, 0, &configurationDescription));
		err = err ?: ECVIOReturn((*_USBDevice)->SetConfiguration(_USBDevice, configurationDescription->bConfigurationValue));

		if(kIOReturnSuccess != err) {
			ECVLog(ECVError, @"Device %@ failed to open", self);
			[self release];
			return nil;
		}

		_valid = YES;

		Class const controller = NSClassFromString(@"ECVController"); // FIXME: Kind of a hack.
		if(controller) (void)ECVIOReturn(IOServiceAddInterestNotification([[controller sharedController] notificationPort], service, kIOGeneralInterest, (IOServiceInterestCallback)ECVDeviceRemoved, self, &_deviceRemovedNotification));
	}
	return self;
}
- (BOOL)isValid
{
	return _valid;
}
- (void)invalidate
{
	_valid = NO;
	[[self captureDocument] close];
}

#pragma mark -

- (Class)deinterlacingMode
{
	return _deinterlacingMode;
}
- (void)setDeinterlacingMode:(Class const)mode
{
	if(mode == _deinterlacingMode) return;
	[_captureDocument setPaused:YES];
	[_deinterlacingMode release];
	_deinterlacingMode = [mode copy];
	[self _updateVideoStorage];
	[_captureDocument setPaused:NO];
	[[NSUserDefaults standardUserDefaults] setInteger:[mode deinterlacingModeType] forKey:ECVDeinterlacingModeKey];
}
- (ECVVideoStorage *)videoStorage { return [[_videoStorage retain] autorelease]; }

#pragma mark -

- (void)read
{
	UInt8 pipe = 0;
	UInt8 direction = kUSBIn;
	UInt8 transferType = kUSBIsoc;
	UInt16 frameRequestSize = 1;
	UInt8 millisecondInterval = 0;
	(void)ECVIOReturn(ECVGetPipeWithProperties((void *)_USBInterface, &pipe, &direction, &transferType, &frameRequestSize, &millisecondInterval));

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
	if(!_USBInterface) return NO;
	IOReturn const error = ECVIOReturn((*_USBInterface)->SetAlternateInterface(_USBInterface, alternateSetting));
	switch(error) {
		case kIOReturnSuccess: return YES;
		case kIOReturnNoDevice:
		case kIOReturnNotResponding: return NO;
	}
	return NO;
}
- (BOOL)controlRequestWithType:(u_int8_t)type request:(UInt8 const)request value:(UInt16 const)v index:(UInt16 const)i length:(UInt16 const)length data:(inout void *const)data
{
	if(!_USBInterface) return NO;
	IOUSBDevRequest r = { type, request, v, i, length, data, 0 };
	IOReturn const error = ECVIOReturn((*_USBInterface)->ControlRequest(_USBInterface, 0, &r));
	if(r.wLenDone != r.wLength) return NO;
	switch(error) {
		case kIOReturnSuccess: return YES;
		case kIOUSBPipeStalled: (void)ECVIOReturn((*_USBInterface)->ClearPipeStall(_USBInterface, 0)); return YES;
		case kIOReturnNotResponding: return NO;
	}
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

- (void)_updateVideoStorage
{
	[_captureDocument setPaused:YES];
	[_videoStorage release];
	_videoStorage = nil;
	if([self videoFormat]) _videoStorage = [[[ECVVideoStorage preferredVideoStorageClass] alloc] initWithVideoFormat:[self videoFormat] deinterlacingMode:[self deinterlacingMode] pixelFormat:[self pixelFormat]];
	[_captureDocument setPaused:NO];
}

#pragma mark -

- (UInt32)_microsecondsInFrame
{
	UInt32 microsecondsInFrame = 0;
	(void)ECVIOReturn((*_USBInterface)->GetFrameListTime(_USBInterface, &microsecondsInFrame));
	return microsecondsInFrame;
}
- (UInt64)_currentFrameNumber
{
	UInt64 currentFrameNumber = 0;
	AbsoluteTime atTimeIgnored;
	(void)ECVIOReturn((*_USBInterface)->GetBusFrameNumber(_USBInterface, &currentFrameNumber, &atTimeIgnored));
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
		err = err ?: ((_USBInterface = [[self class] USBInterfaceWithDevice:_USBDevice]) ? kIOReturnSuccess : kIOReturnError);

		err = err ?: ECVIOReturn((*_USBInterface)->USBInterfaceOpen(_USBInterface));
		err = err ?: ECVIOReturn((*_USBInterface)->CreateInterfaceAsyncEventSource(_USBInterface, &_ignoredEventSource));
		CFRunLoopAddSource(CFRunLoopGetCurrent(), _ignoredEventSource, kCFRunLoopCommonModes);

		if(err) {
			// Do nothing.
		} else if([self _microsecondsInFrame] > [self maximumMicrosecondsInFrame]) {
			ECVLog(ECVError, @"USB bus too slow (%lu > %lu).", (unsigned long)[self _microsecondsInFrame], (unsigned long)[self maximumMicrosecondsInFrame]);
		} else {
			[self read];
		}

		if(_ignoredEventSource) {
			CFRunLoopSourceInvalidate(_ignoredEventSource);
			CFRelease(_ignoredEventSource);
		}
		if(_USBInterface) (*_USBInterface)->Release(_USBInterface);
		_USBInterface = NULL;

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
	while(kCFRunLoopRunHandledSource == CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.0, true)); // Clean up the event loop. Prevents the kernel from filling up its buffer and logging error messages. It'd be nice to turn this off entirely, since we don't use it.
	if(!*frameNumber) *frameNumber = [self _currentFrameNumber] + 10;
	switch(ECVIOReturn((*_USBInterface)->LowLatencyReadIsochPipeAsync(_USBInterface, pipe, transfer->data, *frameNumber, numberOfMicroframes, millisecondInterval, transfer->frames, ECVDoNothing, NULL))) {
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
	if(_USBDevice) (*_USBDevice)->USBDeviceClose(_USBDevice);
	if(_USBDevice) (*_USBDevice)->Release(_USBDevice);
	_USBDevice = NULL;

	IOObjectRelease(_service);
	IOObjectRelease(_deviceRemovedNotification);

	[_productName release];

	[_deinterlacingMode release];
	[_videoSource release];
	[_videoFormat release];

	[_videoStorage release];

	[super dealloc];
}







// Ongoing refactoring... This code is new, the above code is not.

- (ECVCaptureDocument *)captureDocument
{
	return _captureDocument;
}
- (void)setCaptureDocument:(ECVCaptureDocument *const)doc
{
	_captureDocument = doc;
}


- (ECVVideoSource *)videoSource
{
	return [[_videoSource retain] autorelease];
}
- (void)setVideoSource:(ECVVideoSource *const)source
{
	if(BTEqualObjects(source, _videoSource)) return;
	[_captureDocument setPaused:YES];
	[_videoSource release];
	_videoSource = [source retain];
	[_captureDocument setPaused:NO];
	NSString *const key = [NSString stringWithFormat:@"%@.%@", ECVVideoSourceKey, NSStringFromClass([self class])];
	[[NSUserDefaults standardUserDefaults] setObject:[_videoSource serializedValue] forKey:key];
}
- (void)loadPreferredVideoSource
{
	NSString *const key = [NSString stringWithFormat:@"%@.%@", ECVVideoSourceKey, NSStringFromClass([self class])];
	id const val = [[NSUserDefaults standardUserDefaults] objectForKey:key];
	for(ECVVideoSource *const s in [self supportedVideoSources]) if([s matchesSerializedValue:val]) return [self setVideoSource:s];
	[self setVideoSource:[self defaultVideoSource]];
}
- (ECVVideoFormat *)videoFormat
{
	return [[_videoFormat retain] autorelease];
}
- (void)setVideoFormat:(ECVVideoFormat *const)format
{
	if(BTEqualObjects(format, _videoFormat)) return;
	[_captureDocument setPaused:YES];
	[_videoFormat release];
	_videoFormat = [format retain];
	[self _updateVideoStorage];
	[_captureDocument setPaused:NO];
	NSString *const key = [NSString stringWithFormat:@"%@.%@", ECVVideoFormatKey, NSStringFromClass([self class])];
	[[NSUserDefaults standardUserDefaults] setObject:[_videoFormat serializedValue] forKey:key];
}
- (void)loadPreferredVideoFormat
{
	NSString *const key = [NSString stringWithFormat:@"%@.%@", ECVVideoFormatKey, NSStringFromClass([self class])];
	id const val = [[NSUserDefaults standardUserDefaults] objectForKey:key];
	for(ECVVideoFormat *const f in [self supportedVideoFormats]) if([f matchesSerializedValue:val]) return [self setVideoFormat:f];
	[self setVideoFormat:[self defaultVideoFormat]];
}



- (NSString *)name
{
	return _productName;
}
- (io_service_t)service
{
	return _service;
}

#pragma mark -ECVCaptureDevice<ECVVideoTarget>

- (void)play
{
	[_readLock lock];
	_read = YES;
	[_videoStorage empty];
	[_readLock unlock];
	[NSThread detachNewThreadSelector:@selector(_read) toTarget:self withObject:nil];
}
- (void)stop
{
	[_readLock lock];
	_read = NO;
	[_readLock unlock];
}
- (void)pushVideoFrame:(ECVVideoFrame *const)frame
{
	[_captureDocument pushVideoFrame:frame];
}
- (void)pushAudioBufferListValue:(NSValue *const)bufferListValue {}

@end
