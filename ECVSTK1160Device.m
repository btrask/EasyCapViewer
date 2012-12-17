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
#import "ECVSTK1160Device.h"
#import "stk11xx.h"

// Video
#import "ECVVideoSource.h"
#import "ECVVideoFormat.h"
#import "ECVVideoStorage.h"
#import "ECVPixelBuffer.h"

// Other Sources
#import "ECVDebug.h"
#import "ECVPixelFormat.h"

enum {
	ECVSTK1160HighFieldFlag = 1 << 6,
	ECVSTK1160NewImageFlag = 1 << 7,
};

@interface ECVVideoSource(ECVSTK1160Device)
- (BOOL)writeToDevice:(ECVSTK1160Device *const)device;
- (u_int8_t)hardwareSource;
@end
@interface ECVSTK11X0VideoSource_SVideo : ECVVideoSource
@end
@interface ECVSTK11X0VideoSource_CompositeGeneric : ECVVideoSource
@end
@interface ECVSTK11X0VideoSource_Composite1 : ECVSTK11X0VideoSource_CompositeGeneric
@end
@interface ECVSTK11X0VideoSource_Composite2 : ECVSTK11X0VideoSource_CompositeGeneric
@end
@interface ECVSTK11X0VideoSource_Composite3 : ECVSTK11X0VideoSource_CompositeGeneric
@end
@interface ECVSTK11X0VideoSource_Composite4 : ECVSTK11X0VideoSource_CompositeGeneric
@end

@interface ECVSTK1160Device(Private)

- (BOOL)_initializeAudio;
- (BOOL)_initializeResolution;
- (BOOL)_setStreaming:(BOOL)flag;
- (BOOL)_SAA711XExpect:(u_int8_t)val;

@end

@implementation ECVSTK1160Device

#pragma mark -ECVSTK1160Device

- (BOOL)readIndex:(UInt16 const)i value:(out UInt8 *const)outValue
{
	UInt8 v = 0;
	BOOL const r = [self readRequest:kUSBRqGetStatus value:0 index:i length:sizeof(v) data:&v];
	if(outValue) *outValue = v;
	return r;
}
- (BOOL)writeIndex:(UInt16 const)i value:(UInt8 const)v
{
	return [self writeRequest:kUSBRqClearFeature value:v index:i length:0 data:NULL];
}
- (BOOL)setFeatureAtIndex:(u_int16_t)i
{
	return [self controlRequestWithType:USBmakebmRequestType(kUSBOut, kUSBStandard, kUSBDevice) request:kUSBRqSetFeature value:0 index:i length:0 data:NULL];
}

#pragma mark -ECVSTK1160Device(Private)

- (BOOL)_initializeAudio
{
	if(![self writeVT1612ARegister:0x94 value:0x00]) return NO;
	if(![self writeIndex:0x0506 value:0x01]) return NO;
	if(![self writeIndex:0x0507 value:0x00]) return NO;
	if(![_VT1612AChip initialize]) return NO;
	ECVLog(ECVNotice, @"Device audio version: %@", [_VT1612AChip vendorAndRevisionString]);
	return YES;
}
- (BOOL)_initializeResolution
{
	ECVIntegerSize inputSize = [[self videoFormat] frameSize]; // TODO: Clean up this whole method.
	inputSize.height *= 2;
	ECVIntegerSize standardSize = inputSize;
	switch(inputSize.width) {
		case 704:
		case 352:
		case 176:
			inputSize.width = 704;
			standardSize.width = 706;
			break;
		case 640:
		case 320:
		case 160:
			inputSize.width = 640;
			standardSize.width = 644;
			break;
	}
	switch(inputSize.height) {
		case 576:
		case 288:
		case 144:
			inputSize.height = 576;
			standardSize.height = 578;
			break;
		case 480:
		case 240:
		case 120:
			inputSize.height = 480;
			standardSize.height = 486;
			break;
	}
	size_t const bpp = ECVPixelFormatBytesPerPixel([self pixelFormat]);
	struct {
		u_int16_t reg;
		u_int16_t val;
	} settings[] = {
		{0x110, (standardSize.width - inputSize.width) * bpp},
		{0x111, 0},
		{0x112, (standardSize.height - inputSize.height) / 2},
		{0x113, 0},
		{0x114, standardSize.width * bpp},
		{0x115, 5},
		{0x116, standardSize.height / 2},
		{0x117, [[self videoFormat] is50Hz]},
	};
	NSUInteger i = 0;
	for(; i < numberof(settings); i++) if(![self writeIndex:settings[i].reg value:settings[i].val]) return NO;
	return YES;
}
- (BOOL)_setStreaming:(BOOL)flag
{
	u_int8_t value;
	if(![self readIndex:STK0408StatusRegistryIndex value:&value]) return NO;
	if(flag) value |= STK0408StatusStreaming;
	else value &= ~STK0408StatusStreaming;
	return [self writeIndex:STK0408StatusRegistryIndex value:value];
}
- (BOOL)_SAA711XExpect:(u_int8_t)val
{
	NSUInteger retry = 4;
	u_int8_t result = 0;
	while(retry--) {
		if(![self readIndex:0x201 value:&result]) return NO;
		if(val == result) return YES;
		usleep(100);
	}
	ECVLog(ECVError, @"Invalid SAA711X result %x (expected %x)", (unsigned)result, (unsigned)val);
	return NO;
}

