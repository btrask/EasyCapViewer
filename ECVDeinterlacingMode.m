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
#import "ECVDeinterlacingMode.h"

// Models
#import "ECVVideoFrame.h"

@implementation ECVDeinterlacingMode

#pragma mark +ECVDeinterlacingMode

+ (id)deinterlacingModeWithType:(ECVDeinterlacingModeType)type
{
	Class c = Nil;
	switch(type) {
		case ECVProgressiveScan:
			c = [ECVProgressiveScanMode class]; break;
		case ECVWeave:
			c = [ECVWeaveDeinterlacingMode class]; break;
		case ECVLineDoubleLQ:
			c = [ECVLineDoubleLQDeinterlacingMode class]; break;
		case ECVLineDoubleHQ:
			c = [ECVLineDoubleHQDeinterlacingMode class]; break;
		case ECVAlternate:
			c = [ECVAlternateDeinterlacingMode class]; break;
		case ECVBlur:
			c = [ECVBlurDeinterlacingMode class]; break;
		case ECVDrop:
			c = [ECVDropDeinterlacingMode class]; break;
	}
	return [[[c alloc] init] autorelease];
}

#pragma mark -ECVDeinterlacingMode

- (ECVVideoFrame *)prepareNewFrame:(ECVVideoFrame *)frame1 withPreviousFrame:(ECVVideoFrame *)frame2
{
	return frame1;
}
- (ECVVideoFrame *)finishOldFrame:(ECVVideoFrame *)frame1 withPreviousFrame:(ECVVideoFrame *)frame2
{
	[frame1 clearTail];
	return frame1;
}

#pragma mark -<NSCopying>

- (id)copyWithZone:(NSZone *)zone
{
	return [self retain];
}

#pragma mark -<NSObject>

- (NSUInteger)hash
{
	return [[self class] hash];
}
- (BOOL)isEqual:(id)obj
{
	return [obj isMemberOfClass:[self class]];
}

@end

@implementation ECVProgressiveScanMode

#pragma mark -ECVDeinterlacingMode(ECVAbstract)

- (ECVDeinterlacingModeType)deinterlacingModeType
{
	return ECVProgressiveScan;
}

#pragma mark -

- (BOOL)isAcceptableFieldType:(ECVFieldType)fieldType
{
	return ECVFullFrame == fieldType;
}
- (BOOL)shouldDropFieldWithType:(ECVFieldType)fieldType
{
	return NO;
}
- (BOOL)hasOffsetFields
{
	return NO;
}
- (ECVIntegerSize)outputSizeForCaptureSize:(ECVIntegerSize)captureSize
{
	return captureSize;
}
- (BOOL)drawsDoubledLines
{
	return NO;
}
- (NSUInteger)newestCompletedFrameIndex
{
	return 1;
}
- (NSUInteger)frameGroupSize
{
	return 1;
}

@end

@implementation ECVWeaveDeinterlacingMode

#pragma mark -ECVDeinterlacingMode

- (ECVVideoFrame *)prepareNewFrame:(ECVVideoFrame *)frame1 withPreviousFrame:(ECVVideoFrame *)frame2
{
	[frame1 fillWithFrame:frame2];
	return [super prepareNewFrame:frame1 withPreviousFrame:frame2];
}

#pragma mark -ECVDeinterlacingMode(ECVAbstract)

- (ECVDeinterlacingModeType)deinterlacingModeType
{
	return ECVWeave;
}

#pragma mark -

- (BOOL)isAcceptableFieldType:(ECVFieldType)fieldType
{
	return ECVFullFrame != fieldType;
}
- (BOOL)shouldDropFieldWithType:(ECVFieldType)fieldType
{
	return NO;
}
- (BOOL)hasOffsetFields
{
	return YES;
}
- (ECVIntegerSize)outputSizeForCaptureSize:(ECVIntegerSize)captureSize
{
	return captureSize;
}
- (BOOL)drawsDoubledLines
{
	return NO;
}
- (NSUInteger)newestCompletedFrameIndex
{
	return 1;
}
- (NSUInteger)frameGroupSize
{
	return 2;
}

@end

@implementation ECVLineDoubleLQDeinterlacingMode

#pragma mark -ECVDeinterlacingMode(ECVAbstract)

- (ECVDeinterlacingModeType)deinterlacingModeType
{
	return ECVLineDoubleLQ;
}

#pragma mark -

- (BOOL)isAcceptableFieldType:(ECVFieldType)fieldType
{
	return ECVFullFrame != fieldType;
}
- (BOOL)shouldDropFieldWithType:(ECVFieldType)fieldType
{
	return NO;
}
- (BOOL)hasOffsetFields
{
	return NO;
}
- (ECVIntegerSize)outputSizeForCaptureSize:(ECVIntegerSize)captureSize
{
	return (ECVIntegerSize){captureSize.width, captureSize.height / 2};
}
- (BOOL)drawsDoubledLines
{
	return NO;
}
- (NSUInteger)newestCompletedFrameIndex
{
	return 1;
}
- (NSUInteger)frameGroupSize
{
	return 2;
}

