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
typedef NSInteger ECVDeinterlacerType;

@interface ECVDeinterlacer : NSObject
{
	@private
	ECVVideoStorage *_videoStorage;
	ECVMutablePixelBuffer *_pendingBuffer;
}

+ (Class)deinterlacerWithType:(ECVDeinterlacerType)type;

- (id)initWithVideoStorage:(ECVVideoStorage *)storage;
@property(readonly) ECVVideoStorage *videoStorage;
@property(readonly) ECVIntegerSize pixelSize;
@property(readonly) NSUInteger frameGroupSize;
@property(readonly) ECVMutablePixelBuffer *pendingBuffer;

- (ECVMutablePixelBuffer *)nextBufferWithFieldType:(ECVFieldType)fieldType;
- (ECVMutablePixelBuffer *)finishedBufferWithNextFieldType:(ECVFieldType)fieldType;
- (void)drawPixelBuffer:(ECVPixelBuffer *)buffer atPoint:(ECVIntegerPoint)point;
- (ECVPixelBufferDrawingOptions)drawingOptions;
- (void)clearPendingBuffer;

@end

@interface ECVDeinterlacer(ECVAbstract)

+ (ECVDeinterlacerType)DeinterlacerType;

@end

@interface ECVProgressiveScanMode : ECVDeinterlacer
@end

@interface ECVLineDoubleHQDeinterlacer : ECVDeinterlacer
{
	@private
	NSUInteger _rowOffset;
}
@end

@interface ECVWeaveDeinterlacer : ECVDeinterlacer
{
	@private
	ECVPixelBufferDrawingOptions _drawingOptions;
}
@end

@interface ECVAlternateDeinterlacer : ECVDeinterlacer
{
	@private
	ECVPixelBufferDrawingOptions _drawingOptions;
}
@end

@interface ECVHalfHeightDeinterlacer : ECVDeinterlacer
@end

@interface ECVDropDeinterlacer : ECVHalfHeightDeinterlacer
@end

@interface ECVLineDoubleLQDeinterlacer : ECVHalfHeightDeinterlacer
@end

@interface ECVBlurDeinterlacer : ECVHalfHeightDeinterlacer
{
	@private
	ECVMutablePixelBuffer *_blurBuffer;
}
@end
