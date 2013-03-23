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
#import "ECVVideoSource.h"

@implementation ECVVideoSource

#pragma mark +ECVVideoSource

+ (id)source
{
	return [[[self alloc] init] autorelease];
}

#pragma mark -ECVVideoSource

- (BOOL)SVideo { return NO; }
- (BOOL)composite { return NO; }

#pragma mark -

- (id)serializedValue
{
	return NSStringFromClass([self class]);
}
- (BOOL)matchesSerializedValue:(id const)obj
{
	return BTEqualObjects(obj, [self serializedValue]);
}

#pragma mark -NSObject<NSObject>

- (NSUInteger)hash
{
	return [[self class] hash];
}
- (BOOL)isEqual:(id const)obj
{
	return [[self class] isEqual:[obj class]];
}

@end
