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

static Rect ECVNSRectToRect(NSRect r)
{
	return (Rect){NSMinX(r), NSMinY(r), NSMaxX(r), NSMaxY(r)};
}

pascal ComponentResult ECVOpen(ECVCStorage *storage, ComponentInstance self)
{
	if(CountComponentInstances((Component)self) > 1) return -1;
	if(!storage) {
		NSAutoreleasePool *const pool = [[NSAutoreleasePool alloc] init];
		NSDictionary *matchDict = nil;
		Class const class = [ECVCaptureDevice getMatchingDictionary:&matchDict forDeviceDictionary:[[ECVCaptureDevice deviceDictionaries] lastObject]];
		if(![class conformsToProtocol:@protocol(ECVComponentConfiguring)]) {
			[pool drain];
			return -1;
		}
		storage = calloc(1, sizeof(ECVCStorage));
		storage->device = [[class alloc] initWithService:IOServiceGetMatchingService(kIOMasterPortDefault, (CFDictionaryRef)[matchDict retain]) error:NULL];
		[storage->device setDeinterlacingMode:ECVLineDoubleLQ];
		storage->frameByBuffer = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, NULL, &kCFTypeDictionaryValueCallBacks);
		SetComponentInstanceStorage(self, (Handle)storage);
		[pool drain];
	}
	return noErr;
}
pascal ComponentResult ECVClose(ECVCStorage *storage, ComponentInstance self)
{
	if(!storage) return noErr;
	NSAutoreleasePool *const pool = [[NSAutoreleasePool alloc] init];
	[storage->device release];
	CFRelease(storage->frameByBuffer);
	free(storage);
	[pool release];
	return noErr;
}
pascal ComponentResult ECVVersion(ECVCStorage *storage)
{
	return vdigInterfaceRev << 16;
}

