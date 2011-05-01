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
#import "ECVSource.h"

NSString *const ECVSourcesDidChangeNotification = @"ECVSourcesDidChange";

static CFMutableArrayRef ECVSources = NULL;
static NSDictionary *ECVSourceClasses = nil;

@implementation ECVSource

#pragma mark +ECVSource

+ (void)registerClass {}
+ (NSArray *)sources
{
	return [NSArray arrayWithArray:(NSArray *)ECVSources];
}
+ (NSDictionary *)sourceDictionary
{
	return [ECVSourceClasses objectForKey:NSStringFromClass(self)];
}

#pragma mark +NSObject

+ (void)initialize
{
	if([ECVSource class] != self) return;
	ECVSources = CFArrayCreateMutable(kCFAllocatorDefault, 0, NULL);
	ECVSourceClasses = [[NSDictionary alloc] initWithContentsOfFile:[[NSBundle bundleForClass:self] pathForResource:@"ECVSources" ofType:@"plist"]];
	for(NSString *const className in ECVSourceClasses) [NSClassFromString(className) registerClass];
}

#pragma mark -ECVSource

- (BOOL)isActive
{
	return _active;
}
- (void)setActive:(BOOL)flag
{
	if(_active == flag) return;
	_active = flag;
	if(flag) {
		[self retain];
		[self activate];
	} else {
		[self deactivate];
		[self release];
	}
	// TODO: Perhaps post ECVSourcesDidChangeNotification too.
}

#pragma mark -

- (void)activate
{
	if([self isPlaying]) [self play];
}
- (void)deactivate
{
	if([self isPlaying]) [self stop];
}

#pragma mark -

- (void)play {}
- (void)stop {}

#pragma mark -ECVSource(ECVFromPipe)

- (BOOL)isPlaying
{
	return !!_playCount;
}
- (void)setPlaying:(BOOL)flag
{
	if(flag) {
		if(!_playCount++ && [self isActive]) [self play];
	} else {
		NSAssert(_playCount, @"Source must be playing before being stopped.");
		if(!--_playCount && [self isActive]) [self stop];
	}
}

#pragma mark -NSObject

- (id)init
{
	if((self = [super init])) {
		CFArrayAppendValue(ECVSources, self);
	}
	return self;
}
- (void)dealloc
{
	NSAssert(![self isPlaying], @"Source must be stopped before being released.");
	CFIndex const i = CFArrayGetFirstIndexOfValue(ECVSources, CFRangeMake(0, CFArrayGetCount(ECVSources)), self);
	if(kCFNotFound != i) {
		CFArrayRemoveValueAtIndex(ECVSources, i);
		[[NSNotificationCenter defaultCenter] postNotificationName:ECVSourcesDidChangeNotification object:[ECVSource class]];
	}
	[super dealloc];
}

#pragma mark -<NSObject>

- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@: %p '%@'>", [self class], self, [self name]];
}

@end
