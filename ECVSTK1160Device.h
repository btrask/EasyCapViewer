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
// Models
#import "ECVCaptureDevice.h"

// Chipsets
#import "SAA711XChip.h"
#import "VT1612AChip.h"

// Other Sources
#import "ECVComponentConfiguring.h"

enum {
	ECVSTK1160SVideoInput = 0,
	ECVSTK1160Composite1Input = 1,
	ECVSTK1160Composite2Input = 2,
	ECVSTK1160Composite3Input = 3,
	ECVSTK1160Composite4Input = 4,
};
typedef NSUInteger ECVSTK1160VideoSource;

@interface ECVSTK1160Device : ECVCaptureDevice <ECVCaptureDeviceConfiguring, ECVComponentConfiguring, SAA711XDevice, VT1612ADevice>
{
	@private
	ECVSTK1160VideoSource _videoSource;
	SAA711XChip *_SAA711XChip;
	VT1612AChip *_VT1612AChip;
	NSUInteger _offset;
}

- (ECVSTK1160VideoSource)videoSource;
- (void)setVideoSource:(ECVSTK1160VideoSource const)source;

- (BOOL)readIndex:(UInt16 const)i value:(out UInt8 *const)outValue;
- (BOOL)writeIndex:(UInt16 const)i value:(UInt8 const)v;
- (BOOL)setFeatureAtIndex:(u_int16_t)i;

@end
