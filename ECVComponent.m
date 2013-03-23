/* Copyright (c) 2010-2011, Ben Trask
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
#import <objc/objc-runtime.h>

// Models
#import "ECVVideoFormat.h"
#import "ECVVideoStorage.h"
#import "ECVDeinterlacingMode.h"
#import "ECVVideoFrame.h"

// Video Devices
#import "ECVCaptureDevice.h"

// Other Sources
#import "ECVDebug.h"
#import "ECVICM.h"

typedef struct {
	BOOL playing;
	ECVCaptureDevice *device;
	ICMCompressionSessionRef compressionSession;
	ICMEncodedFrameRef encodedFrame;
	BOOL hasNewFrame;
	NSLock *lock;
	NSMutableArray *inputCombinations;
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
	#define ECV_objc_msgSend_CGFloat objc_msgSend_fpret
#else
	#define ECV_objc_msgSend_CGFloat objc_msgSend
#endif

#if defined(ECV_DEBUG)
#define ECV_UNIMPLEMENTED_LOG() ECVLog(ECVNotice, @"Unimplemented %s:%lu", __PRETTY_FUNCTION__, (unsigned long)__LINE__)
#else
#define ECV_UNIMPLEMENTED_LOG()
#endif

#define ECV_CALLCOMPONENT_FUNCTION(name, args...) pascal ComponentResult ADD_CALLCOMPONENT_BASENAME(name)(VD_GLOBALS() self, ##args)
#define ECV_VDIG_FUNCTION(name, args...) pascal VideoDigitizerError ADD_CALLCOMPONENT_BASENAME(name)(VD_GLOBALS() self, ##args)
#define ECV_VDIG_FUNCTION_UNIMPLEMENTED(name, args...) ECV_VDIG_FUNCTION(name, ##args) { ECV_UNIMPLEMENTED_LOG(); return digiUnimpErr; }
#define ECV_VDIG_PROPERTY_UNIMPLEMENTED(prop) \
	ECV_VDIG_FUNCTION_UNIMPLEMENTED(Get ## prop, unsigned short *v)\
	ECV_VDIG_FUNCTION_UNIMPLEMENTED(Set ## prop, unsigned short *v)
#define ECV_VDIG_PROPERTY(prop, getterSel, setterSel) \
	ECV_VDIG_FUNCTION(Get ## prop, unsigned short *v)\
	{\
		ECV_DEBUG_LOG();\
		if(![self->device respondsToSelector:getterSel]) return digiUnimpErr;\
		*v = ((CGFloat (*)(id, SEL))ECV_objc_msgSend_CGFloat)(self->device, getterSel) * USHRT_MAX;\
		return noErr;\
	}\
	ECV_VDIG_FUNCTION(Set ## prop, unsigned short *v)\
	{\
		ECV_DEBUG_LOG();\
		if(![self->device respondsToSelector:setterSel]) return digiUnimpErr;\
		((void (*)(id, SEL, CGFloat))objc_msgSend)(self->device, setterSel, (CGFloat)*v / USHRT_MAX);\
		return noErr;\
	}

static NSString *const ECVVideoSourceObject = @"ECVVideoSourceObjectKey";
static NSString *const ECVVideoFormatObject = @"ECVVideoFormatObjectKey";

static Rect ECVNSRectToRect(NSRect r)
{
	return (Rect){NSMinX(r), NSMinY(r), NSMaxX(r), NSMaxY(r)};
}
static OSType ECVOutputPixelFormat(ECVCStorage const *const self)
{
	// Processing doesn't like '2vuy'. I don't know why.
	// The transformation is pretty fast because all it does is swap bytes I think.
	return kComponentVideoCodecType;//[self->device pixelFormat];//
}

static OSStatus ECVICMEncodedFrameOutputCallback(ECVCStorage *const self, ICMCompressionSessionRef const session, OSStatus const error, ICMEncodedFrameRef const frame, void const *const reserved)
{
	[self->lock lock];
	if(frame) {
		ICMEncodedFrameRelease(self->encodedFrame);
		self->encodedFrame = ICMEncodedFrameRetain(frame);
	}
	self->hasNewFrame = YES;
	[self->lock unlock];
	return noErr;
}
static ICMCompressionSessionRef ECVCompressionSessionCreate(ECVCStorage *const self)
{
	ECVVideoStorage *const vs = [self->device videoStorage];
	ICMCompressionSessionOptionsRef opts = NULL;
	ECVOSStatus(ICMCompressionSessionOptionsCreate(kCFAllocatorDefault, &opts));
	ECVICMCSOSetProperty(opts, DurationsNeeded, (Boolean)true);
	ECVICMCSOSetProperty(opts, AllowAsyncCompletion, (Boolean)true);
	ECVVideoFormat *const format = [vs videoFormat];
	QTTime const frameRate = [format frameRate];
	NSTimeInterval frameRateInterval = 0.0;
	if(QTGetTimeInterval(frameRate, &frameRateInterval)) ECVICMCSOSetProperty(opts, ExpectedFrameRate, X2Fix(1.0 / frameRateInterval));
	ECVICMCSOSetProperty(opts, CPUTimeBudget, (UInt32)QTMakeTimeScaled(frameRate, ECVMicrosecondsPerSecond).timeValue);
//	ECVICMCSOSetProperty(opts, ScalingMode, (OSType)kICMScalingMode_StretchCleanAperture);
	ECVICMCSOSetProperty(opts, Quality, (CodecQ)codecMaxQuality);
	ECVICMCSOSetProperty(opts, Depth, [vs pixelFormat]);

	ECVIntegerSize const s = [format frameSize];
	ICMEncodedFrameOutputRecord cb = {
		.encodedFrameOutputCallback = (ICMEncodedFrameOutputCallback)ECVICMEncodedFrameOutputCallback,
		.encodedFrameOutputRefCon = self,
	};
	ICMCompressionSessionRef result = NULL;
	ECVOSStatus(ICMCompressionSessionCreate(kCFAllocatorDefault, s.width, s.height, ECVOutputPixelFormat(self), [format frameRate].timeScale, opts, (CFDictionaryRef)[NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithUnsignedInteger:s.width], kCVPixelBufferWidthKey,
		[NSNumber numberWithUnsignedInteger:s.height], kCVPixelBufferHeightKey,
		[NSNumber numberWithUnsignedInt:[vs pixelFormat]], kCVPixelBufferPixelFormatTypeKey,
//		[NSDictionary dictionaryWithObjectsAndKeys:
//			[self cleanAperatureDictionary], kCVImageBufferCleanApertureKey,
//			nil], kCVBufferNonPropagatedAttachmentsKey,
		nil], &cb, &result));
	ICMCompressionSessionOptionsRelease(opts);
	return result;
}

ECV_CALLCOMPONENT_FUNCTION(Open, ComponentInstance instance)
{
	ECV_DEBUG_LOG();
	if(CountComponentInstances((Component)self) > 1) return -1;
	if(!self) {
		NSAutoreleasePool *const pool = [[NSAutoreleasePool alloc] init];
		self = calloc(1, sizeof(ECVCStorage));
		for(Class const class in [ECVCaptureDevice deviceClasses]) {
			io_service_t const service = IOServiceGetMatchingService(kIOMasterPortDefault, (CFDictionaryRef)[[class matchingDictionary] retain]);
			if(!service) continue;
			self->device = [[class alloc] initWithService:service];
			if(!self->device) continue;
			break;
		}
		if(!self->device) {
			ECVLog(ECVError, @"Unable to start any devices");
			free(self);
			[pool drain];
			return internalComponentErr;
		}
		[self->device setDeinterlacingMode:[ECVDropDeinterlacingMode class]];
		self->lock = [[NSLock alloc] init];
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
	ICMCompressionSessionRelease(self->compressionSession);
	ICMEncodedFrameRelease(self->encodedFrame);
	[self->lock release];
	[self->inputCombinations release];
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
	ECVIntegerSize const s = [[self->device videoFormat] frameSize];
	[pool drain];

	*info = (DigitizerInfo){};
	info->vdigType = vdTypeBasic;
	info->inputCapabilityFlags = digiInDoesNTSC | digiInDoesPAL | digiInDoesSECAM | digiInDoesColor | digiInDoesComposite | digiInDoesSVideo;
	info->outputCapabilityFlags = digiOutDoes32 | digiOutDoesCompress | digiOutDoesCompressOnly | digiOutDoesNotNeedCopyOfCompressData;
	info->inputCurrentFlags = info->inputCapabilityFlags;
	info->outputCurrentFlags = info->outputCapabilityFlags;

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
	if(noErr != ADD_CALLCOMPONENT_BASENAME(GetDigitizerInfo)(self, &info)) return -1;
	*inputCurrentFlag = info.inputCurrentFlags;
	*outputCurrentFlag = info.outputCurrentFlags;
	return noErr;
}

ECV_VDIG_FUNCTION(GetNumberOfInputs, short *inputs)
{
	ECV_DEBUG_LOG();
	NSAutoreleasePool *const pool = [[NSAutoreleasePool alloc] init];
	[self->inputCombinations release];
	self->inputCombinations = [[NSMutableArray alloc] init];
	for(id const source in [self->device supportedVideoSources]) {
		for(id const format in [self->device supportedVideoFormats]) {
			[self->inputCombinations addObject:[NSDictionary dictionaryWithObjectsAndKeys:
				source, ECVVideoSourceObject,
				format, ECVVideoFormatObject,
				nil]];
		}
	}
	*inputs = MIN(SHRT_MAX, [self->inputCombinations count] - 1);
	[pool drain];
	return noErr;
}
ECV_VDIG_FUNCTION(GetInputFormat, short input, short *format)
{
	ECV_DEBUG_LOG();
	*format = compositeIn;
	return noErr;
}
ECV_VDIG_FUNCTION(GetInputName, long videoInput, Str255 name)
{
	ECV_DEBUG_LOG();
	NSAutoreleasePool *const pool = [[NSAutoreleasePool alloc] init];
	NSDictionary *const inputCombination = [self->inputCombinations objectAtIndex:videoInput];
	NSString *const sourceLabel = [[inputCombination objectForKey:ECVVideoSourceObject] localizedName];
	NSString *const formatLabel = [[inputCombination objectForKey:ECVVideoFormatObject] localizedName];
	CFStringGetPascalString((CFStringRef)[NSString stringWithFormat:@"%@ - %@", sourceLabel, formatLabel], name, 256, kCFStringEncodingUTF8);
	[pool drain];
	return noErr;
}
ECV_VDIG_FUNCTION(GetInput, short *input)
{
	ECV_DEBUG_LOG();
	NSAutoreleasePool *const pool = [[NSAutoreleasePool alloc] init];
	NSDictionary *const inputCombination = [NSDictionary dictionaryWithObjectsAndKeys:
		[self->device videoSource], ECVVideoSourceObject,
		[self->device videoFormat], ECVVideoFormatObject,
		nil];
	NSUInteger i = [self->inputCombinations indexOfObject:inputCombination];
	if(NSNotFound == i) i = 0;
	*input = MIN(SHRT_MAX, i);
	[pool drain];
	return noErr;
}
ECV_VDIG_FUNCTION(SetInput, short input)
{
	ECV_DEBUG_LOG();
	NSAutoreleasePool *const pool = [[NSAutoreleasePool alloc] init];
	NSDictionary *const inputCombination = [self->inputCombinations objectAtIndex:input];
	[self->device setVideoSource:[inputCombination objectForKey:ECVVideoSourceObject]];
	[self->device setVideoFormat:[inputCombination objectForKey:ECVVideoFormatObject]];
	[pool drain];
	return noErr;
}
ECV_VDIG_FUNCTION(SetInputStandard, short inputStandard)
{
	ECV_DEBUG_LOG();
	return noErr;
}

ECV_VDIG_FUNCTION(GetDeviceNameAndFlags, Str255 outName, UInt32 *outNameFlags)
{
	ECV_DEBUG_LOG();
	*outNameFlags = kNilOptions;
	CFStringGetPascalString((CFStringRef)@"ECVComponent", outName, 256, kCFStringEncodingUTF8);
	// TODO: Enumerate the devices and register vdigs for each. Use vdDeviceFlagHideDevice for ourself. Not sure if this is actually necessary (?)
	return noErr;
}

ECV_VDIG_FUNCTION(GetCompressionTime, OSType compressionType, short depth, Rect *srcRect, CodecQ *spatialQuality, CodecQ *temporalQuality, unsigned long *compressTime)
{
	ECV_DEBUG_LOG();
	if(compressionType && ECVOutputPixelFormat(self) != compressionType) return noCodecErr;
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

	CodecType const codec = ECVOutputPixelFormat(self);
	CodecInfo info;
	ECVOSErr(GetCodecInfo(&info, codec, 0));
	VDCompressionListPtr const p = *h;
	p[0] = (VDCompressionList){
		.codec = 0,
		.cType = codec,
		.formatFlags = info.formatFlags,
		.compressFlags = info.compressFlags,
	};
	CFStringGetPascalString((CFStringRef)@"Native Output", p[0].typeName, 64, kCFStringEncodingUTF8);
	CFStringGetPascalString((CFStringRef)@"Test Name", p[0].name, 64, kCFStringEncodingUTF8);

	HSetState((Handle)h, handleState);
	return noErr;
}
ECV_VDIG_FUNCTION(SetCompressionOnOff, Boolean state)
{
	ECV_DEBUG_LOG();
	NSAutoreleasePool *const pool = [[NSAutoreleasePool alloc] init];
	if(state) [self->device play];
	else [self->device stop];
	self->playing = !!state;
	ICMCompressionSessionRelease(self->compressionSession);
	self->compressionSession = state ? ECVCompressionSessionCreate(self) : NULL;
	[pool drain];
	return noErr;
}
ECV_VDIG_FUNCTION(SetCompression, OSType compressType, short depth, Rect *bounds, CodecQ spatialQuality, CodecQ temporalQuality, long keyFrameRate)
{
	ECV_DEBUG_LOG();
	if(compressType && ECVOutputPixelFormat(self) != compressType) return noCodecErr;
	// TODO: Most of these settings don't apply to us...
	return noErr;
}
ECV_VDIG_FUNCTION(ResetCompressSequence)
{
	ECV_DEBUG_LOG();
	return noErr;
}
ECV_VDIG_FUNCTION(CompressOneFrameAsync)
{
//	ECV_DEBUG_LOG();
	NSAutoreleasePool *const pool = [[NSAutoreleasePool alloc] init];
	if(!self->playing) {
		[pool drain];
		return badCallOrderErr;
	}
	[pool drain];
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, kNilOptions), ^{
		ECVVideoStorage *const vs = [self->device videoStorage];
		ECVVideoFrame *const frame = [vs currentFrame];
		if(!frame) ECVCompressOneFrameAsync(self);
		else if([frame lockIfHasBytes]) {
			CVPixelBufferPoolRef const p = ICMCompressionSessionGetPixelBufferPool(self->compressionSession);
			CVPixelBufferRef pixelBuffer = NULL;
			ECVCVReturn(CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, p, &pixelBuffer));
			ECVCVPixelBuffer *const buffer = [[[ECVCVPixelBuffer alloc] initWithPixelBuffer:pixelBuffer] autorelease];
			[buffer lock];
			[buffer drawPixelBuffer:frame];
			[buffer unlock];
			[frame unlock];
			ECVOSStatus(ICMCompressionSessionEncodeFrame(self->compressionSession, pixelBuffer, 0, [[vs videoFormat] frameRate].timeValue, kICMValidTime_DisplayDurationIsValid, NULL, NULL, NULL));
			if(pixelBuffer) CVPixelBufferRelease(pixelBuffer);
		} else if(frame) {
			ECVICMEncodedFrameOutputCallback(self, self->compressionSession, noErr, NULL, NULL);
		}
	});
	return noErr;
}
ECV_VDIG_FUNCTION(CompressDone, UInt8 *queuedFrameCount, Ptr *theData, long *dataSize, UInt8 *similarity, TimeRecord *t)
{
//	ECV_DEBUG_LOG();
	[self->lock lock];
	if(self->hasNewFrame && self->encodedFrame) {
		*theData = (Ptr)ICMEncodedFrameGetDataPtr(self->encodedFrame);
		*dataSize = ICMEncodedFrameGetBufferSize(self->encodedFrame);
		self->hasNewFrame = NO;

		*queuedFrameCount = 1;
		GetTimeBaseTime(self->timeBase, [[self->device videoFormat] frameRate].timeScale, t);
	} else {
		*theData = NULL;
		*dataSize = 0;
		*queuedFrameCount = 0;
	}
	[self->lock unlock];
	*similarity = 0;
	return noErr;
}
ECV_VDIG_FUNCTION(ReleaseCompressBuffer, Ptr bufferAddr)
{
//	ECV_DEBUG_LOG();
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
	ECVIntegerSize const frameSize = [[videoStorage videoFormat] frameSize];
	size_t const bytesPerRow = [videoStorage bytesPerRow];
	[pool drain];

	ImageDescriptionPtr const descPtr = *desc;
	SetHandleSize((Handle)desc, sizeof(ImageDescription));
	*descPtr = (ImageDescription){
		.idSize = sizeof(ImageDescription),
		.cType = ECVOutputPixelFormat(self),
		.version = 2,
		.spatialQuality = codecLosslessQuality,
		.width = frameSize.width,
		.height = frameSize.height,
		.hRes = Long2Fix(72),
		.vRes = Long2Fix(72),
		.frameCount = 1,
		.depth = 24,
		.clutID = -1,
	};

	FieldInfoImageDescriptionExtension2 const fieldInfo = {kQTFieldsProgressiveScan, kQTFieldDetailUnknown};
	ECVICMIDSetProperty(desc, FieldInfo, fieldInfo);

	CleanApertureImageDescriptionExtension const cleanAperture = {
		frameSize.width, 1,
		frameSize.height, 1,
		0, 1,
		0, 1,
	};
	ECVICMIDSetProperty(desc, CleanAperture, cleanAperture);

	PixelAspectRatioImageDescriptionExtension const pixelAspectRatio = {frameSize.height, frameSize.height}; // FIXME: Pretty sure this isn't quite right.
	ECVICMIDSetProperty(desc, PixelAspectRatio, pixelAspectRatio);

	NCLCColorInfoImageDescriptionExtension const colorInfo = {
		kVideoColorInfoImageDescriptionExtensionType,
		kQTPrimaries_SMPTE_C,
		kQTTransferFunction_ITU_R709_2,
		kQTMatrix_ITU_R_601_4
	};
	ECVICMIDSetProperty(desc, NCLCColorInfo, colorInfo);

	ECVICMIDSetProperty(desc, EncodedWidth, (SInt32)frameSize.width);
	ECVICMIDSetProperty(desc, EncodedHeight, (SInt32)frameSize.height);

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
	ECVIntegerSize const s = [[self->device videoFormat] frameSize];
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
ECV_VDIG_FUNCTION(SetDigitizerRect, Rect *digitizerRect)
{
	// According to my experiments with Macam, this function seems necessary, although it doesn't make any difference here.
	ECV_DEBUG_LOG();
	return noErr;
}

ECV_VDIG_FUNCTION(GetDataRate, long *milliSecPerFrame, Fixed *framesPerSecond, long *bytesPerSecond)
{
	ECV_DEBUG_LOG();
	*milliSecPerFrame = 0;
	NSTimeInterval frameRate = 1.0f / 60.0f;
	if(QTGetTimeInterval([[self->device videoFormat] frameRate], &frameRate)) *framesPerSecond = X2Fix(frameRate);
	else *framesPerSecond = 0;
	NSAutoreleasePool *const pool = [[NSAutoreleasePool alloc] init];
	*bytesPerSecond = (1.0f / frameRate) * [[self->device videoStorage] bufferSize];
	[pool drain];
	return noErr;
}

ECV_VDIG_FUNCTION(GetPreferredTimeScale, TimeScale *preferred)
{
	ECV_DEBUG_LOG();
	*preferred = [[self->device videoFormat] frameRate].timeScale;
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
//ECV_VDIG_FUNCTION_UNIMPLEMENTED(SetDigitizerRect, Rect *digitizerRect);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(GetPreferredImageDimensions, long *width, long *height);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(SetDataRate, long bytesPerSecond);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(GetUniqueIDs, UInt64 *outDeviceID, UInt64 * outInputID);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(SelectUniqueIDs, const UInt64 *inDeviceID, const UInt64 *inInputID);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(GetTimeCode, TimeRecord *atTime, void *timeCodeFormat, void *timeCodeTime);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(SetFrameRate, Fixed framesPerSecond);

ECV_VDIG_FUNCTION_UNIMPLEMENTED(GetMaskPixMap, PixMapHandle maskPixMap);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(GetPlayThruDestination, PixMapHandle *dest, Rect *destRect, MatrixRecord *m, RgnHandle *mask);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(UseThisCLUT, CTabHandle colorTableHandle);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(SetInputGammaValue, Fixed channel1, Fixed channel2, Fixed channel3);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(GetInputGammaValue, Fixed *channel1, Fixed *channel2, Fixed *channel3);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(GrabOneFrame);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(GetMaxAuxBuffer, PixMapHandle *pm, Rect *r);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(SetKeyColor, long index);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(GetKeyColor, long *index);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(AddKeyColor, long *index);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(GetNextKeyColor, long index);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(SetKeyColorRange, RGBColor *minRGB, RGBColor *maxRGB);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(GetKeyColorRange, RGBColor *minRGB, RGBColor *maxRGB);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(SetDigitizerUserInterrupt, long flags, VdigIntUPP userInterruptProc, long refcon);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(SetInputColorSpaceMode, short colorSpaceMode);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(GetInputColorSpaceMode, short *colorSpaceMode);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(SetClipState, short clipEnable);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(GetClipState, short *clipEnable);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(SetClipRgn, RgnHandle clipRegion);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(ClearClipRgn, RgnHandle clipRegion);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(GetCLUTInUse, CTabHandle *colorTableHandle);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(GetMaskandValue, unsigned short blendLevel, long *mask, long *value);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(SetMasterBlendLevel, unsigned short *blendLevel);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(SetPlayThruDestination, PixMapHandle dest, RectPtr destRect, MatrixRecordPtr m, RgnHandle mask);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(SetPlayThruOnOff, short state);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(SetFieldPreference, short fieldFlag);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(GetFieldPreference, short *fieldFlag);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(PreflightDestination, Rect *digitizerRect, PixMap **dest, RectPtr destRect, MatrixRecordPtr m);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(PreflightGlobalRect, GrafPtr theWindow, Rect *globalRect);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(SetPlayThruGlobalRect, GrafPtr theWindow, Rect *globalRect);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(SetInputGammaRecord, VDGamRecPtr inputGammaPtr);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(GetInputGammaRecord, VDGamRecPtr *inputGammaPtr);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(SetupBuffers, VdigBufferRecListHandle bufferList);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(GrabOneFrameAsync, short buffer);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(Done, short buffer);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(GetSoundInputDriver, Str255 soundDriverName);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(GetDMADepths, long *depthArray, long *preferredDepth);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(ReleaseAsyncBuffers);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(UseSafeBuffers, Boolean useSafeBuffers);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(GetSoundInputSource, long videoInput, long *soundInput);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(SetPreferredPacketSize, long preferredPacketSizeInBytes);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(SetPreferredImageDimensions, long width, long height);
ECV_VDIG_FUNCTION_UNIMPLEMENTED(SetDestinationPort, CGrafPtr destPort);