#pragma mark -ECVCaptureDevice

- (id)initWithService:(io_service_t)service
{
	if((self = [super initWithService:service])) {
		[self setVideoSource:[ECVSTK11X0VideoSource_SVideo new]]; // TODO: Serialization.
		[self setVideoFormat:[ECVVideoFormat_NTSC_M new]];
		_SAA711XChip = [[SAA711XChip alloc] init];
		[_SAA711XChip setDevice:self];
		_VT1612AChip = [[VT1612AChip alloc] init];
		[_VT1612AChip setDevice:self];
	}
	return self;
}

#pragma mark -ECVCaptureController(ECVAbstract)

- (UInt32)maximumMicrosecondsInFrame
{
	return kUSBHighSpeedMicrosecondsInFrame;
}
- (NSArray *)supportedVideoSources
{
	return [NSArray arrayWithObjects:
		[ECVSTK11X0VideoSource_SVideo new],
		[ECVSTK11X0VideoSource_Composite1 new],
		[ECVSTK11X0VideoSource_Composite2 new],
		[ECVSTK11X0VideoSource_Composite3 new],
		[ECVSTK11X0VideoSource_Composite4 new],
		nil];
}
- (NSSet *)supportedVideoFormats
{
	return [_SAA711XChip supportedVideoFormats];
}
- (OSType)pixelFormat
{
	return k2vuyPixelFormat;
}

#pragma mark -

- (void)read
{
	_offset = 0;
	dev_stk0408_initialize_device(self);
	if(![_SAA711XChip initialize]) return;
	ECVLog(ECVNotice, @"Device video version: %lx", (unsigned long)[_SAA711XChip versionNumber]);
	if(![self _initializeAudio]) return;
	if(![[self videoSource] writeToDevice:self]) return;
	if(![self _initializeResolution]) return;
	if(![self setAlternateInterface:5]) return;
	if(![self _setStreaming:YES]) return;
	[super read];
	(void)[self _setStreaming:NO];
	(void)[self setAlternateInterface:0];
}
- (BOOL)keepReading
{
	if(![super keepReading]) return NO;
	u_int8_t value;
	if(![self readIndex:0x01 value:&value]) return NO;
	if(0x03 != value) {
		ECVLog(ECVError, @"Device watchdog was 0x%02x (should be 0x03).", value);
		return NO;
	}
	return YES;
}
- (void)writeBytes:(UInt8 const *const)bytes length:(NSUInteger const)length toStorage:(ECVVideoStorage *const)storage
{
	if(!length) return;
	size_t skip = 4;
	if(ECVSTK1160NewImageFlag & bytes[0]) {
		ECVFieldType const field = ECVSTK1160HighFieldFlag & bytes[0] ? ECVHighField : ECVLowField;
		[self finishedFrame:[storage finishedFrameWithNextFieldType:field]];
		_offset = 0;
		skip = 8;
	}
	if(length <= skip) return;
	NSUInteger const realLength = length - skip;
	ECVIntegerSize const pixelSize = [[self videoFormat] frameSize];
	ECVIntegerSize const inputSize = (ECVIntegerSize){pixelSize.width, pixelSize.height * 2};
	OSType const pixelFormat = [self pixelFormat];
	NSUInteger const bytesPerRow = ECVPixelFormatBytesPerPixel(pixelFormat) * pixelSize.width;
	ECVPointerPixelBuffer *const buffer = [[ECVPointerPixelBuffer alloc] initWithPixelSize:pixelSize bytesPerRow:bytesPerRow pixelFormat:pixelFormat bytes:bytes + skip validRange:NSMakeRange(_offset, realLength)];
	[storage drawPixelBuffer:buffer atPoint:(ECVIntegerPoint){-8, 0}];
	[buffer release];
	_offset += realLength;
}

#pragma mark -NSObject

