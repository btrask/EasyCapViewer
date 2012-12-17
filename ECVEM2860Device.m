/* Copyright (C) 2012  Ben Trask

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>. */
#import "ECVEM2860Device.h"
#import "SAA711XChip.h"
#import "ECVVideoFormat.h"
#import "ECVVideoStorage.h"
#import "ECVPixelBuffer.h"
#import "ECVPixelFormat.h"

static void ECVPixelFormatHack(uint16_t *const bytes, size_t const len) {
	for(size_t i = 0; i < len / sizeof(uint16_t); ++i) bytes[i] = CFSwapInt16(bytes[i]);
}

static NSString *const ECVEM2860VideoSourceKey = @"ECVEM2860VideoSource";
static NSString *const ECVEM2860VideoFormatKey = @"ECVEM2860VideoFormat";

#define RECEIVE(request, idx, ...) \
	do { \
		u_int8_t const expected[] = {__VA_ARGS__}; \
		u_int8_t data[] = {__VA_ARGS__}; \
		size_t const length = sizeof(expected); \
		if(![self readRequest:(request) value:0 index:(idx) length:length data:data]) return; \
		if(memcmp(expected, data, length) != 0) ECVLog(ECVNotice, @"Read %04p: Expected %@, received %@", (idx), [NSData dataWithBytesNoCopy:(void *)expected length:length freeWhenDone:NO], [NSData dataWithBytesNoCopy:(void *)data length:length freeWhenDone:NO]); \
	} while(0)
#define SEND(request, idx, ...) \
	do { \
		u_int8_t data[] = {__VA_ARGS__}; \
		if(![self writeRequest:(request) value:0 index:(idx) length:sizeof(data) data:data]) return; \
	} while(0)

@implementation ECVEM2860Device

#pragma mark -ECVEM2860Device

- (ECVEM2860VideoSource)videoSource
{
	return _videoSource;
}
- (void)setVideoSource:(ECVEM2860VideoSource const)source
{
	if(source == _videoSource) return;
	[self setPaused:YES];
	_videoSource = source;
	[self setPaused:NO];
	[[self defaults] setInteger:source forKey:ECVEM2860VideoSourceKey];
}

#pragma mark -

- (BOOL)modifyIndex:(UInt16 const)idx enable:(UInt8 const)enable disable:(UInt8 const)disable
{
	NSAssert(!(enable & disable), @"Can't enable and disable the same flag(s).");
	UInt8 old = 0;
	if(![self readRequest:kUSBRqGetStatus value:0 index:idx length:sizeof(old) data:&old]) return NO;
	UInt8 new = (old | enable) & ~disable;
	if(![self writeRequest:kUSBRqGetStatus value:0 index:idx length:sizeof(new) data:&new]) return NO;
	return YES;
}

#pragma mark -ECVCaptureDevice

- (id)initWithService:(io_service_t)service
{
	if((self = [super initWithService:service])) {
		NSUserDefaults *const d = [self defaults];
		[d registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
			[NSNumber numberWithUnsignedInteger:ECVEM2860CompositeInput], ECVEM2860VideoSourceKey,
//			[NSNumber numberWithUnsignedInteger:ECVSAA711XNTSCMFormat], ECVEM2860VideoFormatKey,
			nil]];
		[self setVideoSource:[d integerForKey:ECVEM2860VideoSourceKey]];
//		[self setVideoFormat:[d integerForKey:ECVEM2860VideoFormatKey]];
		_SAA711XChip = [[SAA711XChip alloc] init];
		[_SAA711XChip setDevice:self];
	}
	return self;
}

#pragma mark -ECVCaptureDevice(ECVAbstract)

- (UInt32)maximumMicrosecondsInFrame
{
	return kUSBHighSpeedMicrosecondsInFrame;
}
- (NSSet *)supportedVideoFormats
{
	return [_SAA711XChip supportedVideoFormats];
}
- (OSType)pixelFormat
{
	return k2vuyPixelFormat; // Native format is kYVYU422PixelFormat, but we convert because QuickTime can't handle it (surprisingly).
}

#pragma mark -

