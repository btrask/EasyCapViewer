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
#import "SAA711XChip.h"

// Models
#import "ECVCaptureDevice.h"
#import "ECVVideoSource.h"
#import "ECVVideoFormat.h"

// Other Sources
#import "ECVDebug.h"

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

@interface ECVVideoFormat(SAA711XChip)

- (u_int8_t)SAA711XFSELManualFieldSelection;
- (u_int8_t)SAA711XCSTDFormat;

@end

@interface SAA711XChip(Private)

- (u_int8_t)_SAA711XMODESource;
- (u_int8_t)_SAA711XCHXENOutputControl;
- (u_int8_t)_SAA711XLuminanceControl;
- (u_int8_t)_SAAA711XRTP0OutputPolarity;

@end

@implementation SAA711XChip

#pragma mark -SAA711XChip

- (ECVCaptureDevice<SAA711XDevice> *)device
{
	return device;
}
- (void)setDevice:(ECVCaptureDevice<SAA711XDevice> *const)obj
{
	device = obj;
	NSUserDefaults *const d = [NSUserDefaults standardUserDefaults];
	[d registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithDouble:0.5], ECVBrightnessKey,
		[NSNumber numberWithDouble:0.5], ECVContrastKey,
		[NSNumber numberWithDouble:0.5], ECVSaturationKey,
		[NSNumber numberWithDouble:0.5], ECVHueKey,
		nil]];
	_brightness = [[d objectForKey:ECVBrightnessKey] doubleValue];
	_contrast = [[d objectForKey:ECVContrastKey] doubleValue];
	_saturation = [[d objectForKey:ECVSaturationKey] doubleValue];
	_hue = [[d objectForKey:ECVHueKey] doubleValue];
}

#pragma mark -

- (BOOL)polarityInverted
{
	return _polarityInverted;
}
- (void)setPolarityInverted:(BOOL const)flag
{
	_polarityInverted = flag;
}

#pragma mark -

- (CGFloat)brightness
{
	return _brightness;
}
- (void)setBrightness:(CGFloat const)val
{
	_brightness = val;
	(void)[device writeSAA711XRegister:0x0a value:round(val * 0xff)];
	[[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithDouble:val] forKey:ECVBrightnessKey];
}
- (CGFloat)contrast
{
	return _contrast;
}
- (void)setContrast:(CGFloat const)val
{
	_contrast = val;
	(void)[device writeSAA711XRegister:0x0b value:round(val * 0x7f)];
	[[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithDouble:val] forKey:ECVContrastKey];
}
- (CGFloat)saturation
{
	return _saturation;
}
- (void)setSaturation:(CGFloat const)val
{
	_saturation = val;
	(void)[device writeSAA711XRegister:0x0c value:round(val * 0x7f)];
	[[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithDouble:val] forKey:ECVSaturationKey];
}
- (CGFloat)hue
{
	return _hue;
}
- (void)setHue:(CGFloat const)val
{
	_hue = val;
	(void)[device writeSAA711XRegister:0x0d value:round((val - 0.5f) * 0xff)];
	[[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithDouble:val] forKey:ECVHueKey];
}

#pragma mark -