@end

@implementation ECVLineDoubleHQDeinterlacingMode

#pragma mark -ECVDeinterlacingMode

- (ECVVideoFrame *)prepareNewFrame:(ECVVideoFrame *)frame1 withPreviousFrame:(ECVVideoFrame *)frame2
{
	[frame1 clearHead];
	return frame1;
}
- (ECVVideoFrame *)finishOldFrame:(ECVVideoFrame *)frame1 withPreviousFrame:(ECVVideoFrame *)frame2
{
	[frame1 fillHead];
	return [super finishOldFrame:frame1 withPreviousFrame:frame2];
}

#pragma mark -ECVDeinterlacingMode(ECVAbstract)

- (ECVDeinterlacingModeType)deinterlacingModeType
{
	return ECVLineDoubleHQ;
}

#pragma mark -

- (BOOL)isAcceptableFieldType:(ECVFieldType)fieldType
{
	return ECVFullFrame != fieldType;
}
- (BOOL)shouldDropFieldWithType:(ECVFieldType)fieldType
{
	return NO;
}
- (BOOL)hasOffsetFields
{
	return YES;
}
- (ECVIntegerSize)outputSizeForCaptureSize:(ECVIntegerSize)captureSize
{
	return captureSize;
}
- (BOOL)drawsDoubledLines
{
	return YES;
}
- (NSUInteger)newestCompletedFrameIndex
{
	return 1;
}
- (NSUInteger)frameGroupSize
{
	return 2;
}

@end

@implementation ECVAlternateDeinterlacingMode

#pragma mark -ECVDeinterlacingMode

- (ECVVideoFrame *)prepareNewFrame:(ECVVideoFrame *)frame1 withPreviousFrame:(ECVVideoFrame *)frame2
{
	[frame1 clear];
	return [super prepareNewFrame:frame1 withPreviousFrame:frame2];
}


#pragma mark -ECVDeinterlacingMode(ECVAbstract)

- (ECVDeinterlacingModeType)deinterlacingModeType
{
	return ECVAlternate;
}

#pragma mark -

- (BOOL)isAcceptableFieldType:(ECVFieldType)fieldType
{
	return ECVFullFrame != fieldType;
}
- (BOOL)shouldDropFieldWithType:(ECVFieldType)fieldType
{
	return NO;
}
- (BOOL)hasOffsetFields
{
	return YES;
}
- (ECVIntegerSize)outputSizeForCaptureSize:(ECVIntegerSize)captureSize
{
	return captureSize;
}
- (BOOL)drawsDoubledLines
{
	return NO;
}
- (NSUInteger)newestCompletedFrameIndex
{
	return 1;
}
- (NSUInteger)frameGroupSize
{
	return 2;
}

@end

@implementation ECVBlurDeinterlacingMode

#pragma mark -ECVDeinterlacingMode

- (ECVVideoFrame *)finishOldFrame:(ECVVideoFrame *)frame1 withPreviousFrame:(ECVVideoFrame *)frame2
{
	[frame2 blurWithFrame:frame1];
	return frame2;
}

#pragma mark -ECVDeinterlacingMode(ECVAbstract)

- (ECVDeinterlacingModeType)deinterlacingModeType
{
	return ECVBlur;
}

#pragma mark -

- (BOOL)isAcceptableFieldType:(ECVFieldType)fieldType
{
	return ECVFullFrame != fieldType;
}
- (BOOL)shouldDropFieldWithType:(ECVFieldType)fieldType
{
	return NO;
}
- (BOOL)hasOffsetFields
{
	return NO;
}
- (ECVIntegerSize)outputSizeForCaptureSize:(ECVIntegerSize)captureSize
{
	return (ECVIntegerSize){captureSize.width, captureSize.height / 2};
}
- (BOOL)drawsDoubledLines
{
	return NO;
}
- (NSUInteger)newestCompletedFrameIndex
{
	return 2;
}
- (NSUInteger)frameGroupSize
{
	return 2;
}

@end

@implementation ECVDropDeinterlacingMode

#pragma mark -ECVDeinterlacingMode(ECVAbstract)

- (ECVDeinterlacingModeType)deinterlacingModeType
{
	return ECVDrop;
}

#pragma mark -

- (BOOL)isAcceptableFieldType:(ECVFieldType)fieldType
{
	return ECVFullFrame != fieldType;
}
- (BOOL)shouldDropFieldWithType:(ECVFieldType)fieldType
{
	return ECVLowField == fieldType;
}
- (BOOL)hasOffsetFields
{
	return NO;
}
- (ECVIntegerSize)outputSizeForCaptureSize:(ECVIntegerSize)captureSize
{
	return (ECVIntegerSize){captureSize.width, captureSize.height / 2};
}
- (BOOL)drawsDoubledLines
{
	return NO;
}
- (NSUInteger)newestCompletedFrameIndex
{
	return 1;
}
- (NSUInteger)frameGroupSize
{
	return 1;
}

@end
