/**
 * @file stk11xx-dev-0408.c
 * @author Ivor Hewitt
 * @date 2009-01-01
 * @version v1.0.x
 *
 * @brief Driver for Syntek USB video camera
 *
 * @note Copyright (C) Nicolas VIVIEN
 *       Copyright (C) Ivor Hewitt
 *       Copyright (C) Ben Trask
 *
 * @par Licences
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
 */
#import "ECVSTK1160Controller.h"
#import "stk11xx.h"
#import "ECVConfigController.h"
#import <unistd.h>

enum {
	SAA7115MODECompositeAI11 = 0,
	SAA7115MODECompositeAI12 = 1,
	SAA7115MODECompositeAI21 = 2,
	SAA7115MODECompositeAI22 = 3,
	SAA7115MODECompositeAI23 = 4,
	SAA7115MODECompositeAI24 = 5,
	SAA7115MODESVideoAI11_GAI2 = 6,
	SAA7115MODESVideoAI12_GAI2 = 7,
	SAA7115MODESVideoAI11_YGain = 8,
	SAA7115MODESVideoAI12_YGain = 9,
	SAA7115FUSE0Antialias = 1 << 6,
	SAA7115FUSE1Amplifier = 1 << 7,
};
enum {
	SAA7115GAI18StaticGainControl1 = 1 << 0,
	SAA7115GAI28StaticGainControl2 = 1 << 1,
	SAA7115GAFIXGainControlUserProgrammable = 1 << 2,
	SAA7115HOLDGAutomaticGainControlEnabled = 0 << 3,
	SAA7115HOLDGAutomaticGainControlDisabled = 1 << 3,
	SAA7115CPOFFColorPeakControlDisabled = 1 << 4,
	SAA7115VBSLLongVerticalBlanking = 1 << 5,
	SAA7115HLNRSReferenceSelect = 1 << 6,
};
enum {
	SAA7115YCOMBAdaptiveLuminanceComb = 1 << 6,
	SAA7115BYPSChrominanceTrapCombBypass = 1 << 7,
};
enum {
	SAA7115VNOIVerticalNoiseReductionNormal = 0 << 0,
	SAA7115VNOIVerticalNoiseReductionFast = 1 << 0,
	SAA7115VNOIVerticalNoiseReductionFree = 2 << 0,
	SAA7115VNOIVerticalNoiseReductionBypass = 3 << 0,
	SAA7115HTCHorizontalTimeConstantTVMode = 0 << 3,
	SAA7115HTCHorizontalTimeConstantVTRMode = 1 << 3,
	SAA7115HTCHorizontalTimeConstantAutomatic = 2 << 3,
	SAA7115HTCHorizontalTimeConstantFastLocking = 3 << 3,
	SAA7115FOETForcedOddEventToggle = 1 << 5,
	SAA7115FSELManualFieldSelection50Hz = 0 << 6,
	SAA7115FSELManualFieldSelection60Hz = 1 << 6,
	SAA7115AUFDAutomaticFieldDetection = 1 << 7,
};
enum {
	SAA7115CGAINChromaGainValueMinimum = 0x00,
	SAA7115CGAINChromaGainValueNominal = 0x2a,
	SAA7115CGAINChromaGainValueMaximum = 0x7f,
	SAA7115ACGCAutomaticChromaGainControlEnabled = 0 << 7,
	SAA7115ACGCAutomaticChromaGainControlDisabled = 1 << 7,
};
enum {
	SAA7115RTP0OutputPolarityInverted = 1 << 3,
};
enum {
	SAA7115SLM1ScalerDisabled = 1 << 1,
	SAA7115SLM3AudioClockGenerationDisabled = 1 << 3,
	SAA7115CH1ENAD1X = 1 << 6,
	SAA7115CH2ENAD2X = 1 << 7,
};
enum {
	SAA7115CCOMBAdaptiveChrominanceComb = 1 << 0,
	SAA7115FCTCFastColorTimeConstant = 1 << 2,

