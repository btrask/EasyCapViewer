/* Copyright (C) 2012  Ben Trask

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>. */
#import "ECVCaptureDevice.h"
#import "SAA711XChip.h"
#import "ECVComponentConfiguring.h"
#import "ECVDebug.h"

enum {
	ECVEM2860SVideoInput = 0,
	ECVEM2860CompositeInput = 1,
};
typedef NSUInteger ECVEM2860VideoSource;

@interface ECVEM2860Device : ECVCaptureDevice <ECVCaptureDeviceConfiguring, ECVComponentConfiguring, SAA711XDevice>
{
	@private
	ECVEM2860VideoSource _videoSource;
	SAA711XChip *_SAA711XChip;
	NSUInteger _offset;
}

- (ECVEM2860VideoSource)videoSource;
- (void)setVideoSource:(ECVEM2860VideoSource const)source;

@end
