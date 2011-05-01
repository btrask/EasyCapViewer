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
#import "ECVVideoSource.h"
#import <IOKit/usb/IOUSBLib.h>

// Models/Sources/Video/USB
@class ECVUSBTransferList;

@interface ECVUSBVideoSource : ECVVideoSource
{
	@private
	io_service_t _service;
	NSDictionary *_properties;
	io_object_t _deviceRemovedNotification; // TODO: Not implemented yet.
	IOUSBDeviceInterface320 **_USBDevice;
	IOUSBInterfaceInterface300 **_USBInterface;
	NSLock *_readThreadLock;
	NSLock *_readLock;
	BOOL _read;
}

+ (NSDictionary *)matchingDictionary;
+ (IOUSBDeviceInterface320 **)USBDeviceWithService:(io_service_t)service;
+ (IOUSBInterfaceInterface300 **)USBInterfaceWithDevice:(IOUSBDeviceInterface320 **)device;

- (id)initWithService:(io_service_t)service;

@property(readonly) io_service_t service;
@property(readonly) IOUSBDeviceInterface320 **USBDevice;
@property(readonly) IOUSBInterfaceInterface300 **USBInterface;

- (ECVUSBTransferList *)transferListWithFrameRequestSize:(NSUInteger)frameRequestSize;
- (id)valueForProperty:(char const *)nullTerminatedCString;

- (BOOL)setAlternateInterface:(u_int8_t)alternateSetting;
- (BOOL)controlRequestWithType:(u_int8_t)type request:(u_int8_t)request value:(u_int16_t)v index:(u_int16_t)i length:(u_int16_t)length data:(void *)data;
- (BOOL)writeIndex:(u_int16_t)i value:(u_int16_t)v;
- (BOOL)readIndex:(u_int16_t)i value:(out u_int8_t *)outValue;
- (BOOL)setFeatureAtIndex:(u_int16_t)i;

//- (void)deviceDidDisconnect:(NSNotification *)aNotif;
//- (void)workspaceWillSleep:(NSNotification *)aNotif;

@end

@interface ECVUSBVideoSource(ECVRead_Thread)

- (void)read;
- (BOOL)keepReading;

@end

@interface ECVUSBVideoSource(ECVReadAbstract_Thread)

- (void)readBytes:(UInt8 const *)bytes length:(NSUInteger)length;

@end

@interface ECVUSBVideoSource(ECVAbstract)

@property(readonly) UInt8 pipeRef;
@property(readonly) UInt32 maximumMicrosecondsInFrame; // kUSBFullSpeedMicrosecondsInFrame or kUSBHighSpeedMicrosecondsInFrame.

@end