	SAA7115AUTO0AutomaticChrominanceStandardDetection = 1 << 1,
	SAA7115CSTDPAL_BGDHI   = 0 << 4,
	SAA7115CSTDNTSC44350Hz = 1 << 4,
	SAA7115CSTDPALN        = 2 << 4,
	SAA7115CSTDNTSCN       = 3 << 4,
	SAA7115CSTDNTSCJ       = 4 << 4,
	SAA7115CSTDSECAM       = 5 << 4,

	SAA7115CSTDNTSCM       = SAA7115CSTDPAL_BGDHI,
	SAA7115CSTDPAL60Hz     = SAA7115CSTDNTSC44350Hz,
	SAA7115CSTDNTSC44360Hz = SAA7115CSTDPALN,
	SAA7115CSTDPALM        = SAA7115CSTDNTSCN,
};
static u_int8_t SAA7115MODEModeSelectForVideoSource(ECVSTK1160VideoSource s)
{
	switch(s) {
		case ECVSTK1160SVideoInput: return SAA7115MODESVideoAI12_YGain;
		case ECVSTK1160Composite1Input: return SAA7115MODECompositeAI11;
		case ECVSTK1160Composite2Input: return SAA7115MODECompositeAI21; // The rest are guesses.
		case ECVSTK1160Composite3Input: return SAA7115MODECompositeAI23;
		case ECVSTK1160Composite4Input: return SAA7115MODECompositeAI24;
		default: return 0;
	}
}
static u_int8_t SAA7115CHXENOutputControlForMODE(u_int8_t m)
{
	switch(m) {
		case SAA7115MODECompositeAI11:
		case SAA7115MODECompositeAI12:
			return SAA7115CH1ENAD1X;
		case SAA7115MODECompositeAI21:
		case SAA7115MODECompositeAI22:
		case SAA7115MODECompositeAI23:
		case SAA7115MODECompositeAI24:
			return SAA7115CH2ENAD2X;
		case SAA7115MODESVideoAI11_GAI2:
		case SAA7115MODESVideoAI12_GAI2:
		case SAA7115MODESVideoAI11_YGain:
		case SAA7115MODESVideoAI12_YGain:
			return SAA7115CH1ENAD1X | SAA7115CH2ENAD2X;
		default:
			return 0;
	}
}
static u_int8_t SAA7115CSTDColorStandardSelectionForVideoFormat(ECVSTK1160VideoFormat f)
{
	switch(f) {
		case ECVSTK1160Auto60HzFormat:    return SAA7115AUTO0AutomaticChrominanceStandardDetection;
		case ECVSTK1160NTSCMFormat:       return SAA7115CSTDNTSCM;
		case ECVSTK1160PAL60Format:       return SAA7115CSTDPAL60Hz;
		case ECVSTK1160PALMFormat:        return SAA7115CSTDPALM;
		case ECVSTK1160NTSC44360HzFormat: return SAA7115CSTDNTSC44360Hz;
		case ECVSTK1160NTSCJFormat:       return SAA7115CSTDNTSCJ;

		case ECVSTK1160Auto50HzFormat:    return SAA7115AUTO0AutomaticChrominanceStandardDetection;
		case ECVSTK1160PALBGDHIFormat:    return SAA7115CSTDPAL_BGDHI;
		case ECVSTK1160PALNFormat:        return SAA7115CSTDPALN;
		case ECVSTK1160NTSC44350HzFormat: return SAA7115CSTDNTSC44350Hz;
		case ECVSTK1160NTSCNFormat:       return SAA7115CSTDNTSCN;
		case ECVSTK1160SECAMFormat:       return SAA7115CSTDSECAM;
		default: return 0;
	}
}

/**
 * @param dev Device structure
 *
 * @returns 0 if all is OK
 *
 * @brief This function initializes the device.
 *
 * This function must be called at first. It's the start of the
 * initialization process. After this process, the device is
 * completly initalized and it's ready.
 *
 * This function is written from the USB log.
 */
