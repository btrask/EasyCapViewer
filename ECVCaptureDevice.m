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
#ifdef ECV_DEPENDENT_VIDEO_STORAGE
	#import "ECVDependentVideoStorage.h"
	#define ECV_VIDEO_STORAGE_CLASS ECVDependentVideoStorage
#else
	#import "ECVVideoStorage.h"
	#define ECV_VIDEO_STORAGE_CLASS ECVVideoStorage
#endif
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

NSString *const ECVDeinterlacingModeKey = @"ECVDeinterlacingMode";
NSString *const ECVBrightnessKey = @"ECVBrightness";
NSString *const ECVContrastKey = @"ECVContrast";
NSString *const ECVHueKey = @"ECVHue";
NSString *const ECVSaturationKey = @"ECVSaturation";

NSString *const ECVCaptureDeviceErrorDomain = @"ECVCaptureDeviceError";

static NSString *const ECVVolumeKey = @"ECVVolume";

enum {
	ECVNotPlaying,
	ECVStartPlaying,
	ECVPlaying,
	ECVStopPlaying
}; // _playLock

@interface ECVCaptureDevice(Private)

- (void)_startPlayingWithStorage:(ECVVideoStorage *)storage;
- (void)_stopPlaying;

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
+ (BOOL)deviceAddedWithIterator:(io_iterator_t)iterator
{
	io_service_t service = IO_OBJECT_NULL;
	BOOL created = NO;
	while((service = IOIteratorNext(iterator))) {
		NSError *error = nil;
		ECVCaptureDevice *const device = [[[self alloc] initWithService:service error:&error] autorelease];
		if(device) {
			[[NSDocumentController sharedDocumentController] addDocument:device];
			[device makeWindowControllers];
			[device showWindows];
			created = YES;
		} else if(error) [[NSAlert alertWithError:error] runModal];
		IOObjectRelease(service);
	}
	return created;
}

#pragma mark +NSObject

