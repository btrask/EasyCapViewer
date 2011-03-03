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
@protocol SAA711XDevice;

@interface SAA711XChip : NSObject
{
	@private
	IBOutlet id<SAA711XDevice> device;
	CGFloat _brightness;
	CGFloat _contrast;
	CGFloat _saturation;
	CGFloat _hue;
}

@property(assign) id<SAA711XDevice> device;
@property(nonatomic, assign) CGFloat brightness;
@property(nonatomic, assign) CGFloat contrast;
@property(nonatomic, assign) CGFloat saturation;
@property(nonatomic, assign) CGFloat hue;

- (BOOL)initialize;
@property(readonly) NSUInteger versionNumber;

@end

enum {
	SAA711XAUTO0AutomaticChrominanceStandardDetection = 1 << 1,
	SAA711XCSTDPAL_BGDHI   = 0 << 4,
	SAA711XCSTDNTSC44350Hz = 1 << 4,
	SAA711XCSTDPALN        = 2 << 4,
	SAA711XCSTDNTSCN       = 3 << 4,
	SAA711XCSTDNTSCJ       = 4 << 4,
	SAA711XCSTDSECAM       = 5 << 4,

	SAA711XCSTDNTSCM       = SAA711XCSTDPAL_BGDHI,
	SAA711XCSTDPAL60Hz     = SAA711XCSTDNTSC44350Hz,
	SAA711XCSTDNTSC44360Hz = SAA711XCSTDPALN,
	SAA711XCSTDPALM        = SAA711XCSTDNTSCN,
};
typedef u_int8_t SAA711XCSTDFormat;
enum {
	SAA711XMODECompositeAI11 = 0,
	SAA711XMODECompositeAI12 = 1,
	SAA711XMODECompositeAI21 = 2,
	SAA711XMODECompositeAI22 = 3,
	SAA711XMODECompositeAI23 = 4,
	SAA711XMODECompositeAI24 = 5,
	SAA711XMODESVideoAI11_GAI2 = 6,
	SAA711XMODESVideoAI12_GAI2 = 7,
	SAA711XMODESVideoAI11_YGain = 8,
	SAA711XMODESVideoAI12_YGain = 9,
};
typedef u_int8_t SAA711XMODESource;

@protocol SAA711XDevice

@required
- (BOOL)writeSAA711XRegister:(u_int8_t)reg value:(int16_t)val;
- (BOOL)readSAA711XRegister:(u_int8_t)reg value:(out u_int8_t *)outVal;
@property(readonly) SAA711XMODESource SAA711XMODESource;
@property(readonly) BOOL SVideo;
@property(readonly) SAA711XCSTDFormat SAA711XCSTDFormat;
@property(readonly) BOOL is60HzFormat;
@property(readonly) BOOL SAA711XRTP0OutputPolarityInverted;

@end