- (void)read
{
	_offset = 0;

	BOOL const resolution640 = NO;

	//GET_DESCRIPTOR_FROM_DEVICE
	//GET_DESCRIPTOR_FROM_DEVICE
	//GET_DESCRIPTOR_FROM_DEVICE
	//SELECT_CONFIGURATION
	RECEIVE(kUSBRqGetStatus, 0x000a, 0x22);
	RECEIVE(kUSBRqGetStatus, 0x000a, 0x22);
	RECEIVE(kUSBRqGetStatus, 0x0006, 0x40);
	RECEIVE(kUSBRqGetStatus, 0x0009, 0x9a);
	RECEIVE(kUSBRqGetStatus, 0x000c, 0x00);
	//RECEIVE(kUSBRqGetStatus, 0x0008, 0xfa);
	//SEND(kUSBRqGetStatus, 0x0008, 0xfe);
	[self modifyIndex:0x0008 enable:1 << 2 disable:0];
	RECEIVE(kUSBRqGetStatus, 0x0000, 0x10);
	//RECEIVE(kUSBRqGetStatus, 0x0006, 0x40);
	//SEND(kUSBRqGetStatus, 0x0006, 0x40);
	[self modifyIndex:0x0006 enable:0 disable:0];
	//RECEIVE(kUSBRqGetStatus, 0x0008, 0xfe);
	//SEND(kUSBRqGetStatus, 0x0008, 0xfe);
	[self modifyIndex:0x0008 enable:0 disable:0];
	//RECEIVE(kUSBRqGetStatus, 0x0008, 0xfe);
	//SEND(kUSBRqGetStatus, 0x0008, 0xfe);
	[self modifyIndex:0x0008 enable:0 disable:0];
	RECEIVE(kUSBRqGetState, 0x0042, 0xfe);
	RECEIVE(kUSBRqGetStatus, 0x0005, 0x10);
	RECEIVE(kUSBRqGetState, 0x004a, 0xb1);
	RECEIVE(kUSBRqGetStatus, 0x0005, 0x00);
	//RECEIVE(kUSBRqGetStatus, 0x0008, 0xfe);
	//SEND(kUSBRqGetStatus, 0x0008, 0xfe);
	[self modifyIndex:0x0008 enable:0 disable:0];
	RECEIVE(kUSBRqGetState, 0x00c6, 0xfe);
	RECEIVE(kUSBRqGetStatus, 0x0005, 0x10);
	RECEIVE(kUSBRqGetState, 0x00c4, 0x10);
	RECEIVE(kUSBRqGetStatus, 0x0005, 0x10);
	RECEIVE(kUSBRqGetState, 0x00c2, 0x10);
	RECEIVE(kUSBRqGetStatus, 0x0005, 0x10);
	RECEIVE(kUSBRqGetState, 0x00c0, 0x10);
	RECEIVE(kUSBRqGetStatus, 0x0005, 0x10);
	RECEIVE(kUSBRqGetState, 0x00b6, 0x10);
	RECEIVE(kUSBRqGetStatus, 0x0005, 0x10);
	//RECEIVE(kUSBRqGetStatus, 0x0008, 0xfe);
	//SEND(kUSBRqGetStatus, 0x0008, 0xfa);
	[self modifyIndex:0x0008 enable:0 disable:1 << 2];
	//RECEIVE(kUSBRqGetStatus, 0x0008, 0xfa);
	//SEND(kUSBRqGetStatus, 0x0008, 0xf2);
	[self modifyIndex:0x0008 enable:0 disable:1 << 3];
	RECEIVE(kUSBRqGetState, 0x0022, 0xf2);
	RECEIVE(kUSBRqGetStatus, 0x0005, 0x10);
	RECEIVE(kUSBRqGetState, 0x00ba, 0x10);
	RECEIVE(kUSBRqGetStatus, 0x0005, 0x10);
	//RECEIVE(kUSBRqGetStatus, 0x0008, 0xf2);
	//SEND(kUSBRqGetStatus, 0x0008, 0xfa);
	[self modifyIndex:0x0008 enable:1 << 3 disable:0];
	//SELECT_INTERFACE
	//SELECT_INTERFACE
	//SELECT_INTERFACE
	//SELECT_INTERFACE
	//SELECT_INTERFACE
	//SELECT_INTERFACE
	//SELECT_INTERFACE
	//SELECT_INTERFACE
	[self setAlternateInterface:7];
	[self setAlternateInterface:6];
	[self setAlternateInterface:5];
	[self setAlternateInterface:4];
	[self setAlternateInterface:3];
	[self setAlternateInterface:2];
	[self setAlternateInterface:1];
	[self setAlternateInterface:0];
	RECEIVE(kUSBRqGetStatus, 0x0012, 0x27);
	SEND(kUSBRqGetStatus, 0x0012, 0x27);
	SEND(kUSBRqGetStatus, 0x000d, 0x42);
	RECEIVE(kUSBRqGetStatus, 0x000f, 0x07);
	SEND(kUSBRqGetStatus, 0x000f, 0x07);
	//RECEIVE(kUSBRqGetStatus, 0x0008, 0xfa);
	//SEND(kUSBRqGetStatus, 0x0008, 0xfa);
	[self modifyIndex:0x0008 enable:0 disable:0];
	SEND(kUSBRqGetStatus, 0x0020, 0x00);
	SEND(kUSBRqGetStatus, 0x0022, 0x00);
	RECEIVE(kUSBRqGetStatus, 0x0012, 0x27);
	SEND(kUSBRqGetStatus, 0x0012, 0x27);
	RECEIVE(kUSBRqGetStatus, 0x000c, 0x00);
	SEND(kUSBRqGetStatus, 0x000c, 0x00);
	//RECEIVE(kUSBRqGetStatus, 0x0008, 0xfa);
	//SEND(kUSBRqGetStatus, 0x0008, 0xfe);
	[self modifyIndex:0x0008 enable:1 << 2 disable:0];
	//RECEIVE(kUSBRqGetStatus, 0x0008, 0xfe);
	//SEND(kUSBRqGetStatus, 0x0008, 0xfa);
	[self modifyIndex:0x0008 enable:0 disable:1 << 2];
	SEND(kUSBRqGetStatus, 0x0006, 0x40);
	SEND(kUSBRqGetStatus, 0x0015, 0x20);
	SEND(kUSBRqGetStatus, 0x0016, 0x20);
	SEND(kUSBRqGetStatus, 0x0017, 0x20);
	SEND(kUSBRqGetStatus, 0x0018, 0x00);
	SEND(kUSBRqGetStatus, 0x0019, 0x00);
	SEND(kUSBRqGetStatus, 0x001a, 0x00);
	SEND(kUSBRqGetStatus, 0x0023, 0x00);
	SEND(kUSBRqGetStatus, 0x0024, 0x00);
	SEND(kUSBRqGetStatus, 0x0026, 0x00);
	SEND(kUSBRqGetStatus, 0x0013, 0x08);
	//RECEIVE(kUSBRqGetStatus, 0x0012, 0x27);
	//SEND(kUSBRqGetStatus, 0x0012, 0x27);
	[self modifyIndex:0x0012 enable:0 disable:0];
	SEND(kUSBRqGetStatus, 0x000c, 0x10);
	SEND(kUSBRqGetStatus, 0x0027, 0x00);
	SEND(kUSBRqGetStatus, 0x0010, 0x00);
	//RECEIVE(kUSBRqGetStatus, 0x0011, 0x11);
	//SEND(kUSBRqGetStatus, 0x0011, 0x11);
	[self modifyIndex:0x0011 enable:1 << 4 disable:0];
	if(resolution640) {
		SEND(kUSBRqGetStatus, 0x0028, 0x01);
		SEND(kUSBRqGetStatus, 0x0029, 0xaf);
		SEND(kUSBRqGetStatus, 0x002a, 0x01);
		SEND(kUSBRqGetStatus, 0x002b, 0x3b);
		SEND(kUSBRqGetStatus, 0x001c, 0x08);
		SEND(kUSBRqGetStatus, 0x001d, 0x03);
		SEND(kUSBRqGetStatus, 0x001e, 0xb0);
		SEND(kUSBRqGetStatus, 0x001f, 0x3c);
	} else {
		SEND(kUSBRqGetStatus, 0x0028, 0x01);
		SEND(kUSBRqGetStatus, 0x0029, 0xb3);
		SEND(kUSBRqGetStatus, 0x002a, 0x01);
		SEND(kUSBRqGetStatus, 0x002b, 0x3b);
		SEND(kUSBRqGetStatus, 0x001c, 0x00);
		SEND(kUSBRqGetStatus, 0x001d, 0x03);
		SEND(kUSBRqGetStatus, 0x001e, 0xb4);
		SEND(kUSBRqGetStatus, 0x001f, 0x3c);
	}
	//RECEIVE(kUSBRqGetStatus, 0x001b, 0x00);
	//SEND(kUSBRqGetStatus, 0x001b, 0x00);
	[self modifyIndex:0x001b enable:0 disable:0];
	//RECEIVE(kUSBRqGetStatus, 0x001b, 0x00);
	//SEND(kUSBRqGetStatus, 0x001b, 0x00);
	[self modifyIndex:0x001b enable:0 disable:0];
	//SEND(kUSBRqGetState, 0x004a, 0x01, 0x08);
	//RECEIVE(kUSBRqGetStatus, 0x0005, 0x00);
	//SEND(kUSBRqGetState, 0x004a, 0x03, 0x30);
	//RECEIVE(kUSBRqGetStatus, 0x0005, 0x00);
	//SEND(kUSBRqGetState, 0x004a, 0x06, 0xeb, 0x0d, 0x88, 0x01);
	//RECEIVE(kUSBRqGetStatus, 0x0005, 0x00);
	//SEND(kUSBRqGetState, 0x004a, 0x0a, 0x80, 0x47, 0x40, 0x00);
	//RECEIVE(kUSBRqGetStatus, 0x0005, 0x00);
	//SEND(kUSBRqGetState, 0x004a, 0x0f, 0x2a);
	//RECEIVE(kUSBRqGetStatus, 0x0005, 0x00);
	//SEND(kUSBRqGetState, 0x004a, 0x10, 0x08, 0x0c, 0xe7, 0x00);
	//RECEIVE(kUSBRqGetStatus, 0x0005, 0x00);
	//SEND(kUSBRqGetState, 0x004a, 0x0a, 0x80);
	//RECEIVE(kUSBRqGetStatus, 0x0005, 0x00);
	//SEND(kUSBRqGetState, 0x004a, 0x0e, 0x01);
	//RECEIVE(kUSBRqGetStatus, 0x0005, 0x00);
	//SEND(kUSBRqGetState, 0x004a, 0x08, 0x88);
	//RECEIVE(kUSBRqGetStatus, 0x0005, 0x00);
	//SEND(kUSBRqGetState, 0x004a, 0x02, 0xc0);
	//RECEIVE(kUSBRqGetStatus, 0x0005, 0x00);
	SEND(kUSBRqGetStatus, 0x0021, 0x08);
	SEND(kUSBRqGetStatus, 0x0020, 0x10);
	//SEND(kUSBRqGetState, 0x004a, 0x0d, 0x00);
	//RECEIVE(kUSBRqGetStatus, 0x0005, 0x00);
	SEND(kUSBRqGetStatus, 0x0022, 0x10);
	SEND(kUSBRqGetStatus, 0x0014, 0x32);
	SEND(kUSBRqGetStatus, 0x0025, 0x02);
	RECEIVE(kUSBRqGetStatus, 0x0026, 0x00);
	SEND(kUSBRqGetStatus, 0x0026, 0x00);
	SEND(kUSBRqSetFeature, 0x004a, 0x1f);
	RECEIVE(kUSBRqGetStatus, 0x0005, 0x00);
	RECEIVE(kUSBRqGetState, 0x004a, 0xb1);
	RECEIVE(kUSBRqGetStatus, 0x0005, 0x00);
	//RECEIVE(kUSBRqGetStatus, 0x0027, 0x00);
	//SEND(kUSBRqGetStatus, 0x0027, 0x00);
	[self modifyIndex:0x0027 enable:0 disable:0];
	//RECEIVE(kUSBRqGetStatus, 0x0011, 0x11);
	//SEND(kUSBRqGetStatus, 0x0011, 0x10);
	[self modifyIndex:0x0011 enable:0 disable:1 << 0];
	//RECEIVE(kUSBRqGetStatus, 0x001b, 0x00);
	//SEND(kUSBRqGetStatus, 0x001b, 0x80);
	[self modifyIndex:0x001b enable:1 << 7 disable:0];
	//RECEIVE(kUSBRqGetStatus, 0x000c, 0x10);
	//SEND(kUSBRqGetStatus, 0x000c, 0x10);
	[self modifyIndex:0x000c enable:0 disable:0];
	//RECEIVE(kUSBRqGetStatus, 0x0012, 0x27);
	//SEND(kUSBRqGetStatus, 0x0012, 0x67);
	[self modifyIndex:0x0012 enable:1 << 6 disable:0];
	SEND(kUSBRqGetStatus, 0x0022, 0x10);
	SEND(kUSBRqGetStatus, 0x0020, 0x10);
	//RECEIVE(kUSBRqGetStatus, 0x000f, 0x07);
	//SEND(kUSBRqGetStatus, 0x000f, 0x07);
	[self modifyIndex:0x000f enable:0 disable:0];
	//RECEIVE(kUSBRqGetStatus, 0x0008, 0xfa);
	//SEND(kUSBRqGetStatus, 0x0008, 0xfa);
	[self modifyIndex:0x0008 enable:0 disable:0];
	SEND(kUSBRqSetFeature, 0x004a, 0x1f);
	RECEIVE(kUSBRqGetStatus, 0x0005, 0x00);
	RECEIVE(kUSBRqGetState, 0x004a, 0xb1);
	RECEIVE(kUSBRqGetStatus, 0x0005, 0x00);
	SEND(kUSBRqGetStatus, 0x0021, 0x08);
	SEND(kUSBRqGetStatus, 0x0020, 0x10);
	//SEND(kUSBRqGetState, 0x004a, 0x0d, 0x00);
	//RECEIVE(kUSBRqGetStatus, 0x0005, 0x00);
	SEND(kUSBRqGetStatus, 0x0022, 0x10);
	SEND(kUSBRqGetStatus, 0x0014, 0x32);
	SEND(kUSBRqGetStatus, 0x0025, 0x02);
	//RECEIVE(kUSBRqGetStatus, 0x000e, 0x90);
	//SEND(kUSBRqGetStatus, 0x000e, 0x90);
	[self modifyIndex:0x000e enable:0 disable:0];
	//RECEIVE(kUSBRqGetStatus, 0x000f, 0x07);
	//SEND(kUSBRqGetStatus, 0x000f, 0x87);
	[self modifyIndex:0x000f enable:0 disable:1 << 7];
	//RECEIVE(kUSBRqGetStatus, 0x0008, 0xfa);
	//SEND(kUSBRqGetStatus, 0x0008, 0xf8);
	[self modifyIndex:0x0008 enable:0 disable:1 << 1];
	//SEND(kUSBRqGetState, 0x004a, 0x0a, 0x80);
	//RECEIVE(kUSBRqGetStatus, 0x0005, 0x00);
	//SEND(kUSBRqGetState, 0x004a, 0x0e, 0x01);
	//RECEIVE(kUSBRqGetStatus, 0x0005, 0x00);
	//SEND(kUSBRqGetState, 0x004a, 0x08, 0x88);
	//RECEIVE(kUSBRqGetStatus, 0x0005, 0x00);
	SEND(kUSBRqGetStatus, 0x0021, 0x08);
	SEND(kUSBRqGetStatus, 0x0020, 0x10);
	//SEND(kUSBRqGetState, 0x004a, 0x0d, 0x00);
	//RECEIVE(kUSBRqGetStatus, 0x0005, 0x00);
	SEND(kUSBRqGetStatus, 0x0022, 0x10);
	SEND(kUSBRqGetStatus, 0x0014, 0x32);
	SEND(kUSBRqGetStatus, 0x0025, 0x02);
	//SELECT_INTERFACE
	if(resolution640) {
		[self setAlternateInterface:5];
	} else {
		[self setAlternateInterface:6];
	}
	//RECEIVE(kUSBRqGetStatus, 0x000f, 0x87);
	//SEND(kUSBRqGetStatus, 0x000f, 0x07);
	[self modifyIndex:0x000f enable:0 disable:1 << 7];
	//RECEIVE(kUSBRqGetStatus, 0x0008, 0xf8);
	//SEND(kUSBRqGetStatus, 0x0008, 0xfa);
	[self modifyIndex:0x0008 enable:1 << 1 disable:0];
	SEND(kUSBRqGetStatus, 0x0020, 0x00);
	SEND(kUSBRqGetStatus, 0x0022, 0x00);
	//RECEIVE(kUSBRqGetStatus, 0x0012, 0x67);
	//SEND(kUSBRqGetStatus, 0x0012, 0x27);
	[self modifyIndex:0x0012 enable:0 disable:1 << 6];
	//RECEIVE(kUSBRqGetStatus, 0x000c, 0x10);
	//SEND(kUSBRqGetStatus, 0x000c, 0x00);
	[self modifyIndex:0x000c enable:0 disable:1 << 4];
	//RECEIVE(kUSBRqGetStatus, 0x0008, 0xfa);
	//SEND(kUSBRqGetStatus, 0x0008, 0xfe);
	[self modifyIndex:0x0008 enable:1 << 2 disable:0];
	//RECEIVE(kUSBRqGetStatus, 0x0008, 0xfe);
	//SEND(kUSBRqGetStatus, 0x0008, 0xfa);
	[self modifyIndex:0x0008 enable:0 disable:1 << 2];
	SEND(kUSBRqGetStatus, 0x0006, 0x40);
	SEND(kUSBRqGetStatus, 0x0015, 0x20);
	SEND(kUSBRqGetStatus, 0x0016, 0x20);
	SEND(kUSBRqGetStatus, 0x0017, 0x20);
	SEND(kUSBRqGetStatus, 0x0018, 0x00);
	SEND(kUSBRqGetStatus, 0x0019, 0x00);
	SEND(kUSBRqGetStatus, 0x001a, 0x00);
	SEND(kUSBRqGetStatus, 0x0023, 0x00);
	SEND(kUSBRqGetStatus, 0x0024, 0x00);
	SEND(kUSBRqGetStatus, 0x0026, 0x00);
	SEND(kUSBRqGetStatus, 0x0013, 0x08);
	//RECEIVE(kUSBRqGetStatus, 0x0012, 0x27);
	//SEND(kUSBRqGetStatus, 0x0012, 0x27);
	[self modifyIndex:0x0012 enable:0 disable:0];
	SEND(kUSBRqGetStatus, 0x000c, 0x10);
	SEND(kUSBRqGetStatus, 0x0027, 0x34);
	SEND(kUSBRqGetStatus, 0x0010, 0x00);
	//RECEIVE(kUSBRqGetStatus, 0x0011, 0x10);
	//SEND(kUSBRqGetStatus, 0x0011, 0x11);
	[self modifyIndex:0x0011 enable:1 << 0 disable:0];
	SEND(kUSBRqGetStatus, 0x0028, 0x01);
	SEND(kUSBRqGetStatus, 0x0029, 0xb3);
	SEND(kUSBRqGetStatus, 0x002a, 0x01);
	SEND(kUSBRqGetStatus, 0x002b, 0x3b);
	SEND(kUSBRqGetStatus, 0x001c, 0x00);
	SEND(kUSBRqGetStatus, 0x001d, 0x03);
	SEND(kUSBRqGetStatus, 0x001e, 0xb4);
	SEND(kUSBRqGetStatus, 0x001f, 0x3c);
	//RECEIVE(kUSBRqGetStatus, 0x001b, 0x80);
	//SEND(kUSBRqGetStatus, 0x001b, 0x80);
	[self modifyIndex:0x001b enable:0 disable:0];
	//RECEIVE(kUSBRqGetStatus, 0x001b, 0x80);
	//SEND(kUSBRqGetStatus, 0x001b, 0x80);
	[self modifyIndex:0x001b enable:0 disable:0];
	if(resolution640) {
		//RECEIVE(kUSBRqGetStatus, 0x0026, 0x00);
		//SEND(kUSBRqGetStatus, 0x0026, 0x10);
		[self modifyIndex:0x0026 enable:1 << 4 disable:0];
		SEND(kUSBRqGetStatus, 0x0030, 0x99, 0x01);
	}
	//SEND(kUSBRqGetState, 0x004a, 0x01, 0x08);
	//RECEIVE(kUSBRqGetStatus, 0x0005, 0x00);
	//SEND(kUSBRqGetState, 0x004a, 0x03, 0x30);
	//RECEIVE(kUSBRqGetStatus, 0x0005, 0x00);
	//SEND(kUSBRqGetState, 0x004a, 0x06, 0xeb, 0x0d, 0x88, 0x01);
	//RECEIVE(kUSBRqGetStatus, 0x0005, 0x00);
	//SEND(kUSBRqGetState, 0x004a, 0x0a, 0x80, 0x47, 0x40, 0x00);
	//RECEIVE(kUSBRqGetStatus, 0x0005, 0x00);
	//SEND(kUSBRqGetState, 0x004a, 0x0f, 0x2a);
	//RECEIVE(kUSBRqGetStatus, 0x0005, 0x00);
	//SEND(kUSBRqGetState, 0x004a, 0x10, 0x08, 0x0c, 0xe7, 0x00);
	//RECEIVE(kUSBRqGetStatus, 0x0005, 0x00);
	//SEND(kUSBRqGetState, 0x004a, 0x0a, 0x80);
	//RECEIVE(kUSBRqGetStatus, 0x0005, 0x00);
	//SEND(kUSBRqGetState, 0x004a, 0x0e, 0x01);
	//RECEIVE(kUSBRqGetStatus, 0x0005, 0x00);
	//SEND(kUSBRqGetState, 0x004a, 0x08, 0x88);
	//RECEIVE(kUSBRqGetStatus, 0x0005, 0x00);
	//SEND(kUSBRqGetState, 0x004a, 0x02, 0xc0);
	//RECEIVE(kUSBRqGetStatus, 0x0005, 0x00);
	SEND(kUSBRqGetStatus, 0x0021, 0x08);
	SEND(kUSBRqGetStatus, 0x0020, 0x10);
	//SEND(kUSBRqGetState, 0x004a, 0x0d, 0x00);
	//RECEIVE(kUSBRqGetStatus, 0x0005, 0x00);
	SEND(kUSBRqGetStatus, 0x0022, 0x10);
	SEND(kUSBRqGetStatus, 0x0014, 0x32);
	SEND(kUSBRqGetStatus, 0x0025, 0x02);
	if(resolution640) {
		//RECEIVE(kUSBRqGetStatus, 0x0026, 0x10);
		//SEND(kUSBRqGetStatus, 0x0026, 0x10);
		[self modifyIndex:0x0026 enable:0 disable:0];
	} else {
		//RECEIVE(kUSBRqGetStatus, 0x0026, 0x00);
		//SEND(kUSBRqGetStatus, 0x0026, 0x00);
		[self modifyIndex:0x0026 enable:0 disable:0];
	}
	SEND(kUSBRqSetFeature, 0x004a, 0x1f);
	RECEIVE(kUSBRqGetStatus, 0x0005, 0x00);
	RECEIVE(kUSBRqGetState, 0x004a, 0xb1);
	RECEIVE(kUSBRqGetStatus, 0x0005, 0x00);
	//RECEIVE(kUSBRqGetStatus, 0x0027, 0x34);
	//SEND(kUSBRqGetStatus, 0x0027, 0x34);
	[self modifyIndex:0x0027 enable:0 disable:0];
	//RECEIVE(kUSBRqGetStatus, 0x0011, 0x11);
	//SEND(kUSBRqGetStatus, 0x0011, 0x11);
	[self modifyIndex:0x0011 enable:0 disable:0];
	//RECEIVE(kUSBRqGetStatus, 0x001b, 0x80);
	//SEND(kUSBRqGetStatus, 0x001b, 0x00);
	[self modifyIndex:0x001b enable:0 disable:1 << 7];
	//RECEIVE(kUSBRqGetStatus, 0x000c, 0x10);
	//SEND(kUSBRqGetStatus, 0x000c, 0x10);
	[self modifyIndex:0x000c enable:0 disable:0];
	//RECEIVE(kUSBRqGetStatus, 0x0012, 0x27);
	//SEND(kUSBRqGetStatus, 0x0012, 0x67);
	[self modifyIndex:0x0012 enable:1 << 6 disable:0];
	SEND(kUSBRqGetStatus, 0x0022, 0x10);
	SEND(kUSBRqGetStatus, 0x0020, 0x10);
	if(resolution640) {
		//RECEIVE(kUSBRqGetStatus, 0x000e, 0x95);
		//SEND(kUSBRqGetStatus, 0x000e, 0x95);
		[self modifyIndex:0x000e enable:0 disable:0];
	} else {
		//RECEIVE(kUSBRqGetStatus, 0x000e, 0x96);
		//SEND(kUSBRqGetStatus, 0x000e, 0x96);
		[self modifyIndex:0x000e enable:0 disable:0];
	}
	//RECEIVE(kUSBRqGetStatus, 0x000f, 0x07);
	//SEND(kUSBRqGetStatus, 0x000f, 0x87);
	[self modifyIndex:0x000f enable:1 << 7 disable:0];
	//RECEIVE(kUSBRqGetStatus, 0x0008, 0xfa);
	//SEND(kUSBRqGetStatus, 0x0008, 0xf8);
	[self modifyIndex:0x0008 enable:0 disable:1 << 1];
	SEND(kUSBRqSetFeature, 0x004a, 0x1f);
	RECEIVE(kUSBRqGetStatus, 0x0005, 0x00);
	RECEIVE(kUSBRqGetState, 0x004a, 0xb1);
	RECEIVE(kUSBRqGetStatus, 0x0005, 0x00);
	//RECEIVE(kUSBRqGetStatus, 0x000c, 0x10);
	//SEND(kUSBRqGetStatus, 0x000c, 0x10);
	[self modifyIndex:0x000c enable:0 disable:0];
	//RESET_PIPE
	//GET_CURRENT_FRAME_NUMBER

	if(![_SAA711XChip initialize]) return;
	[super read];
	(void)[self setAlternateInterface:0];
}
- (void)writeBytes:(UInt8 const *const)bytes length:(NSUInteger const)length toStorage:(ECVVideoStorage *const)storage
{
	if(!length) return;
	if(0x22 == bytes[0]) {
		ECVFieldType field = ECVHighField;
		if(length >= 3) field = bytes[2] & 0x01 ? ECVLowField : ECVHighField;
		[self finishedFrame:[storage finishedFrameWithNextFieldType:field]];
		_offset = 0;
	}
	size_t const skip = 4;
	if(length <= skip) return;
	NSUInteger const realLength = length - skip;
	ECVIntegerSize const inputSize = {720, [[self videoFormat] is60Hz] ? 480 : 576};
	ECVIntegerSize const pixelSize = (ECVIntegerSize){inputSize.width, inputSize.height / 2};
	OSType const pixelFormat = [self pixelFormat];
	NSUInteger const bytesPerRow = ECVPixelFormatBytesPerPixel(pixelFormat) * pixelSize.width;
	ECVPixelFormatHack((void *)bytes + skip, realLength);
	ECVPointerPixelBuffer *const buffer = [[ECVPointerPixelBuffer alloc] initWithPixelSize:pixelSize bytesPerRow:bytesPerRow pixelFormat:pixelFormat bytes:bytes + skip validRange:NSMakeRange(_offset, realLength)];
	[storage drawPixelBuffer:buffer atPoint:(ECVIntegerPoint){-8, 0}];
	[buffer release];
	_offset += realLength;
}

