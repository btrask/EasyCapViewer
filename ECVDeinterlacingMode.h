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
@class ECVVideoFormat;
@class ECVVideoStorage;
#import "ECVPixelBuffer.h"
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

@interface ECVDeinterlacingMode : NSObject
{
	@private
	ECVVideoStorage *_videoStorage;
	ECVVideoFormat *_videoFormat;
	ECVMutablePixelBuffer *_pendingBuffer;
}

+ (Class)deinterlacingModeWithType:(ECVDeinterlacingModeType)type;

- (id)initWithVideoStorage:(ECVVideoStorage *const)storage videoFormat:(ECVVideoFormat *const)videoFormat;
- (ECVVideoStorage *)videoStorage;
- (ECVVideoFormat *)videoFormat;
- (ECVMutablePixelBuffer *)pendingBuffer;

- (ECVMutablePixelBuffer *)nextBufferWithFieldType:(ECVFieldType const)fieldType;
- (ECVMutablePixelBuffer *)finishedBufferWithNextFieldType:(ECVFieldType const)fieldType;
- (void)drawPixelBuffer:(ECVPixelBuffer *)buffer atPoint:(ECVIntegerPoint const)point;
- (ECVPixelBufferDrawingOptions)drawingOptions;
- (void)clearPendingBuffer;

@end

@interface ECVDeinterlacingMode(ECVAbstract)

+ (ECVDeinterlacingModeType)deinterlacingModeType;

@end

@interface ECVProgressiveScanMode : ECVDeinterlacingMode
@end

@interface ECVLineDoubleHQDeinterlacingMode : ECVDeinterlacingMode
{
	@private
	NSUInteger _rowOffset;
}
@end

@interface ECVWeaveDeinterlacingMode : ECVDeinterlacingMode
{
	@private
	ECVPixelBufferDrawingOptions _drawingOptions;
}
@end

@interface ECVAlternateDeinterlacingMode : ECVDeinterlacingMode
{
	@private
	ECVPixelBufferDrawingOptions _drawingOptions;
}
@end

@interface ECVHalfHeightDeinterlacingMode : ECVDeinterlacingMode
@end

@interface ECVDropDeinterlacingMode : ECVHalfHeightDeinterlacingMode
@end

@interface ECVLineDoubleLQDeinterlacingMode : ECVHalfHeightDeinterlacingMode
@end

@interface ECVBlurDeinterlacingMode : ECVHalfHeightDeinterlacingMode
{
	@private
	ECVMutablePixelBuffer *_blurBuffer;
}
@end
