/* Copyright (c) 2009, Ben Trask
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
#import "SAA711XChip.h"

enum {
	SAA711XFUSE0Antialias = 1 << 6,
	SAA711XFUSE1Amplifier = 1 << 7,
};
enum {
	SAA711XGAI18StaticGainControl1 = 1 << 0,
	SAA711XGAI28StaticGainControl2 = 1 << 1,
	SAA711XGAFIXGainControlUserProgrammable = 1 << 2,
	SAA711XHOLDGAutomaticGainControlEnabled = 0 << 3,
	SAA711XHOLDGAutomaticGainControlDisabled = 1 << 3,
	SAA711XCPOFFColorPeakControlDisabled = 1 << 4,
	SAA711XVBSLLongVerticalBlanking = 1 << 5,
	SAA711XHLNRSReferenceSelect = 1 << 6,
};
enum {
	SAA711XYCOMBAdaptiveLuminanceComb = 1 << 6,
	SAA711XBYPSChrominanceTrapCombBypass = 1 << 7,
};
enum {
	SAA711XVNOIVerticalNoiseReductionNormal = 0 << 0,
	SAA711XVNOIVerticalNoiseReductionFast = 1 << 0,
	SAA711XVNOIVerticalNoiseReductionFree = 2 << 0,
	SAA711XVNOIVerticalNoiseReductionBypass = 3 << 0,
	SAA711XHTCHorizontalTimeConstantTVMode = 0 << 3,
	SAA711XHTCHorizontalTimeConstantVTRMode = 1 << 3,
	SAA711XHTCHorizontalTimeConstantAutomatic = 2 << 3,
	SAA711XHTCHorizontalTimeConstantFastLocking = 3 << 3,
	SAA711XFOETForcedOddEventToggle = 1 << 5,
	SAA711XFSELManualFieldSelection50Hz = 0 << 6,
	SAA711XFSELManualFieldSelection60Hz = 1 << 6,
	SAA711XAUFDAutomaticFieldDetection = 1 << 7,
};
enum {
	SAA711XCGAINChromaGainValueMinimum = 0x00,
	SAA711XCGAINChromaGainValueNominal = 0x2a,
	SAA711XCGAINChromaGainValueMaximum = 0x7f,
	SAA711XACGCAutomaticChromaGainControlEnabled = 0 << 7,
	SAA711XACGCAutomaticChromaGainControlDisabled = 1 << 7,
};
enum {
	SAA711XRTP0OutputPolarityInverted = 1 << 3,
};
enum {
	SAA711XSLM1ScalerDisabled = 1 << 1,
	SAA711XSLM3AudioClockGenerationDisabled = 1 << 3,
	SAA711XCH1ENAD1X = 1 << 6,
	SAA711XCH2ENAD2X = 1 << 7,
};
enum {
	SAA711XCCOMBAdaptiveChrominanceComb = 1 << 0,
	SAA711XFCTCFastColorTimeConstant = 1 << 2,
};

@interface SAA711XChip(Private)

- (u_int8_t)SAA711XCHXENOutputControl;

@end

@implementation SAA711XChip

#pragma mark -SAA711XChip

@synthesize device;
- (CGFloat)brightness
{
	return _brightness;
}
- (void)setBrightness:(CGFloat)val
{
	_brightness = val;
	(void)[device writeSAA711XRegister:0x0a value:round(val * 0xff)];
}
- (CGFloat)contrast
{
	return _contrast;
}
- (void)setContrast:(CGFloat)val
{
	_contrast = val;
	(void)[device writeSAA711XRegister:0x0b value:round(val * 0x88)];
}
- (CGFloat)saturation
{
	return _saturation;
}
- (void)setSaturation:(CGFloat)val
{
	_saturation = val;
	(void)[device writeSAA711XRegister:0x0c value:round(val * 0x80)];
}
- (CGFloat)hue
{
	return _hue;
}
- (void)setHue:(CGFloat)val
{
	_hue = val;
	(void)[device writeSAA711XRegister:0x0d value:round((val - 0.5f) * 0xff)];
}

#pragma mark -

- (BOOL)initialize
{
	// Based on Table 184 in the datasheet.
	struct {
		u_int8_t reg;
		int16_t val;
	} const settings[] = {
		{0x01, 0x08},
		{0x02, SAA711XFUSE0Antialias | SAA711XFUSE1Amplifier | [device SAA711XMODESource]},
		{0x03, SAA711XHOLDGAutomaticGainControlEnabled | SAA711XVBSLLongVerticalBlanking},
		{0x04, 0x90},
		{0x05, 0x90},
		{0x06, 0xeb},
		{0x07, 0xe0},
		{0x08, SAA711XVNOIVerticalNoiseReductionFast | SAA711XHTCHorizontalTimeConstantFastLocking | SAA711XFOETForcedOddEventToggle | ([device is60HzFormat] ? SAA711XFSELManualFieldSelection60Hz : SAA711XFSELManualFieldSelection50Hz)},
		{0x09, [device SVideo] ? SAA711XBYPSChrominanceTrapCombBypass : SAA711XYCOMBAdaptiveLuminanceComb},
		{0x0e, SAA711XCCOMBAdaptiveChrominanceComb | SAA711XFCTCFastColorTimeConstant | [device SAA711XCSTDFormat]},
		{0x0f, SAA711XCGAINChromaGainValueNominal | SAA711XACGCAutomaticChromaGainControlEnabled},
		{0x10, 0x06},
		{0x11, [device SAA711XRTP0OutputPolarityInverted] ? SAA711XRTP0OutputPolarityInverted : kNilOptions},
		{0x12, 0x00},
		{0x13, 0x00},
		{0x14, 0x01},
		{0x15, 0x11},
		{0x16, 0xfe},
		{0x17, 0xd8},
		{0x18, 0x40},
		{0x19, 0x80},
		{0x1a, 0x77},
		{0x1b, 0x42},
		{0x1c, 0xa9},
		{0x1d, 0x01},
		{0x83, 0x31},
		{0x88, SAA711XSLM1ScalerDisabled | SAA711XSLM3AudioClockGenerationDisabled | [self SAA711XCHXENOutputControl]},
	};
	NSUInteger i;
	for(i = 0; i < numberof(settings); i++) if(![device writeSAA711XRegister:settings[i].reg value:settings[i].val]) return NO;
	for(i = 0x41; i <= 0x57; i++) if(![device writeSAA711XRegister:i value:0xff]) return NO;
	[self setBrightness:_brightness];
	[self setContrast:_contrast];
	[self setSaturation:_saturation];
	[self setHue:_hue];
	return YES;
}

#pragma mark -SAA711XChip(Private)

- (u_int8_t)SAA711XCHXENOutputControl
{
	switch([[self device] SAA711XMODESource]) {
		case SAA711XMODECompositeAI11:
		case SAA711XMODECompositeAI12:
			return SAA711XCH1ENAD1X;
		case SAA711XMODECompositeAI21:
		case SAA711XMODECompositeAI22:
		case SAA711XMODECompositeAI23:
		case SAA711XMODECompositeAI24:
			return SAA711XCH2ENAD2X;
		case SAA711XMODESVideoAI11_GAI2:
		case SAA711XMODESVideoAI12_GAI2:
		case SAA711XMODESVideoAI11_YGain:
		case SAA711XMODESVideoAI12_YGain:
			return SAA711XCH1ENAD1X | SAA711XCH2ENAD2X;
		default:
			return 0;
	}
}

@end
