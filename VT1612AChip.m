/* Copyright (c) 2010, Ben Trask
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
#import "VT1612AChip.h"

enum {
	VT1612ARegisterVolumeStereoOut = 0x02,
	VT1612ARegisterVolumeLineIn = 0x10,
	VT1612ARegisterRecordSelect = 0x1a,
	VT1612ARegisterRecordGain = 0x1c,
	VT1612ARegisterVendorID1 = 0x7c,
	VT1612ARegisterVendorID2 = 0x7e,
};
enum {
	VT1612AMute = 1 << 15,
};
enum {
	VT1612ARecordSourceMic = 0,
	VT1612ARecordSourceCD = 1,
	VT1612ARecordSourceVideoIn = 2,
	VT1612ARecordSourceAuxIn = 3,
	VT1612ARecordSourceLineIn = 4,
	VT1612ARecordSourceStereoMix = 5,
	VT1612ARecordSourceMonoMix = 6,
	VT1612ARecordSourcePhone = 7,
};

static u_int16_t VT1612ATwoChannels(u_int8_t left, u_int8_t right)
{
	union {
		u_int8_t v8[2];
		u_int16_t v16;
	} const result = {
		.v8 = {left, right},
	};
	return CFSwapInt16BigToHost(result.v16);
}
static u_int16_t VT1612ABothChannels(u_int8_t v)
{
	return VT1612ATwoChannels(v, v);
}
static u_int8_t VT1612AInputGain(CGFloat v)
{
	return CLAMP(0x0, round((1.0f - v) * 0x1f), 0x1f);
}
static u_int8_t VT1612ARecordGain(CGFloat v)
{
	return CLAMP(0x0, round(v * 0x0f), 0x15);
}

@implementation VT1612AChip

#pragma mark -VT1612AChip

@synthesize device;

#pragma mark -

- (BOOL)initialize
{
	struct {
		u_int8_t reg;
		u_int16_t val;
	} settings[] = {
		{VT1612ARegisterRecordSelect, VT1612ABothChannels(VT1612ARecordSourceLineIn)},
		{VT1612ARegisterVolumeLineIn, VT1612ABothChannels(VT1612AInputGain(1.0f))},
		{VT1612ARegisterRecordGain, VT1612ABothChannels(VT1612ARecordGain(0.3f))},
	};
	NSUInteger i = 0;
	for(; i < numberof(settings); i++) [device writeVT1612ARegister:settings[i].reg value:settings[i].val];
	return YES;
}
- (NSString *)vendorAndRevisionString
{
	union {
		u_int8_t v8[4];
		u_int16_t v16[2];
		u_int32_t v32;
	} val = {};
	if(![device readVT1612ARegister:VT1612ARegisterVendorID1 value:val.v16 + 0]) return nil;
	if(![device readVT1612ARegister:VT1612ARegisterVendorID2 value:val.v16 + 1]) return nil;
	val.v16[0] = CFSwapInt16HostToBig(val.v16[0]);
	val.v16[1] = CFSwapInt16HostToBig(val.v16[1]);
	if(!val.v32) return @"(Unsupported)";
	return [NSString stringWithFormat:@"%c%c%c-%x", val.v8[0], val.v8[1], val.v8[2], val.v8[3]];
}

@end