- (void)dealloc
{
	[_SAA711XChip setDevice:nil];
	[_VT1612AChip setDevice:nil];
	[_SAA711XChip release];
	[_VT1612AChip release];
	[super dealloc];
}

#pragma mark -ECVCaptureDevice<ECVCaptureDeviceConfiguring>

- (CGFloat)brightness
{
	return [_SAA711XChip brightness];
}
- (void)setBrightness:(CGFloat)val
{
	[_SAA711XChip setBrightness:val];
}
- (CGFloat)contrast
{
	return [_SAA711XChip contrast];
}
- (void)setContrast:(CGFloat)val
{
	[_SAA711XChip setContrast:val];
}
- (CGFloat)saturation
{
	return [_SAA711XChip saturation];
}
- (void)setSaturation:(CGFloat)val
{
	[_SAA711XChip setSaturation:val];
}
- (CGFloat)hue
{
	return [_SAA711XChip hue];
}
- (void)setHue:(CGFloat)val
{
	[_SAA711XChip setHue:val];
}

#pragma mark -<SAA711XDevice>

- (BOOL)writeSAA711XRegister:(u_int8_t)reg value:(int16_t)val
{
	if(![self writeIndex:0x204 value:reg]) return NO;
	if(![self writeIndex:0x205 value:val]) return NO;
	if(![self writeIndex:0x200 value:0x01]) return NO;
	if(![self _SAA711XExpect:0x04]) {
		ECVLog(ECVError, @"SAA711X failed to write %x to %x", (unsigned)val, (unsigned)reg);
		return NO;
	}
	return YES;
}
- (BOOL)readSAA711XRegister:(u_int8_t)reg value:(out u_int8_t *)outVal
{
	if(![self writeIndex:0x208 value:reg]) return NO;
	if(![self writeIndex:0x200 value:0x20]) return NO;
	if(![self _SAA711XExpect:0x01]) {
		ECVLog(ECVError, @"SAA711X failed to read %x", (unsigned)reg);
		return NO;
	}
	return [self readIndex:0x209 value:outVal];
}

#pragma mark -<VT1612ADevice>

- (BOOL)writeVT1612ARegister:(u_int8_t)reg value:(u_int16_t)val
{
	union {
		u_int16_t v16;
		u_int8_t v8[2];
	} const v = {
		.v16 = CFSwapInt16HostToLittle(val),
	};
	if(![self writeIndex:0x504 value:reg]) return NO;
	if(![self writeIndex:0x502 value:v.v8[0]]) return NO;
	if(![self writeIndex:0x503 value:v.v8[1]]) return NO;
	if(![self writeIndex:0x500 value:0x8c]) return NO;
	return YES;
}
- (BOOL)readVT1612ARegister:(u_int8_t)reg value:(out u_int16_t *)outVal
{
	if(![self writeIndex:0x504 value:reg]) return NO;
	if(![self writeIndex:0x500 value:0x8b]) return NO;
	union {
		u_int8_t v8[2];
		u_int16_t v16;
	} val = {};
	if(![self readIndex:0x502 value:val.v8 + 0]) return NO;
	if(![self readIndex:0x503 value:val.v8 + 1]) return NO;
	if(outVal) *outVal = CFSwapInt16LittleToHost(val.v16);
	return YES;
}

@end

@implementation ECVSTK11X0VideoSource_SVideo
- (NSString *)localizedName { return NSLocalizedString(@"S-Video", nil); }
- (BOOL)SVideo { return YES; }
- (BOOL)writeToDevice:(ECVSTK1160Device *const)device { return YES; }
@end
@implementation ECVSTK11X0VideoSource_CompositeGeneric
- (BOOL)composite { return YES; }
- (BOOL)writeToDevice:(ECVSTK1160Device *const)device
{
	return dev_stk0408_write0(device, 1 << 7 | 0x3 << 3, 1 << 7 | [self hardwareSource] << 3);
}
@end
@implementation ECVSTK11X0VideoSource_Composite1
- (NSString *)localizedName { return NSLocalizedString(@"Composite 1", nil); }
- (u_int8_t)hardwareSource { return 3; }
@end
@implementation ECVSTK11X0VideoSource_Composite2
- (NSString *)localizedName { return NSLocalizedString(@"Composite 2", nil); }
- (u_int8_t)hardwareSource { return 2; }
@end
@implementation ECVSTK11X0VideoSource_Composite3
- (NSString *)localizedName { return NSLocalizedString(@"Composite 3", nil); }
- (u_int8_t)hardwareSource { return 1; }
@end
@implementation ECVSTK11X0VideoSource_Composite4
- (NSString *)localizedName { return NSLocalizedString(@"Composite 4", nil); }
- (u_int8_t)hardwareSource { return 0; }
@end
