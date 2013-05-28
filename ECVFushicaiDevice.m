/* Copyright (c) 2013, Ben Trask
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE AUTHORS ''AS IS'' AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. */
#import "ECVFushicaiDevice.h"

// TODO: Copy/pasted from ECVEM2860Device.
static void ECVPixelFormatHack(uint16_t *const bytes, size_t const len) {
	for(size_t i = 0; i < len / sizeof(uint16_t); ++i) bytes[i] = CFSwapInt16(bytes[i]);
}

enum {
	ECVFushicaiHighFieldFlag = 1 << 3,
};

#define CTRL(pipe, type, req, idx, val, ext) \
({ \
	[self controlRequestWithType:type request:req value:val index:idx length:0 data:NULL];\
})

@implementation ECVFushicaiDevice

#pragma mark -ECVFushicaiDevice

- (void)writePacket:(UInt8 const *const)bytes length:(NSUInteger const)length toStorage:(ECVVideoStorage *const)storage
{
	NSUInteger const headerLength = 4;
	NSUInteger const trailerLength = 60;

	if(length < headerLength + trailerLength) return;
	if(0x00 == bytes[0]) return; // Empty packet.
	if(0x88 != bytes[0]) {
		ECVLog(ECVError, @"Unexpected device packet header %x\n", CFSwapInt32(*(unsigned int *)bytes));
		// TODO: Just checking our assumptions.
	}

	NSUInteger const fieldIndex = bytes[1]; // Unused.
	NSUInteger const flags = (bytes[2] >> 4) & 0x0f;
	NSUInteger const packetIndex = (bytes[2] & 0x0f) << 8 | bytes[3];

	if(0x000 == packetIndex) {
		ECVFieldType const field = ECVFushicaiHighFieldFlag & flags ? ECVHighField : ECVLowField;
		[self pushVideoFrame:[storage finishedFrameWithNextFieldType:field]];
		_offset = 0;
	}

	// TODO: This gets copy and pasted over and over... Can we abstract it?
	NSUInteger const realLength = length - headerLength - trailerLength;
	ECVIntegerSize const pixelSize = [[self videoFormat] frameSize];
	ECVIntegerSize const inputSize = (ECVIntegerSize){720, pixelSize.height};
	OSType const pixelFormat = [self pixelFormat];
	NSUInteger const bytesPerRow = ECVPixelFormatBytesPerPixel(pixelFormat) * inputSize.width;
	ECVPixelFormatHack((void *)bytes+headerLength, realLength);
	ECVPointerPixelBuffer *const buffer = [[ECVPointerPixelBuffer alloc] initWithPixelSize:inputSize bytesPerRow:bytesPerRow pixelFormat:pixelFormat bytes:bytes + headerLength validRange:NSMakeRange(_offset, realLength)];
	[storage drawPixelBuffer:buffer atPoint:(ECVIntegerPoint){-8, 0}];
	[buffer release];
	_offset += realLength;
}

#pragma mark -ECVCaptureDevice(ECVRead_Thread)

