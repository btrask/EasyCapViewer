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
@class ECVVideoFrame;
@class ECVDeinterlacingMode;

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

	ECVDeinterlacingMode *_deinterlacingMode;
	ECVVideoStorage *_videoStorage;
	NSConditionLock *_playLock;
	BOOL _firstFrame;
	ECVVideoFrame *_pendingFrame;
	ECVVideoFrame *_lastCompletedFrame;

#if defined(ECV_ENABLE_AUDIO)
	ECVAudioDevice *_audioInput;
	ECVAudioDevice *_audioOutput;
	ECVAudioPipe *_audioPreviewingPipe;
	NSTimeInterval _audioStopTime;
	BOOL _muted;
	CGFloat _volume;
	BOOL _upconvertsFromMono;
#endif
}

+ (NSArray *)deviceDictionaries;
+ (Class)getMatchingDictionary:(out NSDictionary **)outDict forDeviceDictionary:(NSDictionary *)deviceDict;
+ (NSArray *)devicesWithIterator:(io_iterator_t)iterator;

- (id)initWithService:(io_service_t)service error:(out NSError **)outError;
- (void)noteDeviceRemoved;
- (void)workspaceWillSleep:(NSNotification *)aNotif;

@property(assign, getter = isPlaying) BOOL playing;
- (void)togglePlaying;
@property(nonatomic, assign) ECVDeinterlacingMode *deinterlacingMode;

@property(readonly) BTUserDefaults *defaults;
@property(readonly) ECVVideoStorage *videoStorage;
@property(readonly) NSUInteger simultaneousTransfers;
@property(readonly) NSUInteger microframesPerTransfer;

- (void)startPlaying;
- (void)threadMain_play;
- (void)threaded_readImageBytes:(u_int8_t const *)bytes length:(size_t)length;
- (void)threaded_startNewImageWithFieldType:(ECVFieldType)fieldType;

- (BOOL)setAlternateInterface:(u_int8_t)alternateSetting;
- (BOOL)controlRequestWithType:(u_int8_t)type request:(u_int8_t)request value:(u_int16_t)v index:(u_int16_t)i length:(u_int16_t)length data:(void *)data;
- (BOOL)writeIndex:(u_int16_t)i value:(u_int16_t)v;
- (BOOL)readIndex:(u_int16_t)i value:(out u_int8_t *)outValue;
- (BOOL)setFeatureAtIndex:(u_int16_t)i;

#if defined(ECV_ENABLE_AUDIO)
@property(readonly) ECVAudioDevice *audioInputOfCaptureHardware;
@property(nonatomic, retain) ECVAudioDevice *audioInput;
@property(nonatomic, retain) ECVAudioDevice *audioOutput;
- (BOOL)startAudio;
- (void)stopAudio;
#endif

@end

@interface ECVCaptureDevice(ECVAbstract)

@property(readonly) BOOL requiresHighSpeed;
@property(readonly) ECVIntegerSize captureSize;
@property(readonly) UInt8 isochReadingPipe;
@property(readonly) QTTime frameRate;
@property(readonly) OSType pixelFormatType;

- (BOOL)threaded_play;
- (BOOL)threaded_pause;
- (BOOL)threaded_watchdog;

@end