+ (void)initialize
{
	[[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithInteger:ECVWeave], ECVDeinterlacingModeKey,
		[NSNumber numberWithDouble:0.5f], ECVBrightnessKey,
		[NSNumber numberWithDouble:0.5f], ECVContrastKey,
		[NSNumber numberWithDouble:0.5f], ECVHueKey,
		[NSNumber numberWithDouble:0.5f], ECVSaturationKey,
		[NSNumber numberWithDouble:1.0f], ECVVolumeKey,
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

	_windowControllersLock = [[ECVReadWriteLock alloc] init];
	_windowControllers2 = [[NSMutableArray alloc] init];

	[[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(workspaceWillSleep:) name:NSWorkspaceWillSleepNotification object:[NSWorkspace sharedWorkspace]];

#ifndef ECV_DISABLE_AUDIO
	[self setVolume:[[NSUserDefaults standardUserDefaults] doubleForKey:ECVVolumeKey]];
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

	ECVIOReturn((*devicePlugInInterface)->QueryInterface(devicePlugInInterface, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID), (LPVOID)&_deviceInterface));
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
		if(![self isPlaying]) {
			[_playLock unlockWithCondition:ECVStartPlaying];
			[NSThread detachNewThreadSelector:@selector(threaded_readIsochPipeAsync) toTarget:self withObject:nil];
		} else [_playLock unlock];
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
			[_playLock unlockWithCondition:ECVStartPlaying];
			[NSThread detachNewThreadSelector:@selector(threaded_readIsochPipeAsync) toTarget:self withObject:nil];
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

#pragma mark -

#ifndef ECV_DISABLE_AUDIO
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

	NSTimeInterval const timeSinceLastStop = [NSDate timeIntervalSinceReferenceDate] - _audioStopTime;
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

	_audioPreviewingPipe = [[ECVAudioPipe alloc] initWithInputDescription:[inputStream basicDescription] outputDescription:[outputStream basicDescription]];
	[_audioPreviewingPipe setVolume:_volume];
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
	_audioStopTime = [NSDate timeIntervalSinceReferenceDate];
}
#endif

#pragma mark -

- (void)threaded_readIsochPipeAsync
{
	NSAutoreleasePool *const pool = [[NSAutoreleasePool alloc] init];

	UInt8 *fullFrameData = NULL;
	IOUSBLowLatencyIsocFrame *fullFrameList = NULL;

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

	NSUInteger const simultaneousTransfers = [self simultaneousTransfers];
	NSUInteger const microframesPerTransfer = [self microframesPerTransfer];
	UInt8 const pipe = [self isochReadingPipe];
	NSUInteger i;

	UInt16 frameRequestSize = 0;
	UInt8 ignored1 = 0, ignored2 = 0, ignored3 = 0 , ignored4 = 0;
	ECVIOReturn((*_interfaceInterface)->GetPipeProperties(_interfaceInterface, pipe, &ignored1, &ignored2, &ignored3, &frameRequestSize, &ignored4));
	NSParameterAssert(frameRequestSize);

	ECVIOReturn((*_interfaceInterface)->LowLatencyCreateBuffer(_interfaceInterface, (void **)&fullFrameData, frameRequestSize * microframesPerTransfer * simultaneousTransfers, kUSBLowLatencyReadBuffer));
	ECVIOReturn((*_interfaceInterface)->LowLatencyCreateBuffer(_interfaceInterface, (void **)&fullFrameList, sizeof(IOUSBLowLatencyIsocFrame) * microframesPerTransfer * simultaneousTransfers, kUSBLowLatencyFrameListBuffer));
	for(i = 0; i < microframesPerTransfer * simultaneousTransfers; i++) {
		fullFrameList[i].frStatus = kIOReturnInvalid; // Ignore them to start out.
		fullFrameList[i].frReqCount = frameRequestSize;
	}

	UInt64 currentFrame = 0;
	AbsoluteTime ignored;
	ECVIOReturn((*_interfaceInterface)->GetBusFrameNumber(_interfaceInterface, &currentFrame, &ignored));
	currentFrame += 10;

	_firstFrame = YES;

	ECVVideoStorage *const storage = [[[ECV_VIDEO_STORAGE_CLASS alloc] initWithPixelFormatType:kCVPixelFormatType_422YpCbCr8 deinterlacingMode:_deinterlacingMode originalSize:[self captureSize] frameRate:[self frameRate]] autorelease]; // AKA k2vuyPixelFormat or k422YpCbCr8CodecType.
	[self performSelectorOnMainThread:@selector(_startPlayingWithStorage:) withObject:storage waitUntilDone:YES];

	while([_playLock condition] == ECVPlaying) {
		NSAutoreleasePool *const innerPool = [[NSAutoreleasePool alloc] init];
		if(![self threaded_watchdog]) {
			ECVLog(ECVError, @"Invalid device watchdog result.");
			[innerPool release];
			break;
		}
		NSUInteger transfer = 0;
		for(; transfer < simultaneousTransfers; transfer++ ) {
			UInt8 *const frameData = fullFrameData + frameRequestSize * microframesPerTransfer * transfer;
			IOUSBLowLatencyIsocFrame *const frameList = fullFrameList + microframesPerTransfer * transfer;
			for(i = 0; i < microframesPerTransfer; i++) {
				if(kUSBLowLatencyIsochTransferKey == frameList[i].frStatus && i) {
					Nanoseconds const nextUpdateTime = UInt64ToUnsignedWide(UnsignedWideToUInt64(AbsoluteToNanoseconds(frameList[i - 1].frTimeStamp)) + 1e6); // LowLatencyReadIsochPipeAsync() only updates every millisecond at most.
					mach_wait_until(UnsignedWideToUInt64(NanosecondsToAbsolute(nextUpdateTime)));
				}
				while(kUSBLowLatencyIsochTransferKey == frameList[i].frStatus) usleep(100); // In case we haven't slept long enough already.
				[self threaded_readImageBytes:frameData + i * frameRequestSize length:(size_t)frameList[i].frActCount];
				frameList[i].frStatus = kUSBLowLatencyIsochTransferKey;
			}
			ECVIOReturn((*_interfaceInterface)->LowLatencyReadIsochPipeAsync(_interfaceInterface, pipe, frameData, currentFrame, microframesPerTransfer, 1, frameList, ECVDoNothing, NULL));
			currentFrame += microframesPerTransfer / (kUSBFullSpeedMicrosecondsInFrame / _frameTime);
		}
		[innerPool drain];
	}

	[self threaded_pause];
ECVGenericError:
ECVNoDeviceError:
	[self performSelectorOnMainThread:@selector(_stopPlaying) withObject:nil waitUntilDone:NO];

	if(fullFrameData) (*_interfaceInterface)->LowLatencyDestroyBuffer(_interfaceInterface, fullFrameData);
	if(fullFrameList) (*_interfaceInterface)->LowLatencyDestroyBuffer(_interfaceInterface, fullFrameList);
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
	if(frameToDraw) {
		[_windowControllersLock readLock];
		[_windowControllers2 makeObjectsPerformSelector:@selector(threaded_pushFrame:) withObject:frameToDraw];
		[_windowControllersLock unlock];
	}

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
- (BOOL)controlRequestWithType:(UInt8)type request:(UInt8)request value:(UInt16)value index:(UInt16)index length:(UInt16)length data:(void *)data
{
	IOUSBDevRequest r = { type, request, value, index, length, data, 0 };
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
- (BOOL)writeValue:(UInt16)value atIndex:(UInt16)index
{
	return [self controlRequestWithType:USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice) request:kUSBRqClearFeature value:value index:index length:0 data:NULL];
}
- (BOOL)readValue:(out SInt32 *)outValue atIndex:(UInt16)index
{
	SInt32 v = 0;
	BOOL const r = [self controlRequestWithType:USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice) request:kUSBRqGetStatus value:0 index:index length:sizeof(v) data:&v];
	if(outValue) *outValue = CFSwapInt32LittleToHost(v);
	return r;
}
- (BOOL)setFeatureAtIndex:(UInt16)index
{
	return [self controlRequestWithType:USBmakebmRequestType(kUSBOut, kUSBStandard, kUSBDevice) request:kUSBRqSetFeature value:0 index:index length:0 data:NULL];
}

#pragma mark -ECVCaptureDevice(Private)

- (void)_startPlayingWithStorage:(ECVVideoStorage *)storage
{
	[_videoStorage autorelease];
	_videoStorage = [storage retain];
#ifndef ECV_NO_CONTROLLERS
	[[ECVController sharedController] noteCaptureDeviceStartedPlaying:self];
#endif
#ifndef ECV_DISABLE_AUDIO
	(void)[self startAudio];
#endif
	[[self windowControllers] makeObjectsPerformSelector:@selector(startPlaying)];
}
- (void)_stopPlaying
{
	[[self windowControllers] makeObjectsPerformSelector:@selector(stopPlaying)];
#ifndef ECV_DISABLE_AUDIO
	[self stopAudio];
#endif
#ifndef ECV_NO_CONTROLLERS
	[[ECVController sharedController] noteCaptureDeviceStoppedPlaying:self];
#endif
}

#pragma mark -NSDocument

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

	[_windowControllersLock release];
	[_windowControllers2 release];
	IOObjectRelease(_service);
	[_productName release];
	IOObjectRelease(_deviceRemovedNotification);
	[_playLock release];
#ifndef ECV_DISABLE_AUDIO
	[_audioInput release];
	[_audioOutput release];
	[_audioPreviewingPipe release];
#endif
	[super dealloc];
}