- (void)read
{
[self setAlternateInterface:0];
//CTRL(0, USBmakebmRequestType(kUSBOut, kUSBStandard, kUSBInterface), kUSBRqSetInterface, 0, 0);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 2, 0x0000, 0x00a0, 2);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 7, 0x003a, 0x00a0, 2);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 7, 0x0000, 0x00a2, 33);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 7, 0x0020, 0x00a2, 33);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 7, 0x0040, 0x00a2, 33);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 7, 0x0060, 0x00a2, 33);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 7, 0x0080, 0x00a2, 33);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 7, 0x00a0, 0x00a2, 33);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 7, 0x00c0, 0x00a2, 33);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 7, 0x00e0, 0x00a2, 33);
// 4, kUSBIn, kUSBInterrupt
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc008, 0x0001, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc1d0, 0x00ff, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc1d9, 0x0002, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc1da, 0x0013, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc1db, 0x0012, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc1e9, 0x0002, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc1ec, 0x006c, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc25b, 0x0030, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc254, 0x0073, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc294, 0x0020, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc255, 0x00cf, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc256, 0x0020, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc1eb, 0x0030, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc105, 0x0060, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc11f, 0x00f2, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc127, 0x0060, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc0ae, 0x0010, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc284, 0x00aa, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc003, 0x0004, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc01a, 0x0068, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc100, 0x00d3, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc10e, 0x0072, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc10f, 0x00a2, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc112, 0x00b0, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc115, 0x0015, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc117, 0x0001, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc118, 0x002c, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc12d, 0x0010, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc12f, 0x0020, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc220, 0x002e, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc225, 0x0008, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc24e, 0x0002, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc24f, 0x0002, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc254, 0x0059, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc25a, 0x0016, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc25b, 0x0035, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc263, 0x0017, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc266, 0x0016, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc267, 0x0036, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc24e, 0x0002, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc24f, 0x0002, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc239, 0x0040, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc240, 0x0000, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc241, 0x0000, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc242, 0x0002, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc243, 0x0080, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc244, 0x0012, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc245, 0x0090, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc246, 0x0000, 0);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc278, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc278, 0x0009, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc278, 0x000d, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc278, 0x002d, 0);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc279, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc279, 0x0002, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc279, 0x000a, 0);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc27a, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc27a, 0x0000, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc27a, 0x0010, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc27a, 0x0012, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc27a, 0x0032, 0);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xf890, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xf890, 0x000c, 0);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xf894, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xf894, 0x0086, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc0ac, 0x00c0, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc0ad, 0x0000, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc0a2, 0x0012, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc0a3, 0x00e0, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc0a4, 0x0028, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc0a5, 0x0082, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc0a7, 0x0080, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc000, 0x0014, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc006, 0x0003, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc090, 0x0099, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc091, 0x0090, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc094, 0x0068, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc095, 0x0070, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc09c, 0x0030, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc09d, 0x00c0, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc09e, 0x00e0, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc019, 0x0006, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc08c, 0x00ba, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc101, 0x00ff, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc10c, 0x00b3, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc1b2, 0x0080, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc1b4, 0x00a0, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc14c, 0x00ff, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc14d, 0x00ca, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc113, 0x0053, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc119, 0x008a, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc13c, 0x0003, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc150, 0x009c, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc151, 0x0071, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc152, 0x00c6, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc153, 0x0084, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc154, 0x00bc, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc155, 0x00a0, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc156, 0x00a0, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc157, 0x009c, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc158, 0x001f, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc159, 0x0006, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc15d, 0x0000, 0);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc27d, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc27d, 0x0002, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc27d, 0x0006, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc27d, 0x0026, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc27d, 0x0026, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc27d, 0x00a6, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc280, 0x0011, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc281, 0x0040, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc282, 0x0011, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc283, 0x0040, 0);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xf891, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xf891, 0x0010, 0);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc0ae, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc284, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc105, 0x0060, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc11f, 0x00f2, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc127, 0x0060, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc0ae, 0x0010, 0);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc0ae, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc284, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc284, 0x0088, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc003, 0x0004, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc01a, 0x0079, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc100, 0x00d3, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc10e, 0x0068, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc10f, 0x009c, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc112, 0x00f0, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc115, 0x0015, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc117, 0x0000, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc118, 0x00fc, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc12d, 0x0004, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc12f, 0x0008, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc220, 0x002e, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc225, 0x0008, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc24e, 0x0002, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc24f, 0x0001, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc254, 0x005f, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc25a, 0x0012, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc25b, 0x0001, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc263, 0x001c, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc266, 0x0011, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc267, 0x0005, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc24e, 0x0002, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc24f, 0x0002, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc16f, 0x00b8, 0);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc0ae, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc244, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc246, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc244, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc245, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc242, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc243, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc240, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc241, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc239, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc244, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc246, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc244, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc245, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 11, 0xc244, 0x0000, 3);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc244, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc245, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc244, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 11, 0xc244, 0x0000, 2);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc242, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc243, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 11, 0xc242, 0x0000, 2);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc240, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc241, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 11, 0xc240, 0x0000, 2);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc239, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc239, 0x0060, 0);
//CTRL(0, USBmakebmRequestType(kUSBOut, kUSBStandard, kUSBInterface), kUSBRqSetInterface, 1, 0);
[self setAlternateInterface:1];
// 4, kUSBIn, kUSBInterrupt
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBStandard, kUSBEndpoint), kUSBRqClearFeature, 0, 0, 0);
// 3, kUSBIn, kUSBBulk
// 3, kUSBIn, kUSBBulk
// 3, kUSBIn, kUSBBulk
// 3, kUSBIn, kUSBBulk
// 3, kUSBIn, kUSBBulk
// 3, kUSBIn, kUSBBulk
// 3, kUSBIn, kUSBBulk
// 3, kUSBIn, kUSBBulk
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc105, 0x0010, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc11f, 0x00ff, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc127, 0x0060, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc0ae, 0x0030, 0);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc284, 0x0088, 0);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc244, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc246, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc244, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc245, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc242, 0x0000, 1);
// 3, kUSBIn, kUSBBulk
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc243, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc240, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc241, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc239, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc244, 0x0000, 1);
// 3, kUSBIn, kUSBBulk
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc246, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc244, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc245, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 11, 0xc244, 0x0000, 3);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc244, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc245, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc244, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 11, 0xc244, 0x0000, 2);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc242, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc243, 0x0000, 1);
// 3, kUSBIn, kUSBBulk
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 11, 0xc242, 0x0000, 2);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc240, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc241, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 11, 0xc240, 0x0000, 2);
CTRL(0, USBmakebmRequestType(kUSBIn, kUSBVendor, kUSBDevice), 11, 0xc239, 0x0000, 1);
CTRL(0, USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBDevice), 12, 0xc239, 0x0060, 0);

