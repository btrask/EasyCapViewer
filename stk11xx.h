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
enum {
	STK0408StatusRegistryIndex = 0x100,
};
enum {
	STK0408StatusStreaming = 1 << 7,
};

int dev_stk0408_initialize_device(ECVSTK1160Device *dev);
int dev_stk0408_check_device(ECVSTK1160Device *dev);
int dev_stk0408_write0(ECVSTK1160Device *dev, u_int16_t mask, u_int16_t val);

static void usb_stk11xx_write_registry(ECVSTK1160Device *dev, u_int16_t i, u_int16_t v)
{
	(void)[dev writeIndex:i value:v];
}
static void usb_stk11xx_read_registry(ECVSTK1160Device *dev, u_int16_t i, u_int8_t *v)
{
	(void)[dev readIndex:i value:v];
}
