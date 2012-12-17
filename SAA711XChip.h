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
@class ECVCaptureDevice;
@class ECVVideoFormat;

@protocol SAA711XDevice;

@interface SAA711XChip : NSObject
{
	@private
	IBOutlet ECVCaptureDevice<SAA711XDevice> *device;
	BOOL _polarityInverted;
	CGFloat _brightness;
	CGFloat _contrast;
	CGFloat _saturation;
	CGFloat _hue;
}

- (ECVCaptureDevice<SAA711XDevice> *)device;
- (void)setDevice:(ECVCaptureDevice<SAA711XDevice> *const)d;
- (NSUserDefaults *)defaults;

- (BOOL)polarityInverted;
- (void)setPolarityInverted:(BOOL const)flag;

- (CGFloat)brightness;
- (void)setBrightness:(CGFloat const)val;
- (CGFloat)contrast;
- (void)setContrast:(CGFloat const)val;
- (CGFloat)saturation;
- (void)setSaturation:(CGFloat const)val;
- (CGFloat)hue;
- (void)setHue:(CGFloat const)val;

- (BOOL)initialize;
- (NSUInteger)versionNumber;
- (NSSet *)supportedVideoFormats;

@end

@protocol SAA711XDevice

- (BOOL)writeSAA711XRegister:(u_int8_t const)reg value:(int16_t const)val;
- (BOOL)readSAA711XRegister:(u_int8_t const)reg value:(out u_int8_t *const)outVal;

@end
