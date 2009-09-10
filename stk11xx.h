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

#define ARRAY_SIZE(x) numberof(x)
#define STK11XX_PERCENT(x, y) (((int)x * (int)y) / 100)

#define STK_INFO(x, y...)  //NSLog((NSString *)CFSTR(x), ##y)
#define STK_DEBUG(x, y...) //NSLog((NSString *)CFSTR(x), ##y)
#define STK_ERROR(x, y...) //NSLog((NSString *)CFSTR(x), ##y)
#define printk(x, y...)    //NSLog((NSString *)CFSTR(x), ##y)
#define msleep(x) usleep(1000 * (x))

struct stk11xx_coord {
	int x;
	int y;
};

typedef enum {
	STK11XX_PALETTE_RGB24,
	STK11XX_PALETTE_RGB32,
	STK11XX_PALETTE_BGR24,
	STK11XX_PALETTE_BGR32,
	STK11XX_PALETTE_UYVY,
	STK11XX_PALETTE_YUYV
} T_STK11XX_PALETTE;

typedef enum {
	STK11XX_80x60,
	STK11XX_128x96,
	STK11XX_160x120,
	STK11XX_213x160,
	STK11XX_320x240,
	STK11XX_640x480,
	STK11XX_720x480,
	STK11XX_720x576,
	STK11XX_800x600,
	STK11XX_1024x768,
	STK11XX_1280x1024,
	STK11XX_NBR_SIZES
} T_STK11XX_RESOLUTION;

static const struct stk11xx_coord stk11xx_image_sizes[STK11XX_NBR_SIZES] = {
	{   80,   60 },
	{  128,   96 },
	{  160,  120 },
	{  213,  160 },
	{  320,  240 },
	{  640,  480 },
	{  720,  480 },
	{  720,  576 },
	{  800,  600 },
	{ 1024,  768 },
	{ 1280, 1024 }
};

int dev_stk0408_camera_asleep(ECVSTK1160Controller *);
int dev_stk0408_configure_device(ECVSTK1160Controller *, int);
int dev_stk0408_start_stream(ECVSTK1160Controller *dev);
int dev_stk0408_write_208(ECVSTK1160Controller *dev, int val);
int dev_stk0408_write_saa(ECVSTK1160Controller *dev, int reg, int val);
int dev_stk0408_stop_stream(ECVSTK1160Controller *dev);
int dev_stk0408_initialize_device(ECVSTK1160Controller *dev);
int dev_stk0408_init_camera(ECVSTK1160Controller *dev);
int dev_stk0408_check_device(ECVSTK1160Controller *dev);
int dev_stk0408_write0(ECVSTK1160Controller *dev, int mask, int val);

int dev_stk0408_sensor_settings(ECVSTK1160Controller *dev);
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
