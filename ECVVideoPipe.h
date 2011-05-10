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
#import "ECVPipe.h"
#import <QTKit/QTKit.h>

// Models/Sources/Video
@class ECVVideoSource;

// Models/Storages/Video
@class ECVVideoStorage;

// Models/Video
@class ECVPixelBuffer;
@class ECVMutablePixelBuffer;

@interface ECVVideoPipe : ECVPipe
{
	@private
//	ECVDeinterlacer *_deinterlacer;
//	ECVFrameRateConverter *_frameRateConverter;
//	NSUInteger _frameRepeatCount;
	// TODO: More powerful frame conversion (right now we just drop low fields).

	NSLock *_lock;
	ECVPixelBuffer *_buffer;
	ECVIntegerPoint _position;
}

- (id)initWithVideoSource:(ECVVideoSource *)source;
@property(readonly) id videoSource;
@property(readonly) ECVVideoStorage *videoStorage;

// Input
//@property(readonly) ECVIntegerSize inputSize;
//@property(readonly) QTTime inputFrameRate;
//@property(readonly) OSType inputPixelFormat;

// Output
//@property(readonly) ECVIntegerSize outputSize;
//@property(readonly) QTTime outputFrameRate;
//@property(readonly) OSType outputPixelFormat;

// Options
@property(assign) ECVIntegerPoint position;

@end

@interface ECVVideoPipe(ECVFromSource)

//@property(assign) ECVIntegerSize inputSize;
//@property(assign) QTTime inputFrameRate;
//@property(assign) OSType inputPixelFormat;

@end

@interface ECVVideoPipe(ECVFromSource_Threaded)

- (void)writeField:(ECVPixelBuffer *)buffer type:(ECVFieldType)fieldType;

@end

@interface ECVVideoPipe(ECVFromStorage)

@property(assign) ECVVideoStorage *videoStorage;

//@property(assign) ECVIntegerSize outputSize;
//@property(assign) QTTime outputFrameRate;
//@property(assign) OSType outputPixelFormat;

@end

@interface ECVVideoPipe(ECVFromStorage_Threaded)

- (void)readIntoStorageBuffer:(ECVMutablePixelBuffer *)buffer;

@end