pascal VideoDigitizerError ECVGetDigitizerInfo(ECVCStorage *storage, DigitizerInfo *info)
{
	NSAutoreleasePool *const pool = [[NSAutoreleasePool alloc] init];
	ECVPixelSize const s = [storage->device captureSize];
	[pool release];

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
pascal VideoDigitizerError ECVGetCurrentFlags(ECVCStorage *storage, long *inputCurrentFlag, long *outputCurrentFlag)
{
	DigitizerInfo info;
	if(!ECVGetDigitizerInfo(storage, &info)) return -1;
	*inputCurrentFlag = info.inputCurrentFlags;
	*outputCurrentFlag = info.outputCurrentFlags;
	return noErr;
}

pascal VideoDigitizerError ECVGetNumberOfInputs(ECVCStorage *storage, short *inputs)
{
	*inputs = [storage->device numberOfInputs] - 1;
	return noErr;
}
pascal VideoDigitizerError ECVGetInputFormat(ECVCStorage *storage, short input, short *format)
{
	*format = [storage->device inputFormatForInputAtIndex:input];
	return noErr;
}
pascal VideoDigitizerError ECVGetInputName(ECVCStorage *storage, long videoInput, Str255 name)
{
	CFStringGetPascalString((CFStringRef)[storage->device localizedStringForInputAtIndex:videoInput], name, 256, kCFStringEncodingUTF8);
	return noErr;
}
pascal VideoDigitizerError ECVGetInput(ECVCStorage *storage, short *input)
{
	*input = [storage->device inputIndex];
	return noErr;
}
pascal VideoDigitizerError ECVSetInput(ECVCStorage *storage, short input)
{
	[storage->device setInputIndex:input];
	return noErr;
}
pascal VideoDigitizerError ECVSetInputStandard(ECVCStorage *storage, short inputStandard)
{
	[storage->device setInputStandard:inputStandard];
	return noErr;
}

pascal VideoDigitizerError ECVGetDeviceNameAndFlags(ECVCStorage *storage, Str255 outName, UInt32 *outNameFlags)
{
	*outNameFlags = kNilOptions;
	CFStringGetPascalString(CFSTR("Test Device"), outName, 256, kCFStringEncodingUTF8);
	// TODO: Enumerate the devices and register vdigs for each. Use vdDeviceFlagHideDevice for ourself. Not sure if this is actually necessary (?)
	return noErr;
}

pascal VideoDigitizerError ECVGetCompressionTime(ECVCStorage *storage, OSType compressionType, short depth, Rect *srcRect, CodecQ *spatialQuality, CodecQ *temporalQuality, unsigned long *compressTime)
{
	if(compressionType && k422YpCbCr8CodecType != compressionType) return noCodecErr; // TODO: Get the real type.
	*spatialQuality = codecLosslessQuality;
	*temporalQuality = 0;
	*compressTime = 0;
	return noErr;
}
pascal VideoDigitizerError ECVGetCompressionTypes(ECVCStorage *storage, VDCompressionListHandle h)
{
	SInt8 const handleState = HGetState((Handle)h);
	HUnlock((Handle)h);
	SetHandleSize((Handle)h, sizeof(VDCompressionList));
	HLock((Handle)h);

	CodecType const codec = k422YpCbCr8CodecType; // TODO: Get the real type.
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
pascal VideoDigitizerError ECVSetCompressionOnOff(ECVCStorage *storage, Boolean state)
{
	NSAutoreleasePool *const pool = [[NSAutoreleasePool alloc] init];
	[storage->device setPlaying:!!state];
	[pool release];
	return noErr;
}
pascal VideoDigitizerError ECVSetCompression(ECVCStorage *storage, OSType compressType, short depth, Rect *bounds, CodecQ spatialQuality, CodecQ temporalQuality, long keyFrameRate)
{
	if(compressType && k422YpCbCr8CodecType != compressType) return noCodecErr; // TODO: Get the real type.
	// TODO: Most of these settings don't apply to us...
	return noErr;
}
pascal VideoDigitizerError ECVCompressOneFrameAsync(ECVCStorage *storage)
{
	if(![storage->device isPlaying]) return badCallOrderErr;
	return noErr;
}
pascal VideoDigitizerError ECVResetCompressSequence(ECVCStorage *storage)
{
	return noErr;
}
pascal VideoDigitizerError ECVCompressDone(ECVCStorage *storage, UInt8 *queuedFrameCount, Ptr *theData, long *dataSize, UInt8 *similarity, TimeRecord *t)
{
	NSAutoreleasePool *const pool = [[NSAutoreleasePool alloc] init];
	ECVVideoStorage *const vs = [storage->device videoStorage];
	ECVVideoFrame *const frame = [vs oldestFrame];
	*queuedFrameCount = (UInt8)[vs numberOfCompletedFrames];
	if(frame) {
		Ptr const bufferBytes = [frame bufferBytes];
		CFDictionaryAddValue(storage->frameByBuffer, bufferBytes, frame);
		*theData = bufferBytes;
		*dataSize = [[frame videoStorage] bufferSize];
		GetTimeBaseTime(storage->timeBase, [storage->device frameRate].timeScale, t);
	} else {
		*theData = NULL;
		*dataSize = 0;
	}
	*similarity = 0;
	[pool release];
	return noErr;
}
pascal VideoDigitizerError ECVReleaseCompressBuffer(ECVCStorage *storage, Ptr bufferAddr)
{
	NSAutoreleasePool *const pool = [[NSAutoreleasePool alloc] init];
	ECVVideoFrame *const frame = (ECVVideoFrame *)CFDictionaryGetValue(storage->frameByBuffer, bufferAddr);
	NSCAssert(frame, @"Invalid buffer address.");
	[frame removeFromStorage];
	CFDictionaryRemoveValue(storage->frameByBuffer, bufferAddr);
	[pool release];
	return noErr;
}

pascal VideoDigitizerError ECVGetImageDescription(ECVCStorage *storage, ImageDescriptionHandle desc)
{
	ImageDescriptionPtr const descPtr = *desc;
	SetHandleSize((Handle)desc, sizeof(ImageDescription));
	*descPtr = (ImageDescription){
		.idSize = sizeof(ImageDescription),
		.cType = k422YpCbCr8CodecType, // TODO: Get the real type.
		.version = 2,
		.spatialQuality = codecLosslessQuality,
		.hRes = Long2Fix(72),
		.vRes = Long2Fix(72),
		.frameCount = 1,
		.depth = 24,
		.clutID = -1,
	};

	FieldInfoImageDescriptionExtension2 const fieldInfo = {kQTFieldsInterlaced, kQTFieldDetailUnknown};
	ECVOSStatus(ICMImageDescriptionSetProperty(desc, kQTPropertyClass_ImageDescription, kICMImageDescriptionPropertyID_FieldInfo, sizeof(FieldInfoImageDescriptionExtension2), &fieldInfo));

	CleanApertureImageDescriptionExtension const cleanAperture = {
		720, 1, // TODO: Get the real size.
		480, 1,
		0, 1,
		0, 1,
	};
	ECVOSStatus(ICMImageDescriptionSetProperty(desc, kQTPropertyClass_ImageDescription, kICMImageDescriptionPropertyID_CleanAperture, sizeof(CleanApertureImageDescriptionExtension), &cleanAperture));

	PixelAspectRatioImageDescriptionExtension const pixelAspectRatio = {1, 1};
	ECVOSStatus(ICMImageDescriptionSetProperty(desc, kQTPropertyClass_ImageDescription, kICMImageDescriptionPropertyID_PixelAspectRatio, sizeof(PixelAspectRatioImageDescriptionExtension), &pixelAspectRatio));

	NCLCColorInfoImageDescriptionExtension const colorInfo = {
		kVideoColorInfoImageDescriptionExtensionType,
		kQTPrimaries_SMPTE_C,
		kQTTransferFunction_ITU_R709_2,
		kQTMatrix_ITU_R_601_4
	};
	ECVOSStatus(ICMImageDescriptionSetProperty(desc, kQTPropertyClass_ImageDescription, kICMImageDescriptionPropertyID_NCLCColorInfo, sizeof(NCLCColorInfoImageDescriptionExtension), &colorInfo));

	SInt32 const width = 720; // TODO: Get the real size.
	SInt32 const height = 240;
	ECVOSStatus(ICMImageDescriptionSetProperty(desc, kQTPropertyClass_ImageDescription, kICMImageDescriptionPropertyID_EncodedWidth, sizeof(width), &width));
	ECVOSStatus(ICMImageDescriptionSetProperty(desc, kQTPropertyClass_ImageDescription, kICMImageDescriptionPropertyID_EncodedHeight, sizeof(height), &height));

	return noErr;
}

#define DEFAULT_MAX USHRT_MAX
pascal VideoDigitizerError ECVGetVideoDefaults(ECVCStorage *storage, unsigned short *blackLevel, unsigned short *whiteLevel, unsigned short *brightness, unsigned short *hue, unsigned short *saturation, unsigned short *contrast, unsigned short *sharpness)
{
	*blackLevel = 0;
	*whiteLevel = 0;
	*brightness = round(0.5f * DEFAULT_MAX);
	*hue = round(0.5f * DEFAULT_MAX);
	*saturation = round(0.5f * DEFAULT_MAX);
	*contrast = round(0.5f * DEFAULT_MAX);
	*sharpness = 0;
	return noErr;
}
pascal VideoDigitizerError ECVGetBlackLevelValue(ECVCStorage *storage, unsigned short *v)
{
	return digiUnimpErr;
}
pascal VideoDigitizerError ECVSetBlackLevelValue(ECVCStorage *storage, unsigned short *v)
{
	return digiUnimpErr;
}
pascal VideoDigitizerError ECVGetWhiteLevelValue(ECVCStorage *storage, unsigned short *v)
{
	return digiUnimpErr;
}
pascal VideoDigitizerError ECVSetWhiteLevelValue(ECVCStorage *storage, unsigned short *v)
{
	return digiUnimpErr;
}
pascal VideoDigitizerError ECVGetBrightness(ECVCStorage *storage, unsigned short *v)
{
	if(![storage->device respondsToSelector:@selector(brightness)]) return digiUnimpErr;
	*v = [storage->device brightness] * DEFAULT_MAX;
	return noErr;
}
pascal VideoDigitizerError ECVSetBrightness(ECVCStorage *storage, unsigned short *v)
{
	if(![storage->device respondsToSelector:@selector(setBrightness:)]) return digiUnimpErr;
	[storage->device setBrightness:(CGFloat)*v / DEFAULT_MAX];
	return noErr;
}
pascal VideoDigitizerError ECVGetHue(ECVCStorage *storage, unsigned short *v)
{
	if(![storage->device respondsToSelector:@selector(hue)]) return digiUnimpErr;
	*v = [storage->device hue] * DEFAULT_MAX;
	return noErr;
}
pascal VideoDigitizerError ECVSetHue(ECVCStorage *storage, unsigned short *v)
{
	if(![storage->device respondsToSelector:@selector(setHue:)]) return digiUnimpErr;
	[storage->device setHue:(CGFloat)*v / DEFAULT_MAX];
	return noErr;
}
pascal VideoDigitizerError ECVGetSaturation(ECVCStorage *storage, unsigned short *v)
{
	if(![storage->device respondsToSelector:@selector(saturation)]) return digiUnimpErr;
	*v = [storage->device saturation] * DEFAULT_MAX;
	return noErr;
}
pascal VideoDigitizerError ECVSetSaturation(ECVCStorage *storage, unsigned short *v)
{
	if(![storage->device respondsToSelector:@selector(setSaturation:)]) return digiUnimpErr;
	[storage->device setSaturation:(CGFloat)*v / DEFAULT_MAX];
	return noErr;
}
pascal VideoDigitizerError ECVGetContrast(ECVCStorage *storage, unsigned short *v)
{
	if(![storage->device respondsToSelector:@selector(contrast)]) return digiUnimpErr;
	*v = [storage->device contrast] * DEFAULT_MAX;
	return noErr;
}
pascal VideoDigitizerError ECVSetContrast(ECVCStorage *storage, unsigned short *v)
{
	if(![storage->device respondsToSelector:@selector(setContrast:)]) return digiUnimpErr;
	[storage->device setContrast:(CGFloat)*v / DEFAULT_MAX];
	return noErr;
}
pascal VideoDigitizerError ECVGetSharpness(ECVCStorage *storage, unsigned short *sharpness)
{
	return digiUnimpErr;
}
pascal VideoDigitizerError ECVSetSharpness(ECVCStorage *storage, unsigned short *sharpness)
{
	return digiUnimpErr;
}



pascal VideoDigitizerError ECVCaptureStateChanging(ECVCStorage *storage, UInt32 inStateFlags)
{
	return noErr;
}
pascal VideoDigitizerError ECVGetPLLFilterType(ECVCStorage *storage, short *pllType)
{
	*pllType = 0;
	return noErr;
}
pascal VideoDigitizerError ECVSetPLLFilterType(ECVCStorage *storage, short pllType)
{
	return digiUnimpErr;
}




pascal VideoDigitizerError ECVGetVBlankRect(ECVCStorage *storage, short inputStd, Rect *vBlankRect)
{
	if(vBlankRect) *vBlankRect = (Rect){};
	return noErr;
}
pascal VideoDigitizerError ECVGetMaxSrcRect(ECVCStorage *storage, short inputStd, Rect *maxSrcRect)
{
	if(!storage->device) return badCallOrderErr;
	NSAutoreleasePool *const pool = [[NSAutoreleasePool alloc] init];
	ECVPixelSize const s = [storage->device captureSize];
	[pool release];
	if(!s.width || !s.height) return badCallOrderErr;
	if(maxSrcRect) *maxSrcRect = ECVNSRectToRect((NSRect){NSZeroPoint, ECVPixelSizeToNSSize(s)});
	return noErr;
}
pascal VideoDigitizerError ECVGetActiveSrcRect(ECVCStorage *storage, short inputStd, Rect *activeSrcRect)
{
	return ECVGetMaxSrcRect(storage, inputStd, activeSrcRect);
}
pascal VideoDigitizerError ECVGetDigitizerRect(ECVCStorage *storage, Rect *digitizerRect)
{
	return ECVGetMaxSrcRect(storage, ntscIn, digitizerRect);
}
pascal VideoDigitizerError ECVSetDigitizerRect(ECVCStorage *storage, Rect *digitizerRect)
{
	return digiUnimpErr;
}
pascal VideoDigitizerError ECVGetPreferredImageDimensions(ECVCStorage *storage, long *width, long *height)
{
	return digiUnimpErr;
}

pascal VideoDigitizerError ECVGetDataRate(ECVCStorage *storage, long *milliSecPerFrame, Fixed *framesPerSecond, long *bytesPerSecond)
{
	*milliSecPerFrame = 0;
	NSTimeInterval frameRate = 1.0f / 60.0f;
	if(QTGetTimeInterval([storage->device frameRate], &frameRate)) *framesPerSecond = X2Fix(frameRate);
	else *framesPerSecond = 0;
	NSAutoreleasePool *const pool = [[NSAutoreleasePool alloc] init];
	*bytesPerSecond = (1.0f / frameRate) * [[storage->device videoStorage] bufferSize];
	[pool release];
	return noErr;
}
pascal VideoDigitizerError ECVSetDataRate(ECVCStorage *storage, long bytesPerSecond)
{
	return digiUnimpErr;
}

pascal VideoDigitizerError ECVGetUniqueIDs(ECVCStorage *storage, UInt64 *outDeviceID, UInt64 * outInputID)
{
	return digiUnimpErr;
}
pascal VideoDigitizerError ECVSelectUniqueIDs(ECVCStorage *storage, const UInt64 *inDeviceID, const UInt64 *inInputID)
{
	return digiUnimpErr;
}



pascal VideoDigitizerError ECVGetPreferredTimeScale(ECVCStorage *storage, TimeScale *preferred)
{
	*preferred = [storage->device frameRate].timeScale;
	return noErr;
}
pascal VideoDigitizerError ECVSetTimeBase(ECVCStorage *storage, TimeBase t)
{
	storage->timeBase = t;
	return noErr;
}
pascal VideoDigitizerError ECVSetFrameRate(ECVCStorage *storage, Fixed framesPerSecond)
{
	return digiUnimpErr;
}



pascal VideoDigitizerError ECVGetTimeCode(ECVCStorage *storage, TimeRecord *atTime, void *timeCodeFormat, void *timeCodeTime)
{
	return digiUnimpErr;
}