[super read];
[self setAlternateInterface:0];
}

#pragma mark -ECVCaptureDevice(ECVReadAbstract_Thread)

- (void)writeBytes:(UInt8 const *const)bytes length:(NSUInteger const)length toStorage:(ECVVideoStorage *const)storage
{
	if(!length) return;
	if(3072 != length) {
		ECVLog(ECVError, @"Unexpected USB packet length %lu\n", (unsigned long)length);
		// TODO: Intentionally brittle, just checking our assumptions.
		return;
	}
	[self writePacket:bytes + 0 length:1024 toStorage:storage];
	[self writePacket:bytes + 1024 length:1024 toStorage:storage];
	[self writePacket:bytes + 2048 length:1024 toStorage:storage];
}

#pragma mark -ECVCaptureDevice(ECVAbstract)

- (UInt32)maximumMicrosecondsInFrame
{
	return kUSBHighSpeedMicrosecondsInFrame;
}
- (NSArray *)supportedVideoSources
{
	return [NSArray arrayWithObjects:
		[ECVGenericVideoSource_SVideo source],
//		[ECVGenericVideoSource_Composite source], // TODO: Not supported yet.
		nil];
}
- (ECVVideoSource *)defaultVideoSource
{
	return [ECVGenericVideoSource_SVideo source]; // TODO: Default to composite.
}
- (NSSet *)supportedVideoFormats
{
	return [NSSet setWithObjects:
		[ECVVideoFormat_NTSC_M format],
//		[ECVVideoFormat_PAL_BGDHI format], // TODO: Not supported yet.
		nil];
}
- (ECVVideoFormat *)defaultVideoFormat
{
	return [ECVVideoFormat_NTSC_M format];
}
- (OSType)pixelFormat
{
	return k2vuyPixelFormat;
}

@end
