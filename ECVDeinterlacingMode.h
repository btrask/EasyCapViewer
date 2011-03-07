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
#import "ECVDebug.h"

// Models
@class ECVVideoFrame;

enum {
	ECVProgressiveScan = 4,
	ECVWeave = 0,
	ECVLineDoubleLQ = 1,
	ECVLineDoubleHQ = 5,
	ECVAlternate = 2,
	ECVBlur = 3,
	ECVDrop = 6,
};
typedef NSInteger ECVDeinterlacingModeType;

@interface ECVDeinterlacingMode : NSObject <NSCopying>

+ (Class)deinterlacingModeWithType:(ECVDeinterlacingModeType)type;

- (void)prepareNewFrameInArray:(NSArray *)frames;
- (void)finishNewFrameInArray:(NSArray *)frames;

@end

@interface ECVDeinterlacingMode(ECVAbstract)

+ (ECVDeinterlacingModeType)deinterlacingModeType;

- (BOOL)isAcceptableFieldType:(ECVFieldType)fieldType;
- (BOOL)shouldDropFieldWithType:(ECVFieldType)fieldType;
- (BOOL)hasOffsetFields;
- (ECVIntegerSize)outputSizeForCaptureSize:(ECVIntegerSize)captureSize;
- (BOOL)drawsDoubledLines;
- (NSUInteger)newestCompletedFrameIndex;
- (NSUInteger)frameGroupSize;

@end

@interface ECVProgressiveScanMode : ECVDeinterlacingMode
@end

@interface ECVWeaveDeinterlacingMode : ECVDeinterlacingMode
@end

@interface ECVLineDoubleLQDeinterlacingMode : ECVDeinterlacingMode
@end

@interface ECVLineDoubleHQDeinterlacingMode : ECVDeinterlacingMode
@end

@interface ECVAlternateDeinterlacingMode : ECVDeinterlacingMode
@end

@interface ECVBlurDeinterlacingMode : ECVDeinterlacingMode
@end

@interface ECVDropDeinterlacingMode : ECVDeinterlacingMode
@end
