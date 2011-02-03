/* Copyright (c) 2009-2010, Ben Trask
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
#import "ECVCaptureDevice.h"
#import <IOKit/IOCFPlugIn.h>
#import <IOKit/IOMessage.h>
#import <mach/mach_time.h>

// Models
#import "ECVVideoStorage.h"
#import "ECVVideoFrame.h"

// Controllers
#ifndef ECV_NO_CONTROLLERS
#import "ECVController.h"
#import "ECVCaptureController.h"
#endif

// Other Sources
#import "ECVAudioDevice.h"
#import "ECVAudioPipe.h"
#import "ECVDebug.h"
#import "ECVFoundationAdditions.h"
#import "ECVReadWriteLock.h"

#define ECVNanosecondsPerMillisecond 1e6

NSString *const ECVDeinterlacingModeKey = @"ECVDeinterlacingMode";
NSString *const ECVBrightnessKey = @"ECVBrightness";
NSString *const ECVContrastKey = @"ECVContrast";
NSString *const ECVHueKey = @"ECVHue";
NSString *const ECVSaturationKey = @"ECVSaturation";

NSString *const ECVCaptureDeviceErrorDomain = @"ECVCaptureDeviceError";

NSString *const ECVCaptureDeviceVolumeDidChangeNotification = @"ECVCaptureDeviceVolumeDidChange";

static NSString *const ECVVolumeKey = @"ECVVolume";
static NSString *const ECVUpconvertsFromMonoKey = @"ECVUpconvertsFromMono";

typedef struct {
	IOUSBLowLatencyIsocFrame *list;
	UInt8 *data;
} ECVTransfer;

enum {
	ECVNotPlaying,
	ECVStartPlaying,
	ECVPlaying,
	ECVStopPlaying
}; // _playLock

@interface ECVCaptureDevice(Private)

#ifndef ECV_NO_CONTROLLERS
- (void)_startPlayingForControllers;
- (void)_stopPlayingForControllers;
#endif

@end

static void ECVDeviceRemoved(ECVCaptureDevice *device, io_service_t service, uint32_t messageType, void *messageArgument)
{
	if(kIOMessageServiceIsTerminated == messageType) [device performSelector:@selector(noteDeviceRemoved) withObject:nil afterDelay:0.0f inModes:[NSArray arrayWithObject:NSDefaultRunLoopMode]]; // Make sure we don't do anything during a special run loop mode (eg. NSModalPanelRunLoopMode).
}
static void ECVDoNothing(void *refcon, IOReturn result, void *arg0) {}

@implementation ECVCaptureDevice

#pragma mark +ECVCaptureDevice

+ (NSArray *)deviceDictionaries
{
	return [NSArray arrayWithContentsOfFile:[[NSBundle bundleForClass:self] pathForResource:@"ECVDevices" ofType:@"plist"]];
}
+ (Class)getMatchingDictionary:(out NSDictionary **)outDict forDeviceDictionary:(NSDictionary *)deviceDict
{
	Class const class = NSClassFromString([deviceDict objectForKey:@"ECVCaptureClass"]);
	if(!class) return Nil;
	if(outDict) {
		NSMutableDictionary *const d = [(NSMutableDictionary *)IOServiceMatching(kIOUSBDeviceClassName) autorelease];
		[d setObject:[deviceDict objectForKey:@"ECVVendorID"] forKey:[NSString stringWithUTF8String:kUSBVendorID]];
		[d setObject:[deviceDict objectForKey:@"ECVProductID"] forKey:[NSString stringWithUTF8String:kUSBProductID]];
		*outDict = d;
	}
	return class;
}
+ (NSArray *)devicesWithIterator:(io_iterator_t)iterator
{
	NSMutableArray *const devices = [NSMutableArray array];
	io_service_t service = IO_OBJECT_NULL;
	while((service = IOIteratorNext(iterator))) {
		NSError *error = nil;
		ECVCaptureDevice *const device = [[[self alloc] initWithService:service error:&error] autorelease];
		if(device) [devices addObject:device];
		else if(error) [devices addObject:error];
		IOObjectRelease(service);
	}
	return devices;
}

#pragma mark +NSObject

+ (void)initialize
{
	[[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithInteger:ECVLineDoubleHQ], ECVDeinterlacingModeKey,
		[NSNumber numberWithDouble:0.5f], ECVBrightnessKey,
		[NSNumber numberWithDouble:0.5f], ECVContrastKey,
		[NSNumber numberWithDouble:0.5f], ECVHueKey,
		[NSNumber numberWithDouble:0.5f], ECVSaturationKey,
		[NSNumber numberWithDouble:1.0f], ECVVolumeKey,
		[NSNumber numberWithBool:NO], ECVUpconvertsFromMonoKey,
		nil]];
}

#pragma mark -ECVCaptureDevice

- (id)initWithService:(io_service_t)service error:(out NSError **)outError
{
	if(outError) *outError = nil;
	if(!service) {
		[self release];
		return nil;
	}
	if(!(self = [super init])) return nil;

#ifndef ECV_NO_CONTROLLERS
	_windowControllersLock = [[ECVReadWriteLock alloc] init];
	_windowControllers2 = [[NSMutableArray alloc] init];
#endif

	[[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(workspaceWillSleep:) name:NSWorkspaceWillSleepNotification object:[NSWorkspace sharedWorkspace]];

#ifdef ECV_ENABLE_AUDIO
	[self setVolume:[[NSUserDefaults standardUserDefaults] doubleForKey:ECVVolumeKey]];
	[self setUpconvertsFromMono:[[NSUserDefaults standardUserDefaults] boolForKey:ECVUpconvertsFromMonoKey]];
#endif

#ifndef ECV_NO_CONTROLLERS
	ECVIOReturn(IOServiceAddInterestNotification([[ECVController sharedController] notificationPort], service, kIOGeneralInterest, (IOServiceInterestCallback)ECVDeviceRemoved, self, &_deviceRemovedNotification));
#endif

	_service = service;
	IOObjectRetain(_service);

	io_name_t productName = "";
	ECVIOReturn(IORegistryEntryGetName(service, productName));
	_productName = [[NSString alloc] initWithUTF8String:productName];

	SInt32 ignored = 0;
	IOCFPlugInInterface **devicePlugInInterface = NULL;
	ECVIOReturn(IOCreatePlugInInterfaceForService(service, kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID, &devicePlugInInterface, &ignored));

	ECVIOReturn((*devicePlugInInterface)->QueryInterface(devicePlugInInterface, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID320), (LPVOID)&_deviceInterface));
	(*devicePlugInInterface)->Release(devicePlugInInterface);
	devicePlugInInterface = NULL;

	ECVIOReturn((*_deviceInterface)->USBDeviceOpen(_deviceInterface));
	ECVIOReturn((*_deviceInterface)->ResetDevice(_deviceInterface));

	IOUSBConfigurationDescriptorPtr configurationDescription = NULL;
	ECVIOReturn((*_deviceInterface)->GetConfigurationDescriptorPtr(_deviceInterface, 0, &configurationDescription));
	ECVIOReturn((*_deviceInterface)->SetConfiguration(_deviceInterface, configurationDescription->bConfigurationValue));

	IOUSBFindInterfaceRequest interfaceRequest = {
		kIOUSBFindInterfaceDontCare,
		kIOUSBFindInterfaceDontCare,
		kIOUSBFindInterfaceDontCare,
		kIOUSBFindInterfaceDontCare,
	};
	io_iterator_t interfaceIterator = IO_OBJECT_NULL;
	ECVIOReturn((*_deviceInterface)->CreateInterfaceIterator(_deviceInterface, &interfaceRequest, &interfaceIterator));
	io_service_t const interface = IOIteratorNext(interfaceIterator);
	NSParameterAssert(interface);

	IOCFPlugInInterface **interfacePlugInInterface = NULL;
	ECVIOReturn(IOCreatePlugInInterfaceForService(interface, kIOUSBInterfaceUserClientTypeID, kIOCFPlugInInterfaceID, &interfacePlugInInterface, &ignored));

	if(FAILED((*interfacePlugInInterface)->QueryInterface(interfacePlugInInterface, CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID300), (LPVOID)&_interfaceInterface))) goto ECVGenericError;
	NSParameterAssert(_interfaceInterface);
	ECVIOReturn((*_interfaceInterface)->USBInterfaceOpenSeize(_interfaceInterface));

	ECVIOReturn((*_interfaceInterface)->GetFrameListTime(_interfaceInterface, &_frameTime));
	if([self requiresHighSpeed] && kUSBHighSpeedMicrosecondsInFrame != _frameTime) {
		if(outError) *outError = [NSError errorWithDomain:ECVCaptureDeviceErrorDomain code:0 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
			NSLocalizedString(@"This device requires a USB 2.0 High Speed port in order to operate.", nil), NSLocalizedDescriptionKey,
			NSLocalizedString(@"Make sure it is plugged into a port that supports high speed.", nil), NSLocalizedRecoverySuggestionErrorKey,
			[NSArray array], NSLocalizedRecoveryOptionsErrorKey,
			nil]];
		[self release];
		return nil;
	}

	ECVIOReturn((*_interfaceInterface)->CreateInterfaceAsyncEventSource(_interfaceInterface, NULL));
	_playLock = [[NSConditionLock alloc] initWithCondition:ECVNotPlaying];

	[self setDeinterlacingMode:[[NSUserDefaults standardUserDefaults] integerForKey:ECVDeinterlacingModeKey]];

	return self;

ECVGenericError:
ECVNoDeviceError:
	[self release];
	return nil;
}
- (void)noteDeviceRemoved
{
	[self close];
}
- (void)workspaceWillSleep:(NSNotification *)aNotif
{
	[self setPlaying:NO];
	[self noteDeviceRemoved];
}

#pragma mark -

- (BOOL)isPlaying
{
	switch([_playLock condition]) {
		case ECVNotPlaying:
		case ECVStopPlaying:
			return NO;
		case ECVPlaying:
		case ECVStartPlaying:
			return YES;
	}
	return NO;
}
- (void)setPlaying:(BOOL)flag
{
	[_playLock lock];
	if(flag) {
		if(![self isPlaying]) [self startPlaying];
		else [_playLock unlock];
	} else {
		if([self isPlaying]) {
			[_playLock unlockWithCondition:ECVStopPlaying];
			[_playLock lockWhenCondition:ECVNotPlaying];
		}
		[_playLock unlock];
	}
}
- (void)togglePlaying
{
	[_playLock lock];
	switch([_playLock condition]) {
		case ECVNotPlaying:
		case ECVStopPlaying:
			[self startPlaying];
			break;
		case ECVStartPlaying:
		case ECVPlaying:
			[_playLock unlockWithCondition:ECVStopPlaying];
			[_playLock lockWhenCondition:ECVNotPlaying];
			[_playLock unlock];
			break;
	}
}
@synthesize deinterlacingMode = _deinterlacingMode;
- (void)setDeinterlacingMode:(ECVDeinterlacingMode)mode
{
	if(mode == _deinterlacingMode) return;
	ECVPauseWhile(self, { _deinterlacingMode = mode; });
	[[NSUserDefaults standardUserDefaults] setInteger:mode forKey:ECVDeinterlacingModeKey];
}
@synthesize videoStorage = _videoStorage;
- (NSUInteger)simultaneousTransfers
{
	return 32;
}
- (NSUInteger)microframesPerTransfer
{
	return 32;
}

#pragma mark -

- (void)startPlaying
{
	_firstFrame = YES;
	[_videoStorage release];
	_videoStorage = [[ECVVideoStorage alloc] initWithPixelFormatType:[self pixelFormatType] deinterlacingMode:_deinterlacingMode originalSize:[self captureSize] frameRate:[self frameRate]];
	[_playLock unlockWithCondition:ECVStartPlaying];
	[NSThread detachNewThreadSelector:@selector(threadMain_play) toTarget:self withObject:nil];
}
- (void)threadMain_play
{
	NSAutoreleasePool *const pool = [[NSAutoreleasePool alloc] init];
	NSUInteger i;

	[_playLock lock];
	if([_playLock condition] != ECVStartPlaying) {
		[_playLock unlock];
		[pool release];
		return;
	}
	ECVLog(ECVNotice, @"Starting playback.");
	[NSThread setThreadPriority:1.0f];
	if(![self threaded_play]) goto bail;
	[_playLock unlockWithCondition:ECVPlaying];

	UInt8 const pipeIndex = [self isochReadingPipe];
	UInt8 direction = kUSBNone;
	UInt8 pipeNumberIgnored = 0;
	UInt8 transferType = kUSBAnyType;
	UInt16 frameRequestSize = 0;
	UInt8 millisecondInterval = 0;
	ECVIOReturn((*_interfaceInterface)->GetPipeProperties(_interfaceInterface, pipeIndex, &direction, &pipeNumberIgnored, &transferType, &frameRequestSize, &millisecondInterval));
	if(direction != kUSBIn && direction != kUSBAnyDirn) {
		ECVLog(ECVError, @"Invalid pipe direction %lu", (unsigned long)direction);
		goto ECVGenericError;
	}
	if(transferType != kUSBIsoc) {
		ECVLog(ECVError, @"Invalid transfer type %lu", (unsigned long)transferType);
		goto ECVGenericError;
	}
	NSParameterAssert(frameRequestSize);

	NSUInteger const simultaneousTransfers = [self simultaneousTransfers];
	NSUInteger const microframesPerTransfer = [self microframesPerTransfer];
	ECVTransfer *const transfers = calloc(simultaneousTransfers, sizeof(ECVTransfer));
	for(i = 0; i < simultaneousTransfers; ++i) {
		ECVTransfer *const transfer = transfers + i;
		ECVIOReturn((*_interfaceInterface)->LowLatencyCreateBuffer(_interfaceInterface, (void **)&transfer->list, sizeof(IOUSBLowLatencyIsocFrame) * microframesPerTransfer, kUSBLowLatencyFrameListBuffer));
		ECVIOReturn((*_interfaceInterface)->LowLatencyCreateBuffer(_interfaceInterface, (void **)&transfer->data, frameRequestSize * microframesPerTransfer, kUSBLowLatencyReadBuffer));
		NSUInteger j;
		for(j = 0; j < microframesPerTransfer; ++j) {
			transfer->list[j].frStatus = kIOReturnInvalid; // Ignore them to start out.
			transfer->list[j].frReqCount = frameRequestSize;
		}
	}

	UInt64 currentFrame = 0;
	AbsoluteTime atTimeIgnored;
	ECVIOReturn((*_interfaceInterface)->GetBusFrameNumber(_interfaceInterface, &currentFrame, &atTimeIgnored));
	currentFrame += 10;

#ifdef ECV_ENABLE_AUDIO
	[self performSelectorOnMainThread:@selector(startAudio) withObject:nil waitUntilDone:YES];
#endif
#ifndef ECV_NO_CONTROLLERS
	[self performSelectorOnMainThread:@selector(_startPlayingForControllers) withObject:nil waitUntilDone:YES];
#endif

	while([_playLock condition] == ECVPlaying) {
		NSAutoreleasePool *const innerPool = [[NSAutoreleasePool alloc] init];
		if(![self threaded_watchdog]) {
			ECVLog(ECVError, @"Invalid device watchdog result.");
			[innerPool release];
			break;
		}
		for(i = 0; i < simultaneousTransfers; ++i) {
			ECVTransfer *const transfer = transfers + i;
			NSUInteger j;
			for(j = 0; j < microframesPerTransfer; j++) {
				if(kUSBLowLatencyIsochTransferKey == transfer->list[j].frStatus && j) {
					Nanoseconds const nextUpdateTime = UInt64ToUnsignedWide(UnsignedWideToUInt64(AbsoluteToNanoseconds(transfer->list[j - 1].frTimeStamp)) + millisecondInterval * ECVNanosecondsPerMillisecond);
					mach_wait_until(UnsignedWideToUInt64(NanosecondsToAbsolute(nextUpdateTime)));
				}
				while(kUSBLowLatencyIsochTransferKey == transfer->list[j].frStatus) usleep(100); // In case we haven't slept long enough already.
				[self threaded_readImageBytes:transfer->data + j * frameRequestSize length:(size_t)transfer->list[j].frActCount];
				transfer->list[j].frStatus = kUSBLowLatencyIsochTransferKey;
			}
			ECVIOReturn((*_interfaceInterface)->LowLatencyReadIsochPipeAsync(_interfaceInterface, pipeIndex, transfer->data, currentFrame, microframesPerTransfer, CLAMP(1, millisecondInterval, 8), transfer->list, ECVDoNothing, NULL));
			currentFrame += microframesPerTransfer / (kUSBFullSpeedMicrosecondsInFrame / _frameTime);
		}
		[innerPool drain];
	}

	[self threaded_pause];
ECVGenericError:
ECVNoDeviceError:
#ifdef ECV_ENABLE_AUDIO
	[self performSelectorOnMainThread:@selector(stopAudio) withObject:nil waitUntilDone:NO];
#endif
#ifndef ECV_NO_CONTROLLERS
	[self performSelectorOnMainThread:@selector(_stopPlayingForControllers) withObject:nil waitUntilDone:NO];
#endif

	if(transfers) {
		for(i = 0; i < simultaneousTransfers; ++i) {
			if(transfers[i].list) (*_interfaceInterface)->LowLatencyDestroyBuffer(_interfaceInterface, transfers[i].list);
			if(transfers[i].data) (*_interfaceInterface)->LowLatencyDestroyBuffer(_interfaceInterface, transfers[i].data);
		}
		free(transfers);
	}
	[_pendingFrame release];
	_pendingFrame = nil;
	[_lastCompletedFrame release];
	_lastCompletedFrame = nil;
	[_playLock lock];
bail:
	ECVLog(ECVNotice, @"Stopping playback.");
	NSParameterAssert([_playLock condition] != ECVNotPlaying);
	[_playLock unlockWithCondition:ECVNotPlaying];
	[pool drain];
}
- (void)threaded_readImageBytes:(UInt8 const *)bytes length:(size_t)length
{
	[_pendingFrame appendBytes:bytes length:length];
}
- (void)threaded_startNewImageWithFieldType:(ECVFieldType)fieldType
{
	if(_firstFrame) {
		_firstFrame = NO;
		return;
	}

	switch(_deinterlacingMode) {
		case ECVLineDoubleHQ: [_pendingFrame fillHead]; break;
		default: [_pendingFrame clearTail]; break;
	}
	ECVVideoFrame *frameToDraw = _pendingFrame;
	if(ECVBlur == _deinterlacingMode && _lastCompletedFrame) {
		[_lastCompletedFrame blurWithFrame:_pendingFrame];
		frameToDraw = _lastCompletedFrame;
	}
#ifndef ECV_NO_CONTROLLERS
	if(frameToDraw) {
		[_windowControllersLock readLock];
		[_windowControllers2 makeObjectsPerformSelector:@selector(threaded_pushFrame:) withObject:frameToDraw];
		[_windowControllersLock unlock];
	}
#endif

	if(_pendingFrame) {
		[_lastCompletedFrame release];
		_lastCompletedFrame = _pendingFrame;
	}
	_pendingFrame = [[_videoStorage nextFrameWithFieldType:fieldType] retain];
	switch(_deinterlacingMode) {
		case ECVWeave: [_pendingFrame fillWithFrame:_lastCompletedFrame]; break;
		case ECVLineDoubleHQ: [_pendingFrame clearHead]; break;
		case ECVAlternate: [_pendingFrame clear]; break;
	}
}

#pragma mark -

- (BOOL)setAlternateInterface:(UInt8)alternateSetting
{
	IOReturn const error = (*_interfaceInterface)->SetAlternateInterface(_interfaceInterface, alternateSetting);
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
- (BOOL)controlRequestWithType:(u_int8_t)type request:(u_int8_t)request value:(u_int16_t)v index:(u_int16_t)i length:(u_int16_t)length data:(void *)data
{
	IOUSBDevRequest r = { type, request, v, i, length, data, 0 };
	IOReturn const error = (*_interfaceInterface)->ControlRequest(_interfaceInterface, 0, &r);
	switch(error) {
		case kIOReturnSuccess: return YES;
		case kIOUSBPipeStalled: ECVIOReturn((*_interfaceInterface)->ClearPipeStall(_interfaceInterface, 0)); return YES;
		case kIOReturnNotResponding: return NO;
	}
	ECVIOReturn(error);
ECVGenericError:
ECVNoDeviceError:
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

#pragma mark -

#ifdef ECV_ENABLE_AUDIO
- (ECVAudioDevice *)audioInputOfCaptureHardware
{
	ECVAudioDevice *const input = [ECVAudioDevice deviceWithIODevice:_service input:YES];
	[input setName:_productName];
	return input;
}
- (ECVAudioDevice *)audioInput
{
	if(!_audioInput) _audioInput = [[self audioInputOfCaptureHardware] retain];
	if(!_audioInput) _audioInput = [[ECVAudioDevice defaultInputDevice] retain];
	return [[_audioInput retain] autorelease];
}
- (void)setAudioInput:(ECVAudioDevice *)device
{
	NSParameterAssert([device isInput] || !device);
	if(ECVEqualObjects(device, _audioInput)) return;
	ECVPauseWhile(self, {
		[_audioInput release];
		_audioInput = [device retain];
		[_audioPreviewingPipe release];
		_audioPreviewingPipe = nil;
	});
}
- (ECVAudioDevice *)audioOutput
{
	if(!_audioOutput) return _audioOutput = [[ECVAudioDevice defaultOutputDevice] retain];
	return [[_audioOutput retain] autorelease];
}
- (void)setAudioOutput:(ECVAudioDevice *)device
{
	NSParameterAssert(![device isInput] || !device);
	if(ECVEqualObjects(device, _audioOutput)) return;
	ECVPauseWhile(self, {
		[_audioOutput release];
		_audioOutput = [device retain];
		[_audioPreviewingPipe release];
		_audioPreviewingPipe = nil;
	});
}
- (BOOL)startAudio
{
	NSAssert(!_audioPreviewingPipe, @"Audio pipe should be cleared before restarting audio.");

	NSTimeInterval const timeSinceLastStop = [NSDate ECV_timeIntervalSinceReferenceDate] - _audioStopTime;
	usleep(MAX(0.75f - timeSinceLastStop, 0.0f) * ECVMicrosecondsPerSecond); // Don't let the audio be restarted too quickly.

	ECVAudioDevice *const input = [self audioInput];
	ECVAudioDevice *const output = [self audioOutput];

	ECVAudioStream *const inputStream = [[[input streams] objectEnumerator] nextObject];
	if(!inputStream) {
		ECVLog(ECVNotice, @"This device may not support audio (input: %@; stream: %@).", input, inputStream);
		return NO;
	}
	ECVAudioStream *const outputStream = [[[output streams] objectEnumerator] nextObject];
	if(!outputStream) {
		ECVLog(ECVWarning, @"Audio output could not be started (output: %@; stream: %@).", output, outputStream);
		return NO;
	}

	_audioPreviewingPipe = [[ECVAudioPipe alloc] initWithInputDescription:[inputStream basicDescription] outputDescription:[outputStream basicDescription] upconvertFromMono:[self upconvertsFromMono]];
	[_audioPreviewingPipe setVolume:_muted ? 0.0f : _volume];
	[input setDelegate:self];
	[output setDelegate:self];

	if(![input start]) {
		ECVLog(ECVWarning, @"Audio input could not be restarted (input: %@).", input);
		return NO;
	}
	if(![output start]) {
		[output stop];
		ECVLog(ECVWarning, @"Audio output could not be restarted (output: %@).", output);
		return NO;
	}
	return YES;
}
- (void)stopAudio
{
	ECVAudioDevice *const input = [self audioInput];
	ECVAudioDevice *const output = [self audioOutput];
	[input stop];
	[output stop];
	[input setDelegate:nil];
	[output setDelegate:nil];
	[_audioPreviewingPipe release];
	_audioPreviewingPipe = nil;
	_audioStopTime = [NSDate ECV_timeIntervalSinceReferenceDate];
}
#endif

#pragma mark -ECVCaptureDevice(Private)

#ifndef ECV_NO_CONTROLLERS
- (void)_startPlayingForControllers
{
	[[ECVController sharedController] noteCaptureDeviceStartedPlaying:self];
	[[self windowControllers] makeObjectsPerformSelector:@selector(startPlaying)];
}
- (void)_stopPlayingForControllers
{
	[[self windowControllers] makeObjectsPerformSelector:@selector(stopPlaying)];
	[[ECVController sharedController] noteCaptureDeviceStoppedPlaying:self];
}
#endif

#pragma mark -NSDocument

#ifndef ECV_NO_CONTROLLERS
- (void)addWindowController:(NSWindowController *)windowController
{
	[super addWindowController:windowController];
	[_windowControllersLock writeLock];
	if(NSNotFound == [_windowControllers2 indexOfObjectIdenticalTo:windowController]) [_windowControllers2 addObject:windowController];
	[_windowControllersLock unlock];
}
- (void)removeWindowController:(NSWindowController *)windowController
{
	[super removeWindowController:windowController];
	[_windowControllersLock writeLock];
	[_windowControllers2 removeObjectIdenticalTo:windowController];
	[_windowControllersLock unlock];
}
#endif

#pragma mark -

- (void)makeWindowControllers
{
#ifndef ECV_NO_CONTROLLERS
	[self addWindowController:[[[ECVCaptureController alloc] init] autorelease]];
#endif
}
- (NSString *)displayName
{
	return _productName ? _productName : @"";
}
- (void)close
{
	[self setPlaying:NO];
	[super close];
}

#pragma mark -NSObject

- (void)dealloc
{
	[[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
#ifndef ECV_NO_CONTROLLERS
	ECVConfigController *const config = [ECVConfigController sharedConfigController];
	if([config captureDevice] == self) [config setCaptureDevice:nil];
#endif

	if(_deviceInterface) (*_deviceInterface)->USBDeviceClose(_deviceInterface);
	if(_deviceInterface) (*_deviceInterface)->Release(_deviceInterface);
	if(_interfaceInterface) (*_interfaceInterface)->Release(_interfaceInterface);

#ifndef ECV_NO_CONTROLLERS
	[_windowControllersLock release];
	[_windowControllers2 release];
#endif
	IOObjectRelease(_service);
	[_productName release];
	IOObjectRelease(_deviceRemovedNotification);
	[_playLock release];
#ifdef ECV_ENABLE_AUDIO
	[_audioInput release];
	[_audioOutput release];
	[_audioPreviewingPipe release];
#endif
	[super dealloc];
}

#pragma mark -<ECVAudioDeviceDelegate>

#ifdef ECV_ENABLE_AUDIO
- (void)audioDevice:(ECVAudioDevice *)sender didReceiveInput:(AudioBufferList const *)bufferList atTime:(AudioTimeStamp const *)t
{
	if(sender != _audioInput) return;
	[_audioPreviewingPipe receiveInputBufferList:bufferList];
	[_windowControllersLock readLock];
	[_windowControllers2 makeObjectsPerformSelector:@selector(threaded_pushAudioBufferListValue:) withObject:[NSValue valueWithPointer:bufferList]];
	[_windowControllersLock unlock];
}
- (void)audioDevice:(ECVAudioDevice *)sender didRequestOutput:(inout AudioBufferList *)bufferList forTime:(AudioTimeStamp const *)t
{
	if(sender != _audioOutput) return;
	[_audioPreviewingPipe requestOutputBufferList:bufferList];
}
#endif

#pragma mark -<ECVCaptureControllerConfiguring>

#ifdef ECV_ENABLE_AUDIO
- (BOOL)isMuted
{
	return _muted;
}
- (void)setMuted:(BOOL)flag
{
	if(flag == _muted) return;
	_muted = flag;
	[_audioPreviewingPipe setVolume:_muted ? 0.0f : _volume];
	[[NSNotificationCenter defaultCenter] postNotificationName:ECVCaptureDeviceVolumeDidChangeNotification object:self];
}
- (CGFloat)volume
{
	return _volume;
}
- (void)setVolume:(CGFloat)value
{
	_volume = CLAMP(0.0f, value, 1.0f);
	[_audioPreviewingPipe setVolume:_muted ? 0.0f : _volume];
	[[NSUserDefaults standardUserDefaults] setDouble:value forKey:ECVVolumeKey];
	[[NSNotificationCenter defaultCenter] postNotificationName:ECVCaptureDeviceVolumeDidChangeNotification object:self];
}
- (BOOL)upconvertsFromMono
{
	return _upconvertsFromMono;
}
- (void)setUpconvertsFromMono:(BOOL)flag
{
	ECVPauseWhile(self, { _upconvertsFromMono = flag; });
	[[NSUserDefaults standardUserDefaults] setBool:flag forKey:ECVUpconvertsFromMonoKey];
}
#endif

@end
