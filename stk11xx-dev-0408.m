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
#import "ECVSTK1160Device.h"
#import "stk11xx.h"
#import <unistd.h>

// Other Sources
#import "ECVDebug.h"

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
int dev_stk0408_initialize_device(ECVSTK1160Device *dev)
{
	usb_stk11xx_write_registry(dev, 0x0500, 0x0094);
	usb_stk11xx_write_registry(dev, 0x0203, 0x00a0);
	(void)[dev setFeatureAtIndex:1];

	usb_stk11xx_write_registry(dev, 0x0003, 0x0080);
	usb_stk11xx_write_registry(dev, 0x0001, 0x0003);
	dev_stk0408_write0(dev, 0x67, 1 << 5 | 1 << 0);
	struct {
		u_int16_t reg;
		u_int16_t val;
	} const settings[] = {
		{0x203, 0x04a},
		{0x00d, 0x000},
		{0x00f, 0x002},
		{0x103, 0x000},
		{0x018, 0x000},
		{0x01a, 0x014},
		{0x01b, 0x00e},
		{0x01c, 0x046},
		{0x019, 0x000},
		{0x300, 0x012},
		{0x350, 0x02d},
		{0x351, 0x001},
		{0x352, 0x000},
		{0x353, 0x000},
		{0x300, 0x080},
		{0x018, 0x010},
		{0x202, 0x00f},
	};
	NSUInteger i = 0;
	for(; i < numberof(settings); i++) usb_stk11xx_write_registry(dev, settings[i].reg, settings[i].val);
	usb_stk11xx_write_registry(dev, STK0408StatusRegistryIndex, 0x33);
	return 0;
}
int dev_stk0408_write0(ECVSTK1160Device *dev, u_int16_t mask, u_int16_t val)
{
	NSCAssert((mask & val) == val, @"Don't set values that will be masked out.");
	usb_stk11xx_write_registry(dev, 0x00, val);
	usb_stk11xx_write_registry(dev, 0x02, mask);
	return 0;
}
