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
#import "ECVConfigController.h"
#import "ECVAVTarget.h"

// For subclassers
#import "ECVVideoSource.h"
#import "ECVVideoFormat.h"
#import "ECVVideoStorage.h"
#import "ECVPixelBuffer.h"
#import "ECVPixelFormat.h"

// Models
@class ECVCaptureDocument;
@class ECVVideoFrame;

extern NSString *const ECVDeinterlacingModeKey;

extern NSString *const ECVBrightnessKey;
extern NSString *const ECVContrastKey;
extern NSString *const ECVSaturationKey;
extern NSString *const ECVHueKey;

@interface ECVCaptureDevice : NSObject <ECVAVTarget, ECVCaptureDeviceConfiguring>
{
	@private
	io_service_t _service;
	BOOL _valid;
	io_object_t _deviceRemovedNotification;

	NSString *_productName;

	Class _deinterlacingMode;
	ECVVideoStorage *_videoStorage;
	NSTimeInterval _stopTime;

// New ivars...

	ECVCaptureDocument *_captureDocument;

	ECVVideoSource *_videoSource;
	ECVVideoFormat *_videoFormat;

	IOUSBDeviceInterface320 **_USBDevice;
	IOUSBInterfaceInterface300 **_USBInterface;
	NSLock *_readThreadLock;
	NSLock *_readLock;
	BOOL _read;
	CFRunLoopSourceRef _ignoredEventSource;
}

+ (NSArray *)deviceClasses;
+ (void)registerDeviceClass:(Class const)cls; // Add the device to ECVDevices.plist instead, if possible.
+ (void)unregisterDeviceClass:(Class const)cls;

+ (NSDictionary *)deviceDictionary;
+ (NSDictionary *)matchingDictionary;
+ (NSArray *)devicesWithIterator:(io_iterator_t const)iterator;

+ (IOUSBDeviceInterface320 **)USBDeviceWithService:(io_service_t const)service;
+ (IOUSBInterfaceInterface300 **)USBInterfaceWithDevice:(IOUSBDeviceInterface320 **const)device;

- (id)initWithService:(io_service_t const)service;
- (BOOL)isValid;
- (void)invalidate;

- (Class)deinterlacingMode;
- (void)setDeinterlacingMode:(Class const)mode;
- (ECVVideoStorage *)videoStorage;

- (BOOL)setAlternateInterface:(u_int8_t)alternateSetting;
- (BOOL)controlRequestWithType:(u_int8_t)type request:(UInt8 const)request value:(UInt16 const)v index:(UInt16 const)i length:(UInt16 const)length data:(inout void *const)data;
- (BOOL)readRequest:(UInt8 const)request value:(UInt16 const)v index:(UInt16 const)i length:(UInt16 const)length data:(out void *const)data;
- (BOOL)writeRequest:(UInt8 const)request value:(UInt16 const)v index:(UInt16 const)i length:(UInt16 const)length data:(in void *const)data;




// Ongoing refactoring... This code is new, the above code is not.

- (ECVCaptureDocument *)captureDocument;
- (void)setCaptureDocument:(ECVCaptureDocument *const)doc;

- (ECVVideoSource *)videoSource;
- (void)setVideoSource:(ECVVideoSource *const)source;
- (void)loadPreferredVideoSource;
- (ECVVideoFormat *)videoFormat;
- (void)setVideoFormat:(ECVVideoFormat *const)format;
- (void)loadPreferredVideoFormat;

- (NSString *)name;
- (io_service_t)service;

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
- (NSArray *)supportedVideoSources;
- (ECVVideoSource *)defaultVideoSource;
- (NSSet *)supportedVideoFormats;
- (ECVVideoFormat *)defaultVideoFormat;
- (OSType)pixelFormat;

@end
