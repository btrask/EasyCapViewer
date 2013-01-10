/* Copyright (c) 2012, Ben Trask
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE AUTHORS ''AS IS'' AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. */
#import <QTKit/QTKit.h>

@interface ECVVideoFormat : NSObject

+ (NSMenu *)menuWithVideoFormats:(NSSet *const)formats;
+ (id)format;

@end

@interface ECVVideoFormat(ECVAbstract)

- (NSString *)localizedName;
- (ECVIntegerSize)frameSize;
- (BOOL)isInterlaced;
- (BOOL)isProgressive;
- (NSUInteger)frameGroupSize;
- (QTTime)frameRate;
- (BOOL)is60Hz;
- (BOOL)is50Hz;

- (void)addToMenu:(NSMenu *const)menu;
- (NSComparisonResult)compare:(ECVVideoFormat *const)obj;

@end

@interface ECVCommon60HzVideoFormat : ECVVideoFormat
@end
@interface ECVCommon50HzVideoFormat : ECVVideoFormat
@end

@interface ECVVideoFormat_NTSC_M : ECVCommon60HzVideoFormat
@end
@interface ECVVideoFormat_PAL_60 : ECVCommon60HzVideoFormat
@end
@interface ECVVideoFormat_NTSC_443_60Hz : ECVCommon60HzVideoFormat
@end
@interface ECVVideoFormat_PAL_M : ECVCommon60HzVideoFormat
@end
@interface ECVVideoFormat_NTSC_J : ECVCommon60HzVideoFormat
@end

@interface ECVVideoFormat_PAL_BGDHI : ECVCommon50HzVideoFormat
@end
@interface ECVVideoFormat_NTSC_443_50Hz : ECVCommon50HzVideoFormat
@end
@interface ECVVideoFormat_PAL_N : ECVCommon50HzVideoFormat
@end
@interface ECVVideoFormat_NTSC_N : ECVCommon50HzVideoFormat
@end
@interface ECVVideoFormat_SECAM : ECVCommon50HzVideoFormat
@end