int dev_stk0408_initialize_device(ECVSTK1160Controller *dev)
{
	dev_stk0408_write0(dev, 0x0007, 0x0001);

	usb_stk11xx_write_registry(dev, 0x0500, 0x0094);
	msleep(10);

	dev_stk0408_write0(dev, 0x0078, 0x0000);

	usb_stk11xx_write_registry(dev, 0x0203, 0x00a0);

	dev_stk0408_write0(dev, 0x07f, 0x001);

	(void)dev_stk11xx_check_device(dev, 500);

	usb_stk11xx_set_feature(dev, 1);

	return 0;
}

int dev_stk0408_write0(ECVSTK1160Controller *dev, int mask, int val)
{
	usb_stk11xx_write_registry(dev, 0x0002, mask);
	usb_stk11xx_write_registry(dev, 0x0000, val);
	return 0;
}

int dev_stk0408_write_saa(ECVSTK1160Controller *dev, u_int8_t reg, int16_t val)
{
	usb_stk11xx_read_registry(dev, 0x02ff, NULL);
	usb_stk11xx_write_registry(dev, 0x02ff, 0x0000);

	usb_stk11xx_write_registry(dev, 0x0204, reg);
	usb_stk11xx_write_registry(dev, 0x0205, val);
	usb_stk11xx_write_registry(dev, 0x0200, 0x0001);

	if(1 != dev_stk0408_check_device(dev)) return -1;

	usb_stk11xx_write_registry(dev, 0x02ff, 0x0000);

	return 1;
}

int dev_stk0408_set_resolution(ECVSTK1160Controller *dev)
{
/*
 * These registers control the resolution of the capture buffer.
 *
 * xres = (X - xsub) / 2
 * yres = (Y - ysub)
 *
 */
	int x,y,xsub,ysub;

	switch (dev.captureSize.width)
	{
		case 720:
			x = 0x5a0;
			xsub = 0;
			break;

		case 704:
		case 352:
		case 176:
			x = 0x584;
			xsub = 4;
			break;

		case 640:
		case 320:
		case 160:
			x = 0x508;
			xsub = 0x08;
			break;

		default:
			return -1;
	}

	switch (dev.captureSize.height)
	{
		case 576:
		case 288:
		case 144:
			y = 0x121;
			ysub = 0x1;
			break;

		case 480:
			y = dev.is60HzFormat ? 0xf3 : 0x110;
			ysub= dev.is60HzFormat ? 0x03 : 0x20;
			break;

		case 120:
		case 240:
			y = 0x103;
			ysub = 0x13;
			break;

		default:
			return -1;
	}

	usb_stk11xx_write_registry(dev, 0x0110, xsub ); // xsub
	usb_stk11xx_write_registry(dev, 0x0111, 0    );
	usb_stk11xx_write_registry(dev, 0x0112, ysub ); // ysub
	usb_stk11xx_write_registry(dev, 0x0113, 0    );
	usb_stk11xx_write_registry(dev, 0x0114, x    ); // X
	usb_stk11xx_write_registry(dev, 0x0115, 5    );
	usb_stk11xx_write_registry(dev, 0x0116, y    ); // Y
	usb_stk11xx_write_registry(dev, 0x0117, dev.is60HzFormat ? 0 : 1);

	return 0;
}

/**
 * @param dev Device structure
 *
 * @returns 0 if all is OK
 *
 * @brief This function initializes the device for the stream.
 *
 * It's the start. This function has to be called at first, before
 * enabling the video stream.
 */
