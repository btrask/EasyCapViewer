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
#import "ECVVideoFormat.h"

static NSMutableDictionary *ECVVideoFormatByIdentifier = nil;

@implementation ECVVideoFormat

#pragma mark +ECVVideoFormat

+ (NSArray *)formats
{
	return [ECVVideoFormatByIdentifier allValues];
}
+ (id)formatWithIdentifier:(NSString *)ident
{
	return [[[ECVVideoFormatByIdentifier objectForKey:ident] retain] autorelease];
}
+ (void)registerFormat:(ECVVideoFormat *)format
{
	if(format) [ECVVideoFormatByIdentifier setObject:format forKey:[format identifier]];
}

#pragma mark +NSObject

+ (void)initialize
{
	if(ECVVideoFormatByIdentifier) return;
	ECVVideoFormatByIdentifier = [[NSMutableDictionary alloc] init];
	NSDictionary *const formatByIdent = [[[NSDictionary alloc] initWithContentsOfFile:[[NSBundle bundleForClass:self] pathForResource:@"ECVVideoFormats" ofType:@"plist"]] autorelease];
	for(NSString *const ident in formatByIdent) [self registerFormat:[[[self alloc] initWithIdentifier:ident dictionary:[formatByIdent objectForKey:ident]] autorelease]];
	NSLog(@"%@", ECVVideoFormatByIdentifier);
}

#pragma mark -ECVVideoFormat

- (id)initWithIdentifier:(NSString *)ident dictionary:(NSDictionary *)dict
{
	if((self = [super init])) {
		_identifier = [ident copy];
		_properties = [dict copy];
	}
	return self;
}
- (NSDictionary *)properties
{
	return [[_properties copy] autorelease];
}
- (id)valueForProperty:(NSString *)key
{
	return [_properties objectForKey:key];
}

#pragma mark -

- (NSString *)identifier
{
	return [[_identifier copy] autorelease];
}
- (NSString *)localizedName
{
	return [[[self valueForProperty:@"ECVName"] copy] autorelease]; // TODO: Localize.
}
- (ECVRational)frameRate
{
	return ECVRationalFromString([self valueForProperty:@"ECVFrameRate"]);
}
- (ECVIntegerSize)pixelSize
{
	return ECVIntegerSizeFromString([self valueForProperty:@"ECVPixelSize"]);
}
- (ECVRational)sampleMatrixAspectRatio
{
	return ECVRationalFromString([self valueForProperty:@"ECVSampleMatrixAspectRatio"]);
}

#pragma mark -

- (ECVRational)sampleAspectRatioWithDisplayAspectRatio:(ECVRational)DAR
{
	return ECVRationalDivide(DAR, [self sampleMatrixAspectRatio]); // <http://www.mir.com/DMG/aspect.html#definitions>
}
- (ECVIntegerSize)nativeOutputSizeWithDisplayAspectRatio:(ECVRational)DAR
{
	ECVIntegerSize const pixelSize = [self pixelSize];
	ECVRational const SAR = [self sampleAspectRatioWithDisplayAspectRatio:DAR];
	CGFloat const theoreticalWidth = ECVRationalToCGFloat(SAR) * pixelSize.width;
	NSUInteger const widthToNearestMacroblock = (NSUInteger)round(theoreticalWidth / 16.0) * 16;
	return (ECVIntegerSize){widthToNearestMacroblock, pixelSize.height};
}

#pragma mark -ECVVideoFormat<NSCopying>

- (id)copyWithZone:(NSZone *)zone
{
	NSParameterAssert(NSShouldRetainWithZone(self, zone));
	return [self retain];
}

#pragma mark -NSObject

- (void)dealloc
{
	[_identifier release];
	[_properties release];
	[super dealloc];
}

#pragma mark -NSObject<NSObject>

- (NSUInteger)hash
{
	return [[ECVVideoFormat class] hash] ^ [_properties hash];
}
- (BOOL)isEqual:(id)obj
{
	return [obj isKindOfClass:[ECVVideoFormat class]] && [_properties isEqualToDictionary:[obj properties]];
}

@end
