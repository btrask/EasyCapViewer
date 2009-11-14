/** 
 * @file stk11xx.h
 * @author Nicolas VIVIEN
 * @date 2006-10-23
 * @version v2.0.x
 *
 * @brief Driver for Syntek USB video camera
 *
 * @note Copyright (C) Nicolas VIVIEN
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
 *
 * @par SubVersion
 *   $Date: 2009-03-25 09:13:05 -0500 (Wed, 25 Mar 2009) $
 *   $Revision: 84 $
 *   $Author: nicklas79 $
 *   $HeadURL: https://syntekdriver.svn.sourceforge.net/svnroot/syntekdriver/trunk/driver/stk11xx.h $
 */
#import "ECVDebug.h"

#define STK11XX_PERCENT(x, y) (((int)x * (int)y) / 100)

#define STK_ERROR(x, y...) ECVLog(ECVError, (NSString *)CFSTR(x), ##y)
#define msleep(x) usleep((x) * ECVMicrosecondsPerMillisecond)

struct stk11xx_coord {
	int x;
	int y;
};

enum {
	ECVSTK1160SVideoInput = 0,
	ECVSTK1160Composite1Input = 1,
	ECVSTK1160Composite2Input = 2,
	ECVSTK1160Composite3Input = 3,
	ECVSTK1160Composite4Input = 4
};
typedef NSUInteger ECVSTK1160VideoSource;

int dev_stk0408_camera_asleep(ECVSTK1160Controller *);
int dev_stk0408_write_saa(ECVSTK1160Controller *dev, u_int8_t reg, int16_t val);
int dev_stk0408_initialize_device(ECVSTK1160Controller *dev);
int dev_stk0408_init_camera(ECVSTK1160Controller *dev);
int dev_stk0408_check_device(ECVSTK1160Controller *dev);
int dev_stk0408_write0(ECVSTK1160Controller *dev, int mask, int val);
int dev_stk0408_set_streaming(ECVSTK1160Controller *dev, int streaming);

int dev_stk0408_sensor_settings(ECVSTK1160Controller *dev);
int dev_stk0408_set_source(ECVSTK1160Controller *dev, ECVSTK1160VideoSource source);
int dev_stk0408_set_brightness(ECVSTK1160Controller *dev, CGFloat brightness);
int dev_stk0408_set_contrast(ECVSTK1160Controller *dev, CGFloat contrast);
int dev_stk0408_set_saturation(ECVSTK1160Controller *dev, CGFloat saturation);
int dev_stk0408_set_hue(ECVSTK1160Controller *dev, CGFloat hue);

static void usb_stk11xx_write_registry(ECVSTK1160Controller *dev, u_int16_t index, u_int16_t value)
{
	(void)[dev writeValue:value atIndex:index];
}
static void usb_stk11xx_read_registry(ECVSTK1160Controller *dev, u_int16_t index, int32_t *value)
{
	(void)[dev readValue:(SInt32 *)value atIndex:index];
}
static void usb_stk11xx_set_feature(ECVSTK1160Controller *dev, int index)
{
	(void)[dev setFeatureAtIndex:index];
}
static void dev_stk11xx_camera_on(ECVSTK1160Controller *dev)
{
	(void)[dev setAlternateInterface:5];
}
static void dev_stk11xx_camera_off(ECVSTK1160Controller *dev)
{
	(void)[dev setAlternateInterface:0];
}
static int dev_stk11xx_check_device(ECVSTK1160Controller *dev, int nbr)
{
	int i;
	int value;

	for (i=0; i<nbr; i++) {
		usb_stk11xx_read_registry(dev, 0x201, &value);
		
		if (value == 0x00) {
		}
		else if ((value == 0x11) || (value == 0x14)) {
		}
		else if ((value == 0x30) || (value == 0x31)) {
		}
		else if ((value == 0x51)) {
		}
		else if ((value == 0x70) || (value == 0x71)) {
		}
		else if ((value == 0x91)) {
		}
		else if (value == 0x01) {
			return 1;
		} else if ((value == 0x04) || (value == 0x05)) {
			return 1;
		} else if (value == 0x15) {
			return 1;
		} else {
			STK_ERROR("Check device return error (0x0201 = %02X) !\n", value);
			return -1;
		}
	}

	return 0;
}
