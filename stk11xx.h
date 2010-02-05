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
int dev_stk0408_initialize_device(ECVSTK1160Device *dev);
int dev_stk0408_init_camera(ECVSTK1160Device *dev);
int dev_stk0408_check_device(ECVSTK1160Device *dev);
int dev_stk0408_write0(ECVSTK1160Device *dev, int mask, int val);
int dev_stk0408_set_resolution(ECVSTK1160Device *dev);
int dev_stk0408_set_streaming(ECVSTK1160Device *dev, int streaming);

static void usb_stk11xx_write_registry(ECVSTK1160Device *dev, u_int16_t i, u_int16_t v)
{
	(void)[dev writeValue:v atIndex:i];
}
static void usb_stk11xx_read_registry(ECVSTK1160Device *dev, u_int16_t i, int32_t *v)
{
	(void)[dev readValue:(SInt32 *)v atIndex:i];
}
static void usb_stk11xx_set_feature(ECVSTK1160Device *dev, int i)
{
	(void)[dev setFeatureAtIndex:i];
}
static void dev_stk11xx_camera_on(ECVSTK1160Device *dev)
{
	(void)[dev setAlternateInterface:5];
}
static void dev_stk11xx_camera_off(ECVSTK1160Device *dev)
{
	(void)[dev setAlternateInterface:0];
}
