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

enum {
	STK0408StatusRegistryIndex = 0x100,
};
enum {
	STK0408StatusStreaming = 1 << 7,
};

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
	dev_stk0408_check_device(dev);
	usb_stk11xx_set_feature(dev, 1);

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

int dev_stk0408_set_resolution(ECVSTK1160Device *dev)
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
int dev_stk0408_init_camera(ECVSTK1160Device *dev)
{
	usb_stk11xx_write_registry(dev, 0x0500, 0x0094);
	usb_stk11xx_write_registry(dev, 0x0500, 0x008c);
	usb_stk11xx_write_registry(dev, 0x0506, 0x0001);
	usb_stk11xx_write_registry(dev, 0x0507, 0x0000);

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

int dev_stk0408_check_device(ECVSTK1160Device *dev)
{
	int const retry = 2;
	int i = 0;
	for(; i < retry; i++) {
		int value;
		usb_stk11xx_read_registry(dev, 0x201, &value);
		// Writes to 204/205 return 4 on success.
		// Writes to 208 return 1 on success.
		if(0x04 == value || 0x01 == value) return 0;
		if(0x00 != value) {
			ECVLog(ECVError, @"Check device return error (0x0201 = %02X) !\n", value);
			return -1;
		}
	}
	return 0;
}

int dev_stk0408_set_streaming(ECVSTK1160Device *dev, BOOL streaming)
{
	int value;
	usb_stk11xx_read_registry(dev, STK0408StatusRegistryIndex, &value);
	if(streaming) value |= STK0408StatusStreaming;
	else value &= ~STK0408StatusStreaming;
	usb_stk11xx_write_registry(dev, STK0408StatusRegistryIndex, value);
	return 0;
}
