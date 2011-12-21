/* Copyright (c) 2009, Ben Trask
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
#if defined(ECV_ENABLE_AUDIO)
#import <CoreAudio/CoreAudio.h>

extern NSString *const ECVAudioHardwareDevicesDidChangeNotification;

@protocol ECVAudioDeviceDelegate;

@interface ECVAudioDevice : NSObject
{
	@private
	IBOutlet NSObject<ECVAudioDeviceDelegate> *delegate;
	AudioDeviceID _deviceID;
	NSString *_name;
	AudioDeviceIOProcID _procID;
}

+ (NSArray *)allDevices;
+ (id)defaultDevice;
+ (id)deviceWithUID:(NSString *)UID;
+ (id)deviceWithIODevice:(io_service_t)device;

- (id)initWithDeviceID:(AudioDeviceID)deviceID;

- (NSObject<ECVAudioDeviceDelegate> *)delegate;
- (void)setDelegate:(NSObject<ECVAudioDeviceDelegate> *)obj;
- (AudioDeviceID)deviceID;
- (BOOL)isInput;
- (NSString *)UID;

- (NSString *)name;
- (void)setName:(NSString *)str;
- (NSArray *)streams;

- (BOOL)start;
- (void)stop;

@end

@interface ECVAudioDevice(ECVAbstract)

+ (BOOL)isInput;

@end

@interface ECVAudioInput : ECVAudioDevice
@end
@interface ECVAudioOutput : ECVAudioDevice
@end

@protocol ECVAudioDeviceDelegate <NSObject>

@optional
- (void)audioInput:(ECVAudioInput *)sender didReceiveBufferList:(AudioBufferList const *)bufferList atTime:(AudioTimeStamp const *)t;
- (void)audioOutput:(ECVAudioOutput *)sender didRequestBufferList:(inout AudioBufferList *)bufferList forTime:(AudioTimeStamp const *)t;

@end

@interface ECVAudioStream : NSObject
{
	@private
	AudioStreamID _streamID;
}

- (id)initWithStreamID:(AudioStreamID)streamID;
- (AudioStreamID)streamID;

- (AudioStreamBasicDescription)basicDescription;

@end
#endif