#pragma mark -<ECVAudioDeviceDelegate>

#ifndef ECV_DISABLE_AUDIO
- (void)audioDevice:(ECVAudioDevice *)sender didReceiveInput:(AudioBufferList const *)bufferList atTime:(AudioTimeStamp const *)time
{
	if(sender != _audioInput) return;
	[_audioPreviewingPipe receiveInputBufferList:bufferList];
	[_windowControllersLock readLock];
	[_windowControllers2 makeObjectsPerformSelector:@selector(threaded_pushAudioBufferListValue:) withObject:[NSValue valueWithPointer:bufferList]];
	[_windowControllersLock unlock];
}
- (void)audioDevice:(ECVAudioDevice *)sender didRequestOutput:(inout AudioBufferList *)bufferList forTime:(AudioTimeStamp const *)time
{
	if(sender != _audioOutput) return;
	[_audioPreviewingPipe requestOutputBufferList:bufferList];
}
#endif

#pragma mark -<ECVCaptureControllerConfiguring>

#ifndef ECV_DISABLE_AUDIO
- (CGFloat)volume
{
	return _volume;
}
- (void)setVolume:(CGFloat)value
{
	_volume = value;
	[_audioPreviewingPipe setVolume:value];
	[[NSUserDefaults standardUserDefaults] setDouble:value forKey:ECVVolumeKey];
}
#endif

@end
