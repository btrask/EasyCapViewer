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
#import "BTUserDefaults.h"

// Other Sources
#import "ECVFoundationAdditions.h"

static NSTimeInterval const BTSynchronizationDelay = 5.0;

@interface BTUserDefaults(Private)

- (void)_synchronize;

@end

@implementation BTUserDefaults

#pragma mark -BTUserDefaults

- (id)initWithSuite:(NSString *)suite
{
	return [self initWithSuites:[NSArray arrayWithObject:suite]];
}
- (id)initWithSuites:(NSArray *)suites
{
	return [self initWithSuites:suites user:(NSString *)kCFPreferencesCurrentUser host:(NSString *)kCFPreferencesAnyHost];
}
- (id)initWithSuites:(NSArray *)suites user:(NSString *)username host:(NSString *)hostname
{
	if((self = [super init])) {
		_suites = [suites copy];
		_host = [hostname copy];
		_user = [username copy];
		_defaults = [[NSMutableDictionary alloc] init];

		[NSApp ECV_addObserver:self selector:@selector(synchronize) name:NSApplicationWillTerminateNotification];
		[NSApp ECV_addObserver:self selector:@selector(synchronize) name:NSApplicationDidResignActiveNotification]; // Also works when hiding.
		[[[NSWorkspace sharedWorkspace] notificationCenter]  addObserver:self selector:@selector(synchronize) name:NSWorkspaceWillSleepNotification object:[NSWorkspace sharedWorkspace]];
		[[[NSWorkspace sharedWorkspace] notificationCenter]  addObserver:self selector:@selector(synchronize) name:NSWorkspaceWillPowerOffNotification object:[NSWorkspace sharedWorkspace]];
	}
	return self;
}

#pragma mark -

- (id)objectForKey:(NSString *)defaultName
{
	id val = nil;
	for(NSString *const suite in _suites) {
		val = [(id)CFPreferencesCopyValue((CFStringRef)defaultName, (CFStringRef)suite, (CFStringRef)_user, (CFStringRef)_host) autorelease];
		if(val) break;
	}
	if(!val) val = [[[_defaults objectForKey:defaultName] copy] autorelease];
	return val;
}
- (void)setObject:(id)value forKey:(NSString *)defaultName
{
	NSAssert([_suites count], @"BTUserDefaults object must have at least one suite before values can be set");
	CFPreferencesSetValue((CFStringRef)defaultName, (CFPropertyListRef)value, (CFStringRef)[_suites objectAtIndex:0], (CFStringRef)_user, (CFStringRef)_host);
	[self _synchronize];
}
- (void)removeObjectForKey:(NSString *)defaultName
{
	NSAssert([_suites count], @"BTUserDefaults object must have at least one suite before values can be removed");
	CFPreferencesSetValue((CFStringRef)defaultName, NULL, (CFStringRef)[_suites objectAtIndex:0], (CFStringRef)_user, (CFStringRef)_host);
	[self _synchronize];
}

#pragma mark -

- (NSInteger)integerForKey:(NSString *)defaultName
{
	NSNumber *const obj = [self objectForKey:defaultName];
	return obj ? [obj integerValue] : 0;
}
- (float)floatForKey:(NSString *)defaultName
{
	NSNumber *const obj = [self objectForKey:defaultName];
	return obj ? [obj floatValue] : 0.0f;
}
- (double)doubleForKey:(NSString *)defaultName
{
	NSNumber *const obj = [self objectForKey:defaultName];
	return obj ? [obj doubleValue] : 0.0;
}
- (BOOL)boolForKey:(NSString *)defaultName
{
	NSNumber *const obj = [self objectForKey:defaultName];
	return obj ? [obj boolValue] : NO;
}

#pragma mark -

- (void)setInteger:(NSInteger)value forKey:(NSString *)defaultName
{
	[self setObject:[NSNumber numberWithInteger:value] forKey:defaultName];
}
- (void)setFloat:(float)value forKey:(NSString *)defaultName
{
	[self setObject:[NSNumber numberWithFloat:value] forKey:defaultName];
}
- (void)setDouble:(double)value forKey:(NSString *)defaultName
{
	[self setObject:[NSNumber numberWithDouble:value] forKey:defaultName];
}
- (void)setBool:(BOOL)value forKey:(NSString *)defaultName
{
	[self setObject:[NSNumber numberWithBool:value] forKey:defaultName];
}

#pragma mark -

- (void)registerDefaults:(NSDictionary *)registrationDictionary
{
	[_defaults addEntriesFromDictionary:registrationDictionary];
}

#pragma mark -

- (BOOL)synchronize
{
	BOOL success = YES;
	if(_syncTimer) {
		for(NSString *const suite in _suites) {
			if(!CFPreferencesSynchronize((CFStringRef)suite, (CFStringRef)_user, (CFStringRef)_host)) success = NO;
		}
		[[NSProcessInfo processInfo] ECV_enableSuddenTermination];
		[_syncTimer invalidate];
		[_syncTimer release];
		_syncTimer = nil;
		if(!success) [self _synchronize];
	}
	return success;
}

#pragma mark -BTUserDefaults(Private)

- (void)_synchronize
{
	if(_syncTimer) return;
	if(BTSynchronizationDelay > 0.0) {
		[[NSProcessInfo processInfo] ECV_disableSuddenTermination];
		_syncTimer = [[NSTimer timerWithTimeInterval:BTSynchronizationDelay target:self selector:@selector(synchronize) userInfo:nil repeats:NO] retain];
		[[NSRunLoop mainRunLoop] addTimer:_syncTimer forMode:NSRunLoopCommonModes];
	} else {
		[self synchronize];
	}
}

#pragma mark -NSObject

- (id)init
{
	return [self initWithSuite:[[NSBundle mainBundle] bundleIdentifier]];
}
- (void)dealloc
{
	[[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[self synchronize];
	[_suites release];
	[_host release];
	[_user release];
	[_defaults release];
	[super dealloc];
}

@end
