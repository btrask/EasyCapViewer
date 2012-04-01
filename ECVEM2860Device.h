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

enum { // TODO: Move this and related SAA711X format information to the SAA711X header.
	ECVSAA711XAuto60HzFormat = 0,
	ECVSAA711XNTSCMFormat = 8,
	ECVSAA711XPAL60Format = 2,
	ECVSAA711XNTSC44360HzFormat = 6,
	ECVSAA711XPALMFormat = 3,
	ECVSAA711XNTSCJFormat = 9,

	ECVSAA711XAuto50HzFormat = 1,
	ECVSAA711XPALBGDHIFormat = 10,
	ECVSAA711XNTSC44350HzFormat = 7,
	ECVSAA711XPALNFormat = 4,
	ECVSAA711XNTSCNFormat = 5,
	ECVSAA711XSECAMFormat = 11,
};
typedef NSUInteger ECVSAA711XVideoFormat;
static BOOL ECVSAA711XVideoFormatIs60Hz(ECVSAA711XVideoFormat const f)
{
	switch(f) {
		case ECVSAA711XAuto60HzFormat:
		case ECVSAA711XNTSCMFormat:
		case ECVSAA711XPAL60Format:
		case ECVSAA711XPALMFormat:
		case ECVSAA711XNTSC44360HzFormat:
		case ECVSAA711XNTSCJFormat:
			return YES;
		case ECVSAA711XAuto50HzFormat:
		case ECVSAA711XPALBGDHIFormat:
		case ECVSAA711XPALNFormat:
		case ECVSAA711XNTSCNFormat:
		case ECVSAA711XNTSC44350HzFormat:
		case ECVSAA711XSECAMFormat:
			return NO;
		default:
			ECVCAssertNotReached(@"Invalid video format.");
			return NO;
	}
}

@interface ECVEM2860Device : ECVCaptureDevice <ECVCaptureDeviceConfiguring, ECVComponentConfiguring, SAA711XDevice>
{
	@private
	ECVEM2860VideoSource _videoSource;
	ECVSAA711XVideoFormat _videoFormat;
	SAA711XChip *_SAA711XChip;
	NSUInteger _offset;
}

- (ECVEM2860VideoSource)videoSource;
- (void)setVideoSource:(ECVEM2860VideoSource const)source;
- (ECVSAA711XVideoFormat)videoFormat;
- (void)setVideoFormat:(ECVSAA711XVideoFormat const)format;

@end