#pragma mark -ECVCaptureDevice<ECVCaptureDeviceConfiguring>

- (NSArray *)allVideoSourceObjects
{
	return [NSArray arrayWithObjects:
		[NSNumber numberWithUnsignedInteger:ECVEM2860SVideoInput],
		[NSNumber numberWithUnsignedInteger:ECVEM2860CompositeInput],
		nil];
}
- (id)videoSourceObject
{
	return [NSNumber numberWithUnsignedInteger:[self videoSource]];
}
- (void)setVideoSourceObject:(id)obj
{
	[self setVideoSource:[obj unsignedIntegerValue]];
}
- (NSString *)localizedStringForVideoSourceObject:(id)obj
{
	switch([obj unsignedIntegerValue]) {
		case ECVEM2860SVideoInput: return NSLocalizedString(@"S-Video", nil);
		case ECVEM2860CompositeInput: return NSLocalizedString(@"Composite", nil);
	}
	return nil;
}
- (BOOL)isValidVideoSourceObject:(id)obj
{
	return YES;
}
- (NSInteger)indentationLevelForVideoSourceObject:(id)obj
{
	return 0;
}

#pragma mark -

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

#pragma mark -<ECVComponentConfiguring>

- (long)inputCapabilityFlags
{
	return digiInDoesNTSC | digiInDoesPAL | digiInDoesSECAM | digiInDoesColor | digiInDoesComposite | digiInDoesSVideo;
}
- (short)inputFormatForVideoSourceObject:(id)obj
{
	switch([obj unsignedIntegerValue]) {
		case ECVEM2860SVideoInput:
			return sVideoIn;
		case ECVEM2860CompositeInput:
			return compositeIn;
		default:
			ECVAssertNotReached(@"Invalid video source %lu.", (unsigned long)[obj unsignedIntegerValue]);
			return 0;
	}
}
- (short)inputStandard
{
	return currentIn; // TODO: Implement.
//	switch([self videoFormat]) {
//		case ECVSAA711XNTSCMFormat: return ntscReallyIn;
//		case ECVSAA711XPALBGDHIFormat: return palIn;
//		case ECVSAA711XSECAMFormat: return secamIn;
//		default: return currentIn;
//	}
}
- (void)setInputStandard:(short)standard
{
	// TODO: Implement.
//	ECVSAA711XVideoFormat format;
//	switch(standard) {
//		case ntscReallyIn: format = ECVSAA711XNTSCMFormat; break;
//		case palIn: format = ECVSAA711XPALBGDHIFormat; break;
//		case secamIn: format = ECVSAA711XSECAMFormat; break;
//		default: return;
//	}
//	[self setVideoFormat:format];
}

#pragma mark -<SAA711XDevice>

- (BOOL)writeSAA711XRegister:(u_int8_t)reg value:(int16_t)val
{
	UInt8 data[] = {reg, val};
	UInt8 error = 0;
	if(![self writeRequest:kUSBRqGetState value:0 index:0x004a length:sizeof(data) data:data]) return NO;
	if(![self readRequest:kUSBRqGetStatus value:0 index:0x0005 length:sizeof(error) data:&error]) return NO;
	return !error;
}
- (BOOL)readSAA711XRegister:(u_int8_t)reg value:(out u_int8_t *)outVal
{
	return NO; // TODO: Not sure how this works right now, and it's only used for reading the version number anyway.
}

#pragma mark -

- (BOOL)sVideoForSAA711XChip:(SAA711XChip *const)chip
{
	return ECVEM2860SVideoInput == [self videoSource];
}

#pragma mark -NSObject

- (void)dealloc
{
	[_SAA711XChip setDevice:nil];
	[_SAA711XChip release];
	[super dealloc];
}

@end
