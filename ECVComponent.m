/* Copyright (c) 2010, Ben Trask
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
#import <objc/objc-runtime.h>

// Models
#import "ECVVideoStorage.h"
#import "ECVVideoFrame.h"

// Video Devices
#import "ECVCaptureDevice.h"

// Other Sources
#import "ECVDebug.h"
#import "ECVComponentConfiguring.h"

typedef struct {
	ECVCaptureDevice<ECVComponentConfiguring> *device;
	CFMutableDictionaryRef frameByBuffer;
	TimeBase timeBase;
} ECVCStorage;

#define VD_BASENAME() ECV
#define VD_GLOBALS() ECVCStorage *

#define COMPONENT_DISPATCH_FILE "ECVComponentDispatch.h"
#define CALLCOMPONENT_BASENAME() VD_BASENAME()
#define	CALLCOMPONENT_GLOBALS() VD_GLOBALS() storage
#define COMPONENT_UPP_SELECT_ROOT() VD

#include <CoreServices/Components.k.h>
#include <QuickTime/QuickTimeComponents.k.h>
#include <QuickTime/ComponentDispatchHelper.c>

#if defined(__i386__)
	#define ECV_MSG_SEND_CGFLOAT ((CGFloat (*)(id, SEL))objc_msgSend_fpret)
#else
	#define ECV_MSG_SEND_CGFLOAT ((CGFloat (*)(id, SEL))objc_msgSend)
#endif

#define ECV_CALLCOMPONENT_FUNCTION(name, args...) pascal ComponentResult ADD_CALLCOMPONENT_BASENAME(name)(VD_GLOBALS() self, ##args)
#define ECV_VDIG_FUNCTION(name, args...) pascal VideoDigitizerError ADD_CALLCOMPONENT_BASENAME(name)(VD_GLOBALS() self, ##args)
#define ECV_VDIG_FUNCTION_UNIMPLEMENTED(name, args...) ECV_VDIG_FUNCTION(name, ##args) { ECV_DEBUG_LOG(); return digiUnimpErr; }
#define ECV_VDIG_PROPERTY_UNIMPLEMENTED(prop) \
	ECV_VDIG_FUNCTION_UNIMPLEMENTED(Get ## prop, unsigned short *v)\
	ECV_VDIG_FUNCTION_UNIMPLEMENTED(Set ## prop, unsigned short *v)
#define ECV_VDIG_PROPERTY(prop, getterSel, setterSel) \
	ECV_VDIG_FUNCTION(Get ## prop, unsigned short *v)\
	{\
		ECV_DEBUG_LOG();\
		if(![self->device respondsToSelector:getterSel]) return digiUnimpErr;\
		*v = ECV_MSG_SEND_CGFLOAT(self->device, getterSel) * USHRT_MAX;\
		return noErr;\
	}\
	ECV_VDIG_FUNCTION(Set ## prop, unsigned short *v)\
	{\
		ECV_DEBUG_LOG();\
		if(![self->device respondsToSelector:setterSel]) return digiUnimpErr;\
		(void)objc_msgSend(self->device, setterSel, (CGFloat)*v / USHRT_MAX);\
		return noErr;\
	}

static Rect ECVNSRectToRect(NSRect r)
{
	return (Rect){NSMinX(r), NSMinY(r), NSMaxX(r), NSMaxY(r)};
}

ECV_CALLCOMPONENT_FUNCTION(Open, ComponentInstance instance)
{
	ECV_DEBUG_LOG();
	if(CountComponentInstances((Component)self) > 1) return -1;
	if(!self) {
		NSAutoreleasePool *const pool = [[NSAutoreleasePool alloc] init];
		[[NSUserDefaults standardUserDefaults] addSuiteNamed:[[NSBundle bundleForClass:[ECVCaptureDevice class]] objectForInfoDictionaryKey:@"ECVMainSuiteName"]];
		NSDictionary *matchDict = nil;
		Class const class = [ECVCaptureDevice getMatchingDictionary:&matchDict forDeviceDictionary:[[ECVCaptureDevice deviceDictionaries] lastObject]];
		if(![class conformsToProtocol:@protocol(ECVComponentConfiguring)]) {
			[pool drain];
			return -1;
		}
		self = calloc(1, sizeof(ECVCStorage));
		self->device = [[class alloc] initWithService:IOServiceGetMatchingService(kIOMasterPortDefault, (CFDictionaryRef)[matchDict retain]) error:NULL];
		if(!self->device) {
			ECV_DEBUG_LOG();
			free(self);
			[pool drain];
			return internalComponentErr;
		}
		[self->device setDeinterlacingMode:ECVLineDoubleLQ];
		self->frameByBuffer = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, NULL, &kCFTypeDictionaryValueCallBacks);
		SetComponentInstanceStorage(instance, (Handle)self);
		[pool drain];
	}
	return noErr;
}
ECV_CALLCOMPONENT_FUNCTION(Close, ComponentInstance instance)
{
	ECV_DEBUG_LOG();
	if(!self) return noErr;
	NSAutoreleasePool *const pool = [[NSAutoreleasePool alloc] init];
	[self->device release];
	CFRelease(self->frameByBuffer);
	free(self);
	[pool drain];
	return noErr;
}
ECV_CALLCOMPONENT_FUNCTION(Version)
{
	ECV_DEBUG_LOG();
	return vdigInterfaceRev << 16;
}

ECV_VDIG_FUNCTION(GetDigitizerInfo, DigitizerInfo *info)
{
	ECV_DEBUG_LOG();
	NSAutoreleasePool *const pool = [[NSAutoreleasePool alloc] init];
	ECVIntegerSize const s = [self->device captureSize];
	[pool drain];

	*info = (DigitizerInfo){};
	info->vdigType = vdTypeBasic;
	info->inputCapabilityFlags = digiInDoesNTSC | digiInDoesPAL | digiInDoesSECAM | digiInDoesColor | digiInDoesComposite | digiInDoesSVideo;
	info->outputCapabilityFlags = digiOutDoes32 | digiOutDoesCompress | digiOutDoesCompressOnly | digiOutDoesNotNeedCopyOfCompressData;
	info->inputCurrentFlags = info->inputCapabilityFlags;
	info->outputCurrentFlags = info->outputCurrentFlags;

	info->minDestWidth = 0;
	info->minDestHeight = 0;
	info->maxDestWidth = s.width;
	info->maxDestHeight = s.height;
	return noErr;
}
ECV_VDIG_FUNCTION(GetCurrentFlags, long *inputCurrentFlag, long *outputCurrentFlag)
{
	ECV_DEBUG_LOG();
	DigitizerInfo info;
	if(!ADD_CALLCOMPONENT_BASENAME(GetDigitizerInfo)(self, &info)) return -1;
	*inputCurrentFlag = info.inputCurrentFlags;
	*outputCurrentFlag = info.outputCurrentFlags;
	return noErr;
}

ECV_VDIG_FUNCTION(GetNumberOfInputs, short *inputs)
{
	ECV_DEBUG_LOG();
	NSAutoreleasePool *const pool = [[NSAutoreleasePool alloc] init];
	*inputs = [self->device numberOfInputs] - 1;
	[pool drain];
	return noErr;
}
ECV_VDIG_FUNCTION(GetInputFormat, short input, short *format)
{
	ECV_DEBUG_LOG();
	NSAutoreleasePool *const pool = [[NSAutoreleasePool alloc] init];
	*format = [self->device inputFormatForInputAtIndex:input];
	[pool drain];
	return noErr;
}
ECV_VDIG_FUNCTION(GetInputName, long videoInput, Str255 name)
{
	ECV_DEBUG_LOG();
	NSAutoreleasePool *const pool = [[NSAutoreleasePool alloc] init];
	CFStringGetPascalString((CFStringRef)[self->device localizedStringForInputAtIndex:videoInput], name, 256, kCFStringEncodingUTF8);
	[pool drain];
	return noErr;
}
ECV_VDIG_FUNCTION(GetInput, short *input)
{
	ECV_DEBUG_LOG();
	NSAutoreleasePool *const pool = [[NSAutoreleasePool alloc] init];
	*input = [self->device inputIndex];
	[pool drain];
	return noErr;
}
ECV_VDIG_FUNCTION(SetInput, short input)
{
	ECV_DEBUG_LOG();
	NSAutoreleasePool *const pool = [[NSAutoreleasePool alloc] init];
	[self->device setInputIndex:input];
	[pool drain];
	return noErr;
}
ECV_VDIG_FUNCTION(SetInputStandard, short inputStandard)
{
	ECV_DEBUG_LOG();
	NSAutoreleasePool *const pool = [[NSAutoreleasePool alloc] init];
	[self->device setInputStandard:inputStandard];
	[pool drain];
	return noErr;
}

ECV_VDIG_FUNCTION(GetDeviceNameAndFlags, Str255 outName, UInt32 *outNameFlags)
{
	ECV_DEBUG_LOG();
	*outNameFlags = kNilOptions;
	CFStringGetPascalString(CFSTR("Test Device"), outName, 256, kCFStringEncodingUTF8);
	// TODO: Enumerate the devices and register vdigs for each. Use vdDeviceFlagHideDevice for ourself. Not sure if this is actually necessary (?)
	return noErr;
}

ECV_VDIG_FUNCTION(GetCompressionTime, OSType compressionType, short depth, Rect *srcRect, CodecQ *spatialQuality, CodecQ *temporalQuality, unsigned long *compressTime)
{
	ECV_DEBUG_LOG();
	if(compressionType && [self->device pixelFormatType] != compressionType) return noCodecErr;
	*spatialQuality = codecLosslessQuality;
	*temporalQuality = 0;
	*compressTime = 0;
	return noErr;
}
ECV_VDIG_FUNCTION(GetCompressionTypes, VDCompressionListHandle h)
{
	ECV_DEBUG_LOG();
	SInt8 const handleState = HGetState((Handle)h);
	HUnlock((Handle)h);
	SetHandleSize((Handle)h, sizeof(VDCompressionList));
	HLock((Handle)h);

	CodecType const codec = [self->device pixelFormatType];
	ComponentDescription cd = {compressorComponentType, codec, 0, kNilOptions, kAnyComponentFlagsMask};
	VDCompressionListPtr const p = *h;
	p[0] = (VDCompressionList){
		.codec = FindNextComponent(NULL, &cd),
		.cType = codec,
		.formatFlags = codecInfoDepth24,
		.compressFlags = codecInfoDoes32,
	};
	CFStringGetPascalString(CFSTR("Test Type Name"), p[0].typeName, 64, kCFStringEncodingUTF8);
	CFStringGetPascalString(CFSTR("Test Name"), p[0].name, 64, kCFStringEncodingUTF8);

	HSetState((Handle)h, handleState);
	return noErr;
}
ECV_VDIG_FUNCTION(SetCompressionOnOff, Boolean state)
{
	ECV_DEBUG_LOG();
	NSAutoreleasePool *const pool = [[NSAutoreleasePool alloc] init];
	[self->device setPlaying:!!state];
	[pool drain];
	return noErr;
}
ECV_VDIG_FUNCTION(SetCompression, OSType compressType, short depth, Rect *bounds, CodecQ spatialQuality, CodecQ temporalQuality, long keyFrameRate)
{
	ECV_DEBUG_LOG();
	if(compressType && [self->device pixelFormatType] != compressType) return noCodecErr;
	// TODO: Most of these settings don't apply to us...
	return noErr;
}
ECV_VDIG_FUNCTION(CompressOneFrameAsync)
{
	ECV_DEBUG_LOG();
	if(![self->device isPlaying]) return badCallOrderErr;
	return noErr;
}
ECV_VDIG_FUNCTION(ResetCompressSequence)
{
	ECV_DEBUG_LOG();
	return noErr;
}
ECV_VDIG_FUNCTION(CompressDone, UInt8 *queuedFrameCount, Ptr *theData, long *dataSize, UInt8 *similarity, TimeRecord *t)
{
	ECV_DEBUG_LOG();
	NSAutoreleasePool *const pool = [[NSAutoreleasePool alloc] init];
	ECVVideoStorage *const vs = [self->device videoStorage];
	ECVVideoFrame *const frame = [vs currentFrame];
	*queuedFrameCount = 1;
	if(frame) {
		Ptr const bufferBytes = [frame bufferBytes];
		CFDictionaryAddValue(self->frameByBuffer, bufferBytes, frame);
		*theData = bufferBytes;
		*dataSize = [[frame videoStorage] bufferSize];
		GetTimeBaseTime(self->timeBase, [self->device frameRate].timeScale, t);
	} else {
		*theData = NULL;
		*dataSize = 0;
	}
	*similarity = 0;
	[pool drain];
	return noErr;
}
ECV_VDIG_FUNCTION(ReleaseCompressBuffer, Ptr bufferAddr)
{
	ECV_DEBUG_LOG();
	NSAutoreleasePool *const pool = [[NSAutoreleasePool alloc] init];
	CFDictionaryRemoveValue(self->frameByBuffer, bufferAddr);
	[pool drain];
	return noErr;
}

ECV_VDIG_FUNCTION(GetImageDescription, ImageDescriptionHandle desc)
{
	ECV_DEBUG_LOG();
	NSAutoreleasePool *const pool = [[NSAutoreleasePool alloc] init];
	ECVVideoStorage *const videoStorage = [self->device videoStorage];
	if(!videoStorage) {
		[pool drain];
		return badCallOrderErr;
	}
	ECVIntegerSize const originalSize = [videoStorage originalSize];
	ECVIntegerSize const pixelSize = [videoStorage pixelSize];
	[pool drain];

	ImageDescriptionPtr const descPtr = *desc;
	SetHandleSize((Handle)desc, sizeof(ImageDescription));
	*descPtr = (ImageDescription){
		.idSize = sizeof(ImageDescription),
		.cType = [self->device pixelFormatType],
		.version = 2,
		.spatialQuality = codecLosslessQuality,
		.width = originalSize.width,
		.height = originalSize.height,
		.hRes = Long2Fix(72),
		.vRes = Long2Fix(72),
		.frameCount = 1,
		.depth = 24,
		.clutID = -1,
	};

	FieldInfoImageDescriptionExtension2 const fieldInfo = {kQTFieldsInterlaced, kQTFieldDetailUnknown};
	ECVOSStatus(ICMImageDescriptionSetProperty(desc, kQTPropertyClass_ImageDescription, kICMImageDescriptionPropertyID_FieldInfo, sizeof(FieldInfoImageDescriptionExtension2), &fieldInfo));

	CleanApertureImageDescriptionExtension const cleanAperture = {
		pixelSize.width, 1,
		pixelSize.height, 1,
		0, 1,
		0, 1,
	};
	ECVOSStatus(ICMImageDescriptionSetProperty(desc, kQTPropertyClass_ImageDescription, kICMImageDescriptionPropertyID_CleanAperture, sizeof(CleanApertureImageDescriptionExtension), &cleanAperture));

	PixelAspectRatioImageDescriptionExtension const pixelAspectRatio = {originalSize.height, 540};
	ECVOSStatus(ICMImageDescriptionSetProperty(desc, kQTPropertyClass_ImageDescription, kICMImageDescriptionPropertyID_PixelAspectRatio, sizeof(PixelAspectRatioImageDescriptionExtension), &pixelAspectRatio));

	NCLCColorInfoImageDescriptionExtension const colorInfo = {
		kVideoColorInfoImageDescriptionExtensionType,
		kQTPrimaries_SMPTE_C,
		kQTTransferFunction_ITU_R709_2,
		kQTMatrix_ITU_R_601_4
	};
	ECVOSStatus(ICMImageDescriptionSetProperty(desc, kQTPropertyClass_ImageDescription, kICMImageDescriptionPropertyID_NCLCColorInfo, sizeof(NCLCColorInfoImageDescriptionExtension), &colorInfo));

	ECVOSStatus(ICMImageDescriptionSetProperty(desc, kQTPropertyClass_ImageDescription, kICMImageDescriptionPropertyID_EncodedWidth, sizeof(pixelSize.width), &pixelSize.width));
	ECVOSStatus(ICMImageDescriptionSetProperty(desc, kQTPropertyClass_ImageDescription, kICMImageDescriptionPropertyID_EncodedHeight, sizeof(pixelSize.height), &pixelSize.height));

	return noErr;
}

ECV_VDIG_FUNCTION(GetVBlankRect, short inputStd, Rect *vBlankRect)
{
	ECV_DEBUG_LOG();
	if(vBlankRect) *vBlankRect = (Rect){};
	return noErr;
}
ECV_VDIG_FUNCTION(GetMaxSrcRect, short inputStd, Rect *maxSrcRect)
{
	ECV_DEBUG_LOG();
	NSAutoreleasePool *const pool = [[NSAutoreleasePool alloc] init];
	ECVIntegerSize const s = [self->device captureSize];
	[pool drain];
	if(!s.width || !s.height) return badCallOrderErr;
	if(maxSrcRect) *maxSrcRect = ECVNSRectToRect((NSRect){NSZeroPoint, ECVIntegerSizeToNSSize(s)});
	return noErr;
}
ECV_VDIG_FUNCTION(GetActiveSrcRect, short inputStd, Rect *activeSrcRect)
{
	ECV_DEBUG_LOG();
	return ADD_CALLCOMPONENT_BASENAME(GetMaxSrcRect)(self, inputStd, activeSrcRect);
}
ECV_VDIG_FUNCTION(GetDigitizerRect, Rect *digitizerRect)
{
	ECV_DEBUG_LOG();
	return ADD_CALLCOMPONENT_BASENAME(GetMaxSrcRect)(self, ntscIn, digitizerRect);
}

ECV_VDIG_FUNCTION(GetDataRate, long *milliSecPerFrame, Fixed *framesPerSecond, long *bytesPerSecond)
{
	ECV_DEBUG_LOG();
	*milliSecPerFrame = 0;
	NSTimeInterval frameRate = 1.0f / 60.0f;
	if(QTGetTimeInterval([self->device frameRate], &frameRate)) *framesPerSecond = X2Fix(frameRate);
	else *framesPerSecond = 0;
	NSAutoreleasePool *const pool = [[NSAutoreleasePool alloc] init];
	*bytesPerSecond = (1.0f / frameRate) * [[self->device videoStorage] bufferSize];
	[pool drain];
	return noErr;
}

ECV_VDIG_FUNCTION(GetPreferredTimeScale, TimeScale *preferred)
{
	ECV_DEBUG_LOG();
	*preferred = [self->device frameRate].timeScale;
	return noErr;
}
ECV_VDIG_FUNCTION(SetTimeBase, TimeBase t)
{
	ECV_DEBUG_LOG();
	self->timeBase = t;
	return noErr;
}

ECV_VDIG_FUNCTION(GetVideoDefaults, unsigned short *blackLevel, unsigned short *whiteLevel, unsigned short *brightness, unsigned short *hue, unsigned short *saturation, unsigned short *contrast, unsigned short *sharpness)
{
	ECV_DEBUG_LOG();
	*blackLevel = 0;
	*whiteLevel = 0;
	*brightness = round(0.5f * USHRT_MAX);
	*hue = round(0.5f * USHRT_MAX);
	*saturation = round(0.5f * USHRT_MAX);
	*contrast = round(0.5f * USHRT_MAX);
	*sharpness = 0;
	return noErr;
}
ECV_VDIG_PROPERTY_UNIMPLEMENTED(BlackLevelValue);
ECV_VDIG_PROPERTY_UNIMPLEMENTED(WhiteLevelValue);
ECV_VDIG_PROPERTY(Brightness, @selector(brightness), @selector(setBrightness:));
ECV_VDIG_PROPERTY(Hue, @selector(hue), @selector(setHue:));
ECV_VDIG_PROPERTY(Saturation, @selector(saturation), @selector(setSaturation:));
ECV_VDIG_PROPERTY(Contrast, @selector(contrast), @selector(setContrast:));
ECV_VDIG_PROPERTY_UNIMPLEMENTED(Sharpness);

ECV_VDIG_FUNCTION_UNIMPLEMENTED(CaptureStateChanging, UInt32 inStateFlags);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(GetPLLFilterType, short *pllType);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(SetPLLFilterType, short pllType);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(SetDigitizerRect, Rect *digitizerRect);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(GetPreferredImageDimensions, long *width, long *height);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(SetDataRate, long bytesPerSecond);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(GetUniqueIDs, UInt64 *outDeviceID, UInt64 * outInputID);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(SelectUniqueIDs, const UInt64 *inDeviceID, const UInt64 *inInputID);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(GetTimeCode, TimeRecord *atTime, void *timeCodeFormat, void *timeCodeTime);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(SetFrameRate, Fixed framesPerSecond);