int dev_stk0408_init_camera(ECVSTK1160Controller *dev)
{
	usb_stk11xx_write_registry(dev, 0x0003, 0x0080);
	usb_stk11xx_write_registry(dev, 0x0001, 0x0003);
	dev_stk0408_write0(dev, 0x0078, 0x0030);

	const int ids[] = {
		0x203,0x00d,0x00f,0x103,0x018,0x01b,0x01c,0x01a,0x019,
		0x300,0x350,0x351,0x352,0x353,0x300,0x018,0x202,
	};
	const int values[] = {
		0x04a,0x000,0x002,0x000,0x000,0x00e,0x046,0x014,0x000,
		0x012,0x02d,0x001,0x000,0x000,0x080,0x010,0x00f,
	};
	int i = 0;
	for(; i < numberof(values); i++) usb_stk11xx_write_registry(dev, ids[i], values[i]);

	usb_stk11xx_read_registry(dev, 0x0100, NULL);
	usb_stk11xx_write_registry(dev, 0x0100, 0x0033);

	dev_stk0408_sensor_settings(dev);

	usb_stk11xx_read_registry(dev, 0x0100, NULL);
	usb_stk11xx_write_registry(dev, 0x0100, 0x0033);
	usb_stk11xx_write_registry(dev, 0x0103, 0x0000);
	usb_stk11xx_write_registry(dev, 0x0100, 0x0033);

	usb_stk11xx_write_registry(dev, 0x0104, 0x0000);
	usb_stk11xx_write_registry(dev, 0x0105, 0x0000);
	usb_stk11xx_write_registry(dev, 0x0106, 0x0000);

	dev_stk11xx_camera_off(dev);

	usb_stk11xx_write_registry(dev, 0x0500, 0x0094);
	usb_stk11xx_write_registry(dev, 0x0500, 0x008c);
	usb_stk11xx_write_registry(dev, 0x0506, 0x0001);
	usb_stk11xx_write_registry(dev, 0x0507, 0x0000);

	//test and set?
	usb_stk11xx_write_registry(dev, 0x0504, 0x0012);
	usb_stk11xx_write_registry(dev, 0x0500, 0x008b);
	usb_stk11xx_write_registry(dev, 0x0504, 0x0012);
	usb_stk11xx_write_registry(dev, 0x0502, 0x0000);
	usb_stk11xx_write_registry(dev, 0x0503, 0x0080);
	usb_stk11xx_write_registry(dev, 0x0500, 0x008c);

	usb_stk11xx_write_registry(dev, 0x0504, 0x0010);
	usb_stk11xx_write_registry(dev, 0x0500, 0x008b);
	usb_stk11xx_write_registry(dev, 0x0504, 0x0010);
	usb_stk11xx_write_registry(dev, 0x0502, 0x0000);
	usb_stk11xx_write_registry(dev, 0x0503, 0x0000);
	usb_stk11xx_write_registry(dev, 0x0500, 0x008c);

	usb_stk11xx_write_registry(dev, 0x0504, 0x000e);
	usb_stk11xx_write_registry(dev, 0x0500, 0x008b);
	usb_stk11xx_write_registry(dev, 0x0504, 0x000e);
	usb_stk11xx_write_registry(dev, 0x0502, 0x0000);
	usb_stk11xx_write_registry(dev, 0x0503, 0x0000);
	usb_stk11xx_write_registry(dev, 0x0500, 0x008c);

	usb_stk11xx_write_registry(dev, 0x0504, 0x0016);
	usb_stk11xx_write_registry(dev, 0x0500, 0x008b);
	usb_stk11xx_write_registry(dev, 0x0504, 0x0016);
	usb_stk11xx_write_registry(dev, 0x0502, 0x0000);
	usb_stk11xx_write_registry(dev, 0x0503, 0x0000);
	usb_stk11xx_write_registry(dev, 0x0500, 0x008c);

	usb_stk11xx_write_registry(dev, 0x0504, 0x001a);
	usb_stk11xx_write_registry(dev, 0x0502, 0x0004);
	usb_stk11xx_write_registry(dev, 0x0503, 0x0004);
	usb_stk11xx_write_registry(dev, 0x0500, 0x008c);

	usb_stk11xx_write_registry(dev, 0x0504, 0x0002);
	usb_stk11xx_write_registry(dev, 0x0500, 0x008b);
	usb_stk11xx_write_registry(dev, 0x0504, 0x0002);
	usb_stk11xx_write_registry(dev, 0x0502, 0x0000);
	usb_stk11xx_write_registry(dev, 0x0503, 0x0080);
	usb_stk11xx_write_registry(dev, 0x0500, 0x008c);

	usb_stk11xx_write_registry(dev, 0x0504, 0x001c);
	usb_stk11xx_write_registry(dev, 0x0500, 0x008b);
	usb_stk11xx_write_registry(dev, 0x0504, 0x001c);
	usb_stk11xx_write_registry(dev, 0x0502, 0x0000);
	usb_stk11xx_write_registry(dev, 0x0503, 0x0080);
	usb_stk11xx_write_registry(dev, 0x0500, 0x008c);

	dev_stk11xx_camera_on(dev);
	usb_stk11xx_write_registry(dev, 0x0106, 0x0000);

	dev_stk0408_set_resolution(dev);
	usb_stk11xx_write_registry(dev, 0x0504, 0x0002);
	usb_stk11xx_write_registry(dev, 0x0500, 0x008b);
	usb_stk11xx_write_registry(dev, 0x0504, 0x0002);
	usb_stk11xx_write_registry(dev, 0x0502, 0x0000);
	usb_stk11xx_write_registry(dev, 0x0503, 0x0080);
	usb_stk11xx_write_registry(dev, 0x0500, 0x008c);

	usb_stk11xx_write_registry(dev, 0x0504, 0x001c);
	usb_stk11xx_write_registry(dev, 0x0500, 0x008b);
	usb_stk11xx_write_registry(dev, 0x0504, 0x001c);
	usb_stk11xx_write_registry(dev, 0x0502, 0x0000);
	usb_stk11xx_write_registry(dev, 0x0503, 0x0080);
	usb_stk11xx_write_registry(dev, 0x0500, 0x008c);

	usb_stk11xx_write_registry(dev, 0x0504, 0x0002);
	usb_stk11xx_write_registry(dev, 0x0500, 0x008b);
	usb_stk11xx_write_registry(dev, 0x0504, 0x0002);
	usb_stk11xx_write_registry(dev, 0x0502, 0x0000);
	usb_stk11xx_write_registry(dev, 0x0503, 0x0000);
	usb_stk11xx_write_registry(dev, 0x0500, 0x008c);

	usb_stk11xx_write_registry(dev, 0x0504, 0x001c);
	usb_stk11xx_write_registry(dev, 0x0500, 0x008b);
	usb_stk11xx_write_registry(dev, 0x0504, 0x001c);
	usb_stk11xx_write_registry(dev, 0x0502, 0x0000);
	usb_stk11xx_write_registry(dev, 0x0503, 0x0000);
	usb_stk11xx_write_registry(dev, 0x0500, 0x008c);

	return 0;
}

