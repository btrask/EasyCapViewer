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

#define ECVPauseWhile(obj, code) do {\
	ECVCaptureDevice *const __obj = (obj);\
	BOOL const __p = [__obj isPlaying];\
	if(__p) [__obj setPlaying:NO];\
	({code});\
	if(__p) [__obj setPlaying:YES];\
} while(NO)

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
	IOUSBDeviceInterface320 **_deviceInterface;
	IOUSBInterfaceInterface300 **_interfaceInterface;
	UInt32 _frameTime;

	Class _deinterlacingMode;
	ECVVideoStorage *_videoStorage;
	NSConditionLock *_playLock;

#if defined(ECV_ENABLE_AUDIO)
	ECVAudioInput *_audioInput;
	ECVAudioOutput *_audioOutput;
	ECVAudioPipe *_audioPreviewingPipe;
	NSTimeInterval _audioStopTime;
	BOOL _muted;
	CGFloat _volume;
	BOOL _upconvertsFromMono;
#endif
}

+ (NSArray *)deviceClasses;
+ (void)registerDeviceClass:(Class)cls; // Add the device to ECVDevices.plist instead, if possible.
+ (void)unregisterDeviceClass:(Class)cls;

+ (NSDictionary *)deviceDictionary;
+ (NSDictionary *)matchingDictionary;
+ (NSArray *)devicesWithIterator:(io_iterator_t)iterator;

- (id)initWithService:(io_service_t)service error:(out NSError **)outError;
- (void)noteDeviceRemoved;
- (void)workspaceWillSleep:(NSNotification *)aNotif;

@property(assign, getter = isPlaying) BOOL playing;
- (void)togglePlaying;
@property(nonatomic, assign) Class deinterlacingMode;

@property(readonly) BTUserDefaults *defaults;
@property(readonly) ECVVideoStorage *videoStorage;
@property(readonly) NSUInteger simultaneousTransfers;
@property(readonly) NSUInteger microframesPerTransfer;

- (void)startPlaying;
- (void)threadMain_play;
- (void)threaded_nextFieldType:(ECVFieldType)fieldType;
- (void)threaded_drawPixelBuffer:(ECVPixelBuffer *)buffer atPoint:(ECVIntegerPoint)point;

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

@end

@interface ECVCaptureDevice(ECVAbstract)

@property(readonly) BOOL requiresHighSpeed;
@property(readonly) ECVIntegerSize captureSize;
@property(readonly) UInt8 isochReadingPipe;
@property(readonly) QTTime frameRate;
@property(readonly) OSType pixelFormat;

- (BOOL)threaded_play;
- (BOOL)threaded_pause;
- (BOOL)threaded_watchdog;
- (void)threaded_readBytes:(UInt8 const *)bytes length:(size_t)length;

@end
