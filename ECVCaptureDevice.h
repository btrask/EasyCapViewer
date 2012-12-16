/* Copyright (c) 2009-2010, Ben Trask
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
#import <IOKit/usb/IOUSBLib.h>
#import <QTKit/QTKit.h>

// Models
@class ECVVideoFormat;
@class ECVVideoStorage;
@class ECVPixelBuffer;
@class ECVVideoFrame;

// Controllers
#import "ECVConfigController.h"

// Other Sources
#if defined(ECV_ENABLE_AUDIO)
#import "ECVAudioDevice.h"
@class ECVAudioPipe;
#endif
@class ECVReadWriteLock;

// External
@class BTUserDefaults;

extern NSString *const ECVDeinterlacingModeKey;
extern NSString *const ECVBrightnessKey;
extern NSString *const ECVContrastKey;
extern NSString *const ECVHueKey;
extern NSString *const ECVSaturationKey;

extern NSString *const ECVCaptureDeviceErrorDomain;

extern NSString *const ECVCaptureDeviceVolumeDidChangeNotification;

@interface ECVCaptureDevice : NSDocument <ECVCaptureDeviceConfiguring
#if defined(ECV_ENABLE_AUDIO)
, ECVAudioDeviceDelegate
#endif
>
{
	@private
	BTUserDefaults *_defaults;
#if !defined(ECV_NO_CONTROLLERS)
	ECVReadWriteLock *_windowControllersLock;
	NSMutableArray *_windowControllers2;
#endif

	io_service_t _service;
	NSString *_productName;
	io_object_t _deviceRemovedNotification;

	Class _deinterlacingMode;
	ECVVideoStorage *_videoStorage;
	NSTimeInterval _stopTime;

#if defined(ECV_ENABLE_AUDIO)
	ECVAudioInput *_audioInput;
	ECVAudioOutput *_audioOutput;
	ECVAudioPipe *_audioPreviewingPipe;
	BOOL _muted;
	CGFloat _volume;
	BOOL _upconvertsFromMono;
#endif

// New ivars...

	ECVVideoFormat *_videoFormat;
	NSUInteger _pauseCount;
	BOOL _pausedFromUI;

	IOUSBDeviceInterface320 **_USBDevice;
	IOUSBInterfaceInterface300 **_USBInterface;
	NSLock *_readThreadLock;
	NSLock *_readLock;
	BOOL _read;
}

+ (NSArray *)deviceClasses;
+ (void)registerDeviceClass:(Class const)cls; // Add the device to ECVDevices.plist instead, if possible.
+ (void)unregisterDeviceClass:(Class const)cls;

+ (NSDictionary *)deviceDictionary;
+ (NSDictionary *)matchingDictionary;
+ (NSArray *)devicesWithIterator:(io_iterator_t const)iterator;

+ (IOUSBDeviceInterface320 **)USBDeviceWithService:(io_service_t const)service;
+ (IOUSBInterfaceInterface300 **)USBInterfaceWithDevice:(IOUSBDeviceInterface320 **const)device;

- (id)initWithService:(io_service_t const)service error:(out NSError **const)outError;
- (void)noteDeviceRemoved;
- (void)workspaceWillSleep:(NSNotification *const)aNotif;

- (Class)deinterlacingMode;
- (void)setDeinterlacingMode:(Class const)mode;
- (BTUserDefaults *)defaults;
- (ECVVideoStorage *)videoStorage;

- (BOOL)setAlternateInterface:(u_int8_t)alternateSetting;
- (BOOL)controlRequestWithType:(u_int8_t)type request:(UInt8 const)request value:(UInt16 const)v index:(UInt16 const)i length:(UInt16 const)length data:(inout void *const)data;
- (BOOL)readRequest:(UInt8 const)request value:(UInt16 const)v index:(UInt16 const)i length:(UInt16 const)length data:(out void *const)data;
- (BOOL)writeRequest:(UInt8 const)request value:(UInt16 const)v index:(UInt16 const)i length:(UInt16 const)length data:(in void *const)data;

#if defined(ECV_ENABLE_AUDIO)
@property(readonly) ECVAudioInput *audioInputOfCaptureHardware;
@property(nonatomic, retain) ECVAudioInput *audioInput;
@property(nonatomic, retain) ECVAudioOutput *audioOutput;
- (BOOL)startAudio;
- (void)stopAudio;
#endif




// Ongoing refactoring... This code is new, the above code is not.

- (ECVVideoFormat *)videoFormat;
- (void)setVideoFormat:(ECVVideoFormat *const)format;

- (NSUInteger)pauseCount;
- (BOOL)isPaused;
- (void)setPaused:(BOOL const)flag;
- (BOOL)pausedFromUI;
- (void)setPausedFromUI:(BOOL const)flag;
- (void)togglePausedFromUI;

- (void)play;
- (void)stop;

- (NSString *)name;
- (io_service_t)service;

- (void)finishedFrame:(ECVVideoFrame *const)frame; // TODO: Part of the gradual split into two separate objects.

@end

@interface ECVCaptureDevice(ECVRead_Thread)

- (void)read;
- (BOOL)keepReading;

@end

@interface ECVCaptureDevice(ECVReadAbstract_Thread)

- (void)writeBytes:(UInt8 const *const)bytes length:(NSUInteger const)length toStorage:(ECVVideoStorage *const)storage;

@end

@interface ECVCaptureDevice(ECVAbstract)

- (UInt32)maximumMicrosecondsInFrame;
- (NSSet *)supportedVideoFormats;
- (OSType)pixelFormat;

@end
