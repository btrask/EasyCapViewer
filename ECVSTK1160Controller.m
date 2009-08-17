/* Copyright (c) 2009, Ben Trask
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * The names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

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
#import "ECVSTK1160Controller.h"

// Controllers
#import "ECVConfigController.h"

enum {
	ECVNewImageFlag = 0x80,
	ECVHighFieldFlag = 0x40
};
enum {
	ECVSTK1160SVideoInput = 0,
	ECVSTK1160Composite1Input = 1,
	ECVSTK1160Composite2Input = 2,
	ECVSTK1160Composite3Input = 3,
	ECVSTK1160Composite4Input = 4
};

static NSString *const ECVSTK1160VideoSourceKey = @"ECVSTK1160VideoSource";
static NSString *const ECVSTK1160ResolutionKey = @"ECVSTK1160Resolution";

@implementation ECVSTK1160Controller

#pragma mark +NSObject

- (void)initialize
{
	[[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithUnsignedInteger:ECVSTK1160Composite1Input], ECVSTK1160VideoSourceKey,
		[NSNumber numberWithUnsignedInteger:STK11XX_720x480], ECVSTK1160ResolutionKey,
		nil]];
}

#pragma mark -ECVCaptureController

- (id)initWithDevice:(io_service_t)device error:(out NSError **)outError
{
	if((self = [super initWithDevice:device error:outError])) {
		NSUserDefaults *const d = [NSUserDefaults standardUserDefaults];
		self.videoSource = [d objectForKey:ECVSTK1160VideoSourceKey];
		self.resolution = [d objectForKey:ECVSTK1160ResolutionKey];
		self.brightness = [[d objectForKey:ECVBrightnessKey] doubleValue];
		self.contrast = [[d objectForKey:ECVContrastKey] doubleValue];
		self.hue = [[d objectForKey:ECVHueKey] doubleValue];
		self.saturation = [[d objectForKey:ECVSaturationKey] doubleValue];
	}
	return self;
}
@synthesize sVideo = _sVideo;

#pragma mark -ECVCaptureController(ECVAbstract)

- (BOOL)requiresHighSpeed
{
	return YES;
}
- (NSSize)captureSize
{
	return NSMakeSize(view.x, view.y);
}
- (NSUInteger)simultaneousTransfers
{
	return 2;
}
- (NSUInteger)microframesPerTransfer
{
	return 512;
}
- (UInt8)isochReadingPipe
{
	return 2;
}
- (ECVVideoFormat)defaultVideoFormat
{
	return ECVNTSCFormat;
}
- (BOOL)supportsVideoFormat:(ECVVideoFormat)format
{
	switch(format) {
		case ECVNTSCFormat: return YES;
		case ECVPALFormat: return YES;
		default: return NO;
	}
}

#pragma mark -

- (BOOL)threaded_play
{
	dev_stk0408_initialize_device(self);
	dev_stk0408_init_camera(self);
	dev_stk11xx_camera_on(self);
	dev_stk0408_reconf_camera(self);
	dev_stk0408_start_stream(self);
	dev_stk0408_camera_settings(self);
	return YES;
}
- (BOOL)threaded_pause
{
	dev_stk0408_stop_stream(self);
	dev_stk11xx_camera_off(self);
	dev_stk0408_camera_asleep(self);
	return YES;
}
- (BOOL)threaded_watchdog
{
	SInt32 value;
	if(![self readValue:&value atIndex:0x0001]) return NO;
	NSLog(@"value is %d", value);
	return 0x0003 == value;
}
- (void)threaded_readFrame:(IOUSBLowLatencyIsocFrame *)frame bytes:(UInt8 const *)bytes
{
	size_t const length = (size_t)frame->frActCount;
	if(!length) return;
	size_t skip = 4;
	if(ECVNewImageFlag & bytes[0]) {
		[self threaded_startNewImageWithFieldType:ECVHighFieldFlag & bytes[0] ? ECVHighField : ECVLowField absoluteTime:frame->frTimeStamp];
		skip = 8;
	}
	if(length > skip) [self threaded_readImageBytes:bytes + skip length:length - skip];
}

#pragma mark -ECVCaptureController(ECVConfigOptional)

- (NSArray *)allVideoSources
{
	return [NSArray arrayWithObjects:
		[NSNumber numberWithUnsignedInteger:ECVSTK1160SVideoInput],
		[NSNumber numberWithUnsignedInteger:ECVSTK1160Composite1Input],
		[NSNumber numberWithUnsignedInteger:ECVSTK1160Composite2Input],
		[NSNumber numberWithUnsignedInteger:ECVSTK1160Composite3Input],
		[NSNumber numberWithUnsignedInteger:ECVSTK1160Composite4Input],
		nil];
}
- (NSString *)localizedStringForVideoSource:(id)obj
{
	switch([obj unsignedIntegerValue]) {
		case ECVSTK1160SVideoInput: return NSLocalizedString(@"S-Video", nil);
		case ECVSTK1160Composite1Input: return NSLocalizedString(@"Composite 1", nil);
		case ECVSTK1160Composite2Input: return NSLocalizedString(@"Composite 2", nil);
		case ECVSTK1160Composite3Input: return NSLocalizedString(@"Composite 3", nil);
		case ECVSTK1160Composite4Input: return NSLocalizedString(@"Composite 4", nil);
	}
	return nil;
}
- (id)videoSource
{
	return [NSNumber numberWithUnsignedInteger:_sVideo ? ECVSTK1160SVideoInput : vsettings.input];
}
- (void)setVideoSource:(id)obj
{
	NSUInteger const s = [obj unsignedIntegerValue];
	_sVideo = NO;
	switch(s) {
		case ECVSTK1160SVideoInput:
			_sVideo = YES;
			vsettings.input = 1;
			break;
		case ECVSTK1160Composite2Input: vsettings.input = 2; break;
		case ECVSTK1160Composite3Input: vsettings.input = 3; break;
		case ECVSTK1160Composite4Input: vsettings.input = 4; break;
		default: vsettings.input = 1; break;
	}
	[[NSUserDefaults standardUserDefaults] setObject:obj forKey:ECVSTK1160VideoSourceKey];
}

#pragma mark -

- (NSArray *)allResolutions
{
	return [NSArray arrayWithObjects:
		[NSNumber numberWithUnsignedInteger:STK11XX_640x480],
		[NSNumber numberWithUnsignedInteger:STK11XX_720x480],
		[NSNumber numberWithUnsignedInteger:STK11XX_720x576],
		nil];
}
- (NSString *)localizedStringForResolution:(id)obj
{
	T_STK11XX_RESOLUTION const r = [obj unsignedIntegerValue];
	return [NSString localizedStringWithFormat:NSLocalizedString(@"%dx%d", nil), stk11xx_image_sizes[r].x, stk11xx_image_sizes[r].y];
}
- (id)resolution
{
	return [NSNumber numberWithUnsignedInteger:resolution];
}
- (void)setResolution:(id)obj
{
	T_STK11XX_RESOLUTION const r = [obj unsignedIntegerValue];
	dev_stk0408_select_video_mode(self, stk11xx_image_sizes[r].x, stk11xx_image_sizes[r].y);
	[self noteVideoSettingDidChange];
	if(!self.fullScreen) [[self window] setContentSize:[self outputSize]];
	[[NSUserDefaults standardUserDefaults] setObject:obj forKey:ECVSTK1160ResolutionKey];
}

#pragma mark -

- (CGFloat)brightness
{
	return (CGFloat)vsettings.brightness / 0xFFFF;
}
- (void)setBrightness:(CGFloat)val
{
	vsettings.brightness = val * 0xFFFF;
	[[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithDouble:val] forKey:ECVBrightnessKey];
}
- (CGFloat)contrast
{
	return (CGFloat)vsettings.contrast / 0xFFFF;
}
- (void)setContrast:(CGFloat)val
{
	vsettings.contrast = val * 0xFFFF;
	[[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithDouble:val] forKey:ECVContrastKey];
}
- (CGFloat)hue
{
	return (CGFloat)vsettings.colour / 0xFFFF;
}
- (void)setHue:(CGFloat)val
{
	vsettings.colour = val * 0xFFFF;
	[[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithDouble:val] forKey:ECVHueKey];
}
- (CGFloat)saturation
{
	return (CGFloat)vsettings.hue / 0xFFFF;
}
- (void)setSaturation:(CGFloat)val
{
	vsettings.hue = val * 0xFFFF;
	[[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithDouble:val] forKey:ECVSaturationKey];
}

@end
