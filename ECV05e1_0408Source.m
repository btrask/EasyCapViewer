/* Copyright (c) 2011, Ben Trask
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
#import "ECV05e1_0408Source.h"

// Models/Devices/Video/USB/05e1:0408
#import "stk11xx.h"

// Models/Pipes/Video
#import "ECVVideoPipe.h"

// Models/Video
#import "ECVPixelBuffer.h"

// Models
#import "ECVVideoFormat.h"

// Other Sources
#import "ECVDebug.h"
#import "ECVFoundationAdditions.h"

enum {
	ECVSVideoInput = 0,
	ECVComposite1Input = 1,
	ECVComposite2Input = 2,
	ECVComposite3Input = 3,
	ECVComposite4Input = 4,
};
enum {
	ECVHighFieldFlag = 1 << 6,
	ECVNewImageFlag = 1 << 7,
};

@interface ECV05e1_0408Pipe : ECVVideoPipe
{
	@private
	NSUInteger _input;
}

@property(assign) NSUInteger input;

@end

@interface ECV05e1_0408Source(Private)

- (ECV05e1_0408Pipe *)_primaryPipe;
- (NSUInteger)_currentInput;
- (ECVVideoFormat *)_currentFormat;
- (void)_nextFieldType:(ECVFieldType)fieldType;
- (void)_removePipe:(ECV05e1_0408Pipe *)pipe;

- (ECVIntegerSize)_inputFieldSize;
- (ECVIntegerSize)_inputFrameSize;
- (ECVIntegerSize)_outputFieldSize;
- (ECVIntegerSize)_outputFrameSize;

- (BOOL)_initializeAudio;
- (BOOL)_initializeResolution;
- (BOOL)_setVideoSource:(NSUInteger)source;
- (BOOL)_setStreaming:(BOOL)flag;
- (BOOL)_SAA711XExpect:(u_int8_t)val;

@end

@implementation ECV05e1_0408Source

#pragma mark -ECV05e1_0408Source(Private)

- (ECV05e1_0408Pipe *)_primaryPipe
{
	return CFArrayGetCount(_pipes) ? CFArrayGetValueAtIndex(_pipes, 0) : nil;
}
- (NSUInteger)_currentInput
{
	return [[self _primaryPipe] input];
}
- (ECVVideoFormat *)_currentFormat
{
	return [[self _primaryPipe] format];
}
- (void)_nextFieldType:(ECVFieldType)fieldType
{
	NSUInteger const input = [self _currentInput];
	ECVVideoFormat *const format = [self _currentFormat];

	CFMutableArrayRef const pipes = _pipes;
	CFIndex const count = CFArrayGetCount(pipes);
	CFIndex i;
	for(i = 0; i < count; ++i) {
		ECV05e1_0408Pipe *const pipe = CFArrayGetValueAtIndex(pipes, i);
		if([pipe input] != input) continue;
		if(!ECVEqualObjects([pipe format], format)) continue;
		[pipe writeField:_pendingBuffer type:fieldType];
	}

	[_pendingBuffer release];
	ECVIntegerSize const pixelSize = [self _outputFrameSize];
	OSType const pixelFormat = kCVPixelFormatType_422YpCbCr8;
	NSUInteger const bytesPerRow = ECVPixelFormatBytesPerPixel(pixelFormat) * pixelSize.width;
	_pendingBuffer = [[ECVConcreteMutablePixelBuffer alloc] initWithPixelSize:pixelSize bytesPerRow:bytesPerRow pixelFormat:pixelFormat];
	_offset = 0;
}
- (void)_removePipe:(ECV05e1_0408Pipe *)pipe
{
	CFMutableArrayRef const pipes = _pipes;
	CFIndex const i = CFArrayGetFirstIndexOfValue(pipes, CFRangeMake(0, CFArrayGetCount(pipes)), pipe);
	if(kCFNotFound != i) CFArrayRemoveValueAtIndex(pipes, i);
	// TODO: The current format may have changed, so we may need to stop and restart the device.
}

#pragma mark -

- (ECVIntegerSize)_inputFieldSize
{
	ECVIntegerSize const s = [self _inputFrameSize];
	return (ECVIntegerSize){s.width, s.height / 2};
}
- (ECVIntegerSize)_inputFrameSize
{
	return ECVIntegerSizeFromString([[self _currentFormat] valueForProperty:@"ECV05e1_0408InputSize"]);
}
- (ECVIntegerSize)_outputFieldSize
{
	ECVIntegerSize const s = [self _outputFrameSize];
	return (ECVIntegerSize){s.width, s.height / 2};
}
- (ECVIntegerSize)_outputFrameSize
{
	return [[self _currentFormat] pixelSize];
}

#pragma mark -

- (BOOL)_initializeAudio
{
	if(![self writeVT1612ARegister:0x94 value:0x00]) return NO;
	if(![self writeIndex:0x0506 value:0x01]) return NO;
	if(![self writeIndex:0x0507 value:0x00]) return NO;
	if(![_VT1612AChip initialize]) return NO;
	ECVLog(ECVNotice, @"Device audio version: %@", [_VT1612AChip vendorAndRevisionString]);
	return YES;
}
- (BOOL)_initializeResolution
{
	ECVIntegerSize inputSize = [self _inputFrameSize];
	ECVIntegerSize standardSize = inputSize;
	switch(inputSize.width) {
		case 704:
		case 352:
		case 176:
			inputSize.width = 704;
			standardSize.width = 706;
			break;
		case 640:
		case 320:
		case 160:
			inputSize.width = 640;
			standardSize.width = 644;
			break;
	}
	switch(inputSize.height) {
		case 576:
		case 288:
		case 144:
			inputSize.height = 576;
			standardSize.height = 578;
			break;
		case 480:
		case 240:
		case 120:
			inputSize.height = 480;
			standardSize.height = 486;
			break;
	}
	size_t const bpp = ECVPixelFormatBytesPerPixel(kCVPixelFormatType_422YpCbCr8);
	struct {
		u_int16_t reg;
		u_int16_t val;
	} settings[] = {
		{0x110, (standardSize.width - inputSize.width) * bpp},
		{0x111, 0},
		{0x112, (standardSize.height - inputSize.height) / 2},
		{0x113, 0},
		{0x114, standardSize.width * bpp},
		{0x115, 5},
		{0x116, standardSize.height / 2},
		{0x117, ![self is60HzFormat]},
	};
	NSUInteger i = 0;
	for(; i < numberof(settings); i++) if(![self writeIndex:settings[i].reg value:settings[i].val]) return NO;
	return YES;
}
- (BOOL)_setVideoSource:(NSUInteger)source
{
	UInt8 val = 0;
	switch(source) {
		case ECVComposite1Input: val = 3; break;
		case ECVComposite2Input: val = 2; break;
		case ECVComposite3Input: val = 1; break;
		case ECVComposite4Input: val = 0; break;
		case ECVSVideoInput: return YES;
		default: return NO;
	}
	if(dev_stk0408_write0(self, 1 << 7 | 0x3 << 3, 1 << 7 | val << 3)) return NO;
	return YES;
}
- (BOOL)_setStreaming:(BOOL)flag
{
	u_int8_t value;
	if(![self readIndex:STK0408StatusRegistryIndex value:&value]) return NO;
	if(flag) value |= STK0408StatusStreaming;
	else value &= ~STK0408StatusStreaming;
	return [self writeIndex:STK0408StatusRegistryIndex value:value];
}
- (BOOL)_SAA711XExpect:(u_int8_t)val
{
	NSUInteger retry = 4;
	u_int8_t result = 0;
	while(retry--) {
		if(![self readIndex:0x201 value:&result]) return NO;
		if(val == result) return YES;
		usleep(100);
	}
	ECVLog(ECVError, @"Invalid SAA711X result %x (expected %x)", (unsigned)result, (unsigned)val);
	return NO;
}

#pragma mark -ECVUSBVideoSource

- (id)initWithService:(io_service_t)service
{
	if((self = [super initWithService:service])) {
		_SAA711XChip = [[SAA711XChip alloc] init];
		[_SAA711XChip setBrightness:0.5]; // TODO: Figure out a new user defaults system. Perhaps use the USB serial number property.
		[_SAA711XChip setContrast:0.5];
		[_SAA711XChip setSaturation:0.5];
		[_SAA711XChip setHue:0.5];
		[_SAA711XChip setDevice:self];
		_VT1612AChip = [[VT1612AChip alloc] init];
		[_VT1612AChip setDevice:self];
		_pipes = CFArrayCreateMutable(kCFAllocatorDefault, 0, NULL);
	}
	return self;
}

#pragma mark -ECVUSBVideoSource(ECVRead_Thread)

- (void)read
{
	_offset = 0;
	dev_stk0408_initialize_device(self);
	if(![_SAA711XChip initialize]) return;
	ECVLog(ECVNotice, @"Device video version: %lx", (unsigned long)[_SAA711XChip versionNumber]);
	if(![self _initializeAudio]) return;
	if(![self _setVideoSource:[self _currentInput]]) return;
	if(![self _initializeResolution]) return;
	if(![self setAlternateInterface:5]) return;
	if(![self _setStreaming:YES]) return;
	[super read];
	(void)[self _setStreaming:NO];
	(void)[self setAlternateInterface:0];
}
- (BOOL)keepReading
{
	if(![super keepReading]) return NO;
	u_int8_t value;
	if(![self readIndex:0x01 value:&value]) return NO;
	if(0x03 != value) {
		ECVLog(ECVError, @"Device watchdog was 0x%02x (should be 0x03).", value);
		return NO;
	}
	return YES;
}

#pragma mark -ECVUSBVideoSource(ECVReadAbstract_Thread)

- (void)readBytes:(UInt8 const *)bytes length:(NSUInteger)length
{
	if(!length) return;
	NSUInteger header = 4;
	if(bytes[0] & ECVNewImageFlag) {
		[self _nextFieldType:ECVHighFieldFlag & bytes[0] ? ECVHighField : ECVLowField];
		header += 4;
	}
	if(length <= header) return;

	NSUInteger const realLength = length - header;
	ECVIntegerSize const pixelSize = [self _inputFieldSize];
	OSType const pixelFormat = kCVPixelFormatType_422YpCbCr8;
	NSUInteger const bytesPerRow = ECVPixelFormatBytesPerPixel(pixelFormat) * pixelSize.width;
	ECVPointerPixelBuffer *const buffer = [[ECVPointerPixelBuffer alloc] initWithPixelSize:pixelSize bytesPerRow:bytesPerRow pixelFormat:pixelFormat bytes:bytes + header validRange:NSMakeRange(_offset, realLength)];

	ECVIntegerSize const outputSize = [self _outputFieldSize];
	[_pendingBuffer drawPixelBuffer:buffer options:ECVDrawToHighField | ECVDrawToLowField atPoint:(ECVIntegerPoint){(outputSize.width - pixelSize.width) / 2, (outputSize.height - pixelSize.height) / 2}];

	[buffer release];
	_offset += realLength;
}

#pragma mark -ECVUSBVideoSource(ECVAbstract)

- (UInt8)pipeRef
{
	return 2;
}
- (UInt32)maximumMicrosecondsInFrame
{
	return kUSBHighSpeedMicrosecondsInFrame;
}

#pragma mark -ECVVideoSource(ECVAbstract)

- (ECVVideoPipe *)videoPipeWithInput:(id)input
{
	NSUInteger const i = [input unsignedIntegerValue];
	ECV05e1_0408Pipe *const pipe = [[[ECV05e1_0408Pipe alloc] initWithVideoSource:self] autorelease];
	[pipe setInput:i];
	[pipe setName:[self localizedStringForInput:input]];
	[pipe setInputPixelFormat:kCVPixelFormatType_422YpCbCr8];
	CFArrayAppendValue(_pipes, pipe); // TODO: Locking will eventually be necessary.
	return pipe;
}

#pragma mark -ECVSource(ECVAbstract)

- (NSArray *)inputs
{
	return [NSArray arrayWithObjects:
		[NSNumber numberWithUnsignedInteger:ECVSVideoInput],
		[NSNumber numberWithUnsignedInteger:ECVComposite1Input],
		[NSNumber numberWithUnsignedInteger:ECVComposite2Input],
		[NSNumber numberWithUnsignedInteger:ECVComposite3Input],
		[NSNumber numberWithUnsignedInteger:ECVComposite4Input],
		nil];
}
- (NSString *)localizedStringForInput:(id)input
{
	switch([input unsignedIntegerValue]) {
		case ECVSVideoInput    : return NSLocalizedString(@"S-Video", nil);
		case ECVComposite1Input: return NSLocalizedString(@"Composite 1", nil);
		case ECVComposite2Input: return NSLocalizedString(@"Composite 2", nil);
		case ECVComposite3Input: return NSLocalizedString(@"Composite 3", nil);
		case ECVComposite4Input: return NSLocalizedString(@"Composite 4", nil);
	}
	ECVAssertNotReached(@"Invalid input.");
	return nil;
}

#pragma mark -NSObject

- (void)dealloc
{
	[_SAA711XChip release];
	[_VT1612AChip release];
	CFRelease(_pipes);
	[super dealloc];
}

#pragma mark -<SAA711XDevice>

- (BOOL)writeSAA711XRegister:(u_int8_t)reg value:(int16_t)val
{
	if(![self writeIndex:0x204 value:reg]) return NO;
	if(![self writeIndex:0x205 value:val]) return NO;
	if(![self writeIndex:0x200 value:0x01]) return NO;
	if(![self _SAA711XExpect:0x04]) {
		ECVLog(ECVError, @"SAA711X failed to write %x to %x", (unsigned)val, (unsigned)reg);
		return NO;
	}
	return YES;
}
- (BOOL)readSAA711XRegister:(u_int8_t)reg value:(out u_int8_t *)outVal
{
	if(![self writeIndex:0x208 value:reg]) return NO;
	if(![self writeIndex:0x200 value:0x20]) return NO;
	if(![self _SAA711XExpect:0x01]) {
		ECVLog(ECVError, @"SAA711X failed to read %x", (unsigned)reg);
		return NO;
	}
	return [self readIndex:0x209 value:outVal];
}
- (SAA711XMODESource)SAA711XMODESource
{
	return [self SVideo] ? SAA711XMODESVideoAI12_YGain : SAA711XMODECompositeAI11;
}
- (BOOL)SVideo
{
	return [self _currentInput] == ECVSVideoInput;
}
- (SAA711XCSTDFormat)SAA711XCSTDFormat
{
	return [[[self _currentFormat] valueForProperty:@"SAA711XCSTDFormat"] unsignedIntegerValue];
}
- (BOOL)is60HzFormat
{
	return [[[self _currentFormat] valueForProperty:@"SAA711XIs60Hz"] boolValue];
}
- (BOOL)SAA711XRTP0OutputPolarityInverted
{
	return YES;
}

#pragma mark -<VT1612ADevice>

- (BOOL)writeVT1612ARegister:(u_int8_t)reg value:(u_int16_t)val
{
	union {
		u_int16_t v16;
		u_int8_t v8[2];
	} const v = {
		.v16 = CFSwapInt16HostToLittle(val),
	};
	if(![self writeIndex:0x504 value:reg]) return NO;
	if(![self writeIndex:0x502 value:v.v8[0]]) return NO;
	if(![self writeIndex:0x503 value:v.v8[1]]) return NO;
	if(![self writeIndex:0x500 value:0x8c]) return NO;
	return YES;
}
- (BOOL)readVT1612ARegister:(u_int8_t)reg value:(out u_int16_t *)outVal
{
	if(![self writeIndex:0x504 value:reg]) return NO;
	if(![self writeIndex:0x500 value:0x8b]) return NO;
	union {
		u_int8_t v8[2];
		u_int16_t v16;
	} val = {};
	if(![self readIndex:0x502 value:val.v8 + 0]) return NO;
	if(![self readIndex:0x503 value:val.v8 + 1]) return NO;
	if(outVal) *outVal = CFSwapInt16LittleToHost(val.v16);
	return YES;
}

@end

@implementation ECV05e1_0408Pipe

#pragma mark -ECV05e1_0408Pipe

@synthesize input = _input;

#pragma mark -NSObject

- (void)dealloc
{
	[[self videoSource] _removePipe:self];
	[super dealloc];
}

@end