int dev_stk0408_check_device(ECVSTK1160Controller *dev)
{
	int i;
	int value;
	const int retry=2;

	for (i=0; i < retry; i++) {
		usb_stk11xx_read_registry(dev, 0x201, &value);

//writes to 204/204 return 4 on success
//writes to 208 return 1 on success

		if (value == 0x04 || value == 0x01)
			return 1;

		if (value != 0x00)
		{
			STK_ERROR("Check device return error (0x0201 = %02X) !\n", value);
			return -1;
		}
//		msleep(10);
	}

	return 0;
}


/**
 * @param dev Device structure
 *
 * @returns 0 if all is OK
 *
 * @brief This function sets the default sensor settings
 *
 * We set some registers in using a I2C bus.
 * WARNING, the sensor settings can be different following the situation.
 */

int dev_stk0408_sensor_settings(ECVSTK1160Controller *dev)
{
	// Based on Table 184 in the datasheet.
	struct {
		u_int8_t reg;
		int16_t val;
	} settings[] = {
		{0x01, 0x08},
		{0x03, SAA7115HOLDGAutomaticGainControlEnabled | SAA7115VBSLLongVerticalBlanking},
		{0x04, 0x90},
		{0x05, 0x90},
		{0x06, 0xeb},
		{0x07, 0xe0},
		{0x08, SAA7115VNOIVerticalNoiseReductionFast | SAA7115HTCHorizontalTimeConstantFastLocking | SAA7115FOETForcedOddEventToggle | (dev.is60HzFormat ? SAA7115FSELManualFieldSelection60Hz : SAA7115FSELManualFieldSelection50Hz)},
		{0x09, dev.SVideo ? SAA7115BYPSChrominanceTrapCombBypass : SAA7115YCOMBAdaptiveLuminanceComb},
		{0x0e, SAA7115CCOMBAdaptiveChrominanceComb | SAA7115FCTCFastColorTimeConstant | SAA7115CSTDColorStandardSelectionForVideoFormat(dev.videoFormat)},
		{0x0f, SAA7115CGAINChromaGainValueNominal | SAA7115ACGCAutomaticChromaGainControlEnabled},
		{0x10, 0x06},
		{0x11, SAA7115RTP0OutputPolarityInverted},
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
	};
	NSUInteger i;
	for(i = 0; i < numberof(settings); i++) (void)dev_stk0408_write_saa(dev, settings[i].reg, settings[i].val);
	for(i = 0x41; i <= 0x57; i++) (void)dev_stk0408_write_saa(dev, i, 0xff);
	(void)dev_stk0408_set_source(dev, dev.videoSource);
	(void)dev_stk0408_set_brightness(dev, dev.brightness);
	(void)dev_stk0408_set_contrast(dev, dev.contrast);
	(void)dev_stk0408_set_saturation(dev, dev.saturation);
	(void)dev_stk0408_set_hue(dev, dev.hue);
	return 0;
}
int dev_stk0408_set_source(ECVSTK1160Controller *dev, ECVSTK1160VideoSource source)
{
	u_int8_t const MODE = SAA7115MODEModeSelectForVideoSource(dev.videoSource);
	dev_stk0408_write_saa(dev, 0x02, SAA7115FUSE0Antialias | SAA7115FUSE1Amplifier | MODE);
	dev_stk0408_write_saa(dev, 0x88, SAA7115SLM1ScalerDisabled | SAA7115SLM3AudioClockGenerationDisabled | SAA7115CHXENOutputControlForMODE(MODE));
	return 1;
}
int dev_stk0408_set_brightness(ECVSTK1160Controller *dev, CGFloat brightness)
{
	return dev_stk0408_write_saa(dev, 0x0a, round(brightness * 0xff));
}
int dev_stk0408_set_contrast(ECVSTK1160Controller *dev, CGFloat contrast)
{
	return dev_stk0408_write_saa(dev, 0x0b, round(contrast * 0x88));
}
int dev_stk0408_set_saturation(ECVSTK1160Controller *dev, CGFloat saturation)
{
	return dev_stk0408_write_saa(dev, 0x0c, round(saturation * 0x80));
}
int dev_stk0408_set_hue(ECVSTK1160Controller *dev, CGFloat hue)
{
	return dev_stk0408_write_saa(dev, 0x0d, round((dev.hue - 0.5f) * 0xff));
}

enum {
	STK0408Streaming = 1 << 7,
};
int dev_stk0408_set_streaming(ECVSTK1160Controller *dev, int streaming)
{
	int value;
	usb_stk11xx_read_registry(dev, 0x0100, &value);
	if(streaming) value |= STK0408Streaming;
	else value &= ~STK0408Streaming;
	usb_stk11xx_write_registry(dev, 0x0100, value);
	return 0;
}