- (BOOL)initialize
{
	ECVVideoFormat *const f = [(ECVCaptureDevice *)[self device] videoFormat];
	// Based on Table 184 in the datasheet.
	struct {
		u_int8_t reg;
		int16_t val;
	} const settings[] = {
		{0x01, 0x08},
		{0x02, SAA711XFUSE0Antialias | SAA711XFUSE1Amplifier | [self _SAA711XMODESource]},
		{0x03, SAA711XHOLDGAutomaticGainControlEnabled | SAA711XVBSLLongVerticalBlanking},
		{0x04, 0x90},
		{0x05, 0x90},
		{0x06, 0xeb},
		{0x07, 0xe0},
		{0x08, SAA711XVNOIVerticalNoiseReductionFast | SAA711XHTCHorizontalTimeConstantFastLocking | SAA711XFOETForcedOddEventToggle | [f SAA711XFSELManualFieldSelection]},
		{0x09, }, // Uh, what was this?
		{0x0e, SAA711XCCOMBAdaptiveChrominanceComb | SAA711XFCTCFastColorTimeConstant | [f SAA711XCSTDFormat]},
		{0x0f, SAA711XCGAINChromaGainValueNominal | SAA711XACGCAutomaticChromaGainControlEnabled},
		{0x10, 0x06},
		{0x11, [self _SAAA711XRTP0OutputPolarity]},
		{0x12, 0x00},
		{0x13, 0x00},
		{0x14, 0x01},
		{0x15, 0x11},
		{0x16, 0xfe},
		{0x17, 0x00}, // Must be 0x00 for GM7113 (v10).
		{0x18, 0x40},
		{0x19, 0x80},
		{0x1a, 0x77},
		{0x1b, 0x42},
		{0x1c, 0xa9},
		{0x1d, 0x01},
		{0x83, 0x31},
		{0x88, SAA711XSLM1ScalerDisabled | SAA711XSLM3AudioClockGenerationDisabled | [self _SAA711XCHXENOutputControl]},
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
- (NSUInteger)versionNumber
{
	u_int8_t version = 0;
	[device readSAA711XRegister:0x00 value:&version];
	return version;
}
- (NSSet *)supportedVideoFormats
{
	return [NSSet setWithObjects:
		[ECVVideoFormat_NTSC_M format],
		[ECVVideoFormat_PAL_60 format],
		[ECVVideoFormat_NTSC_443_60Hz format],
		[ECVVideoFormat_PAL_M format],
		[ECVVideoFormat_NTSC_J format],

		[ECVVideoFormat_PAL_BGDHI format],
		[ECVVideoFormat_NTSC_443_50Hz format],
		[ECVVideoFormat_PAL_N format],
		[ECVVideoFormat_NTSC_N format],
		[ECVVideoFormat_SECAM format],
		nil];
}
- (ECVVideoFormat *)defaultVideoFormat
{
	return [ECVVideoFormat_NTSC_M format];
}

#pragma mark -SAA711XChip(Private)

- (u_int8_t)_SAA711XMODESource
{
	ECVVideoSource *const s = [(ECVCaptureDevice *)[self device] videoSource];
	return [s SVideo] ? SAA711XMODESVideoAI12_YGain : SAA711XMODECompositeAI11;
}
- (u_int8_t)_SAA711XCHXENOutputControl
{
	switch([self _SAA711XMODESource]) {
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
- (u_int8_t)_SAA711XLuminanceControl
{
	ECVVideoSource *const s = [(ECVCaptureDevice *)[self device] videoSource];
	return [s SVideo] ? SAA711XBYPSChrominanceTrapCombBypass : SAA711XYCOMBAdaptiveLuminanceComb;
}
- (u_int8_t)_SAAA711XRTP0OutputPolarity
{
	return [self polarityInverted] ? SAA711XRTP0OutputPolarityInverted : 0;
}

#pragma mark -NSObject

- (id)init
{
	if((self = [super init])) {
		_polarityInverted = YES; // So far both devices are inverted, so...
		_brightness = 0.5;
		_contrast = 0.5;
		_saturation = 0.5;
		_hue = 0.5;
	}
	return self;
}

@end

@implementation ECVCommon60HzVideoFormat(SAA711XFSELManualFieldSelection)
- (u_int8_t)SAA711XFSELManualFieldSelection { return SAA711XFSELManualFieldSelection60Hz; };
@end
@implementation ECVCommon50HzVideoFormat(SAA711XFSELManualFieldSelection)
- (u_int8_t)SAA711XFSELManualFieldSelection { return SAA711XFSELManualFieldSelection50Hz; };
@end

@implementation ECVVideoFormat_NTSC_M(SAA711XCSTDFormat)
- (u_int8_t)SAA711XCSTDFormat { return SAA711XCSTDNTSCM; }
@end
@implementation ECVVideoFormat_PAL_60(SAA711XCSTDFormat)
- (u_int8_t)SAA711XCSTDFormat { return SAA711XCSTDPAL60Hz; }
@end
@implementation ECVVideoFormat_NTSC_443_60Hz(SAA711XCSTDFormat)
- (u_int8_t)SAA711XCSTDFormat { return SAA711XCSTDNTSC44360Hz; }
@end
@implementation ECVVideoFormat_PAL_M(SAA711XCSTDFormat)
- (u_int8_t)SAA711XCSTDFormat { return SAA711XCSTDPALM; }
@end
@implementation ECVVideoFormat_NTSC_J(SAA711XCSTDFormat)
- (u_int8_t)SAA711XCSTDFormat { return SAA711XCSTDNTSCJ; }
@end

@implementation ECVVideoFormat_PAL_BGDHI(SAA711XCSTDFormat)
- (u_int8_t)SAA711XCSTDFormat { return SAA711XCSTDPAL_BGDHI; }
@end
@implementation ECVVideoFormat_NTSC_443_50Hz(SAA711XCSTDFormat)
- (u_int8_t)SAA711XCSTDFormat { return SAA711XCSTDNTSC44350Hz; }
@end
@implementation ECVVideoFormat_PAL_N(SAA711XCSTDFormat)
- (u_int8_t)SAA711XCSTDFormat { return SAA711XCSTDPALN; }
@end
@implementation ECVVideoFormat_NTSC_N(SAA711XCSTDFormat)
- (u_int8_t)SAA711XCSTDFormat { return SAA711XCSTDNTSCN; }
@end
@implementation ECVVideoFormat_SECAM(SAA711XCSTDFormat)
- (u_int8_t)SAA711XCSTDFormat { return SAA711XCSTDSECAM; }
@end
