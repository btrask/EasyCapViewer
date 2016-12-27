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
#import "ECVFrameRateConverter.h"
#import <AVFoundation/AVFoundation.h>


static ECVRational ECVRationalFromCMTime(CMTime t)
{
	return ECVMakeRational(t.value, t.timescale);
}
static CMTime ECVRationalToCMTime(ECVRational r)
{
	return CMTimeMake(r.numer,(int32_t)r.denom);
}

@interface ECVFrameRateConverter(Private)

+ (NSData *)_frameRepeatDataWithSourceFrameRate:(CMTime)sourceFrameRate targetFrameRate:(CMTime)targetFrameRate;

- (NSUInteger)_repeatCountForFrame:(NSUInteger)i;

@end

@implementation ECVFrameRateConverter

#pragma mark +ECVFrameRateConverter

+ (CMTime)frameRateWithRatio:(ECVRational)ratio ofFrameRate:(CMTime)rate
{
	return ECVRationalToCMTime(ECVRationalDivide(ECVRationalFromCMTime(rate), ratio));
}

#pragma mark +ECVFrameRateConverter(Private)

+ (NSData *)_frameRepeatDataWithSourceFrameRate:(CMTime)sourceFrameRate targetFrameRate:(CMTime)targetFrameRate
{
	ECVRational const s = ECVRationalFromCMTime(sourceFrameRate);
	ECVRational const t = ECVRationalFromCMTime(targetFrameRate);
	ECVRational const ratio = ECVRationalDivide(s, t);
	ECVRational const one = ECVMakeRational(1, 1);

	ECVRational const targetFrameCount = ECVRationalLCM(ratio, one);
	ECVRational const sourceFrameCount = ECVRationalDivide(targetFrameCount, ratio);
	ECVRational const lowerBoundRatio = ECVMakeRational(floor(ECVRationalToCGFloat(ratio)), 1);
	ECVRational const extraFrames = ECVRationalSubtract(targetFrameCount, ECVRationalMultiply(lowerBoundRatio, sourceFrameCount));

	NSUInteger const sourceFrameCountInteger = ECVRationalToNSInteger(sourceFrameCount);
	NSMutableData *const data = [NSMutableData dataWithLength:sizeof(NSUInteger) * sourceFrameCountInteger];
	NSUInteger *const values = (NSUInteger *)[data mutableBytes];
	NSUInteger i;

	NSUInteger const lowerBoundRatioInteger = ECVRationalToNSInteger(lowerBoundRatio);
	for(i = 0; i < sourceFrameCountInteger; ++i) values[i] = lowerBoundRatioInteger;

	NSUInteger remaining = ECVRationalToNSInteger(extraFrames);
	if(remaining) {
		NSUInteger const extraFrameFrequency = floor(ECVRationalToCGFloat(ECVRationalDivide(sourceFrameCount, extraFrames)));
		for(i = 0; i < sourceFrameCountInteger && remaining; i += extraFrameFrequency, --remaining) values[i]++;
	}

	return data;
}

#pragma -ECVFrameRateConverter

- (id)initWithSourceFrameRate:(CMTime)sourceFrameRate targetFrameRate:(CMTime)targetFrameRate
{
	if((self = [super init])) {
		_sourceFrameRate = sourceFrameRate;
		_targetFrameRate = targetFrameRate;
		_frameRepeatData = [[[self class] _frameRepeatDataWithSourceFrameRate:sourceFrameRate targetFrameRate:targetFrameRate] copy];
		_count = [_frameRepeatData length] / sizeof(NSUInteger);
		_index = 0;
	}
	return self;
}
@synthesize sourceFrameRate = _sourceFrameRate;
@synthesize targetFrameRate = _targetFrameRate;

#pragma mark -

- (NSUInteger)currentFrameRepeatCount
{
	return [self _repeatCountForFrame:_index];
}
- (NSUInteger)nextFrameRepeatCount
{
	return [self _repeatCountForFrame:(_index++ % _count)];
}

#pragma mark -ECVFrameRateConverter(Private)

- (NSUInteger)_repeatCountForFrame:(NSUInteger)i
{
	NSParameterAssert(i < _count);
	return ((NSUInteger *)[_frameRepeatData bytes])[i];
}

#pragma mark -NSObject

- (void)dealloc
{
	[_frameRepeatData release];
	[super dealloc];
}

@end
