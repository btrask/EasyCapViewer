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
#import "ECVVideoFormat.h"

@interface ECVVideoFormat(Private)

+ (void)_addFromSet:(NSMutableSet *const)set toMenu:(NSMenu *const)menu;

@end

@implementation ECVVideoFormat

+ (NSMenu *)menuWithVideoFormats:(NSSet *const)formats
{
	NSMenu *const menu = [[[NSMenu alloc] initWithTitle:@""] autorelease];
	NSMutableSet *const set = [[formats mutableCopy] autorelease];
	NSMenuItem *const label60Hz = [menu addItemWithTitle:@"60Hz" action:NULL keyEquivalent:@""];
	[ECVVideoFormat_NTSC_M _addFromSet:set toMenu:menu];
	[ECVVideoFormat_PAL_60 _addFromSet:set toMenu:menu];
	[ECVVideoFormat_NTSC_443_60Hz _addFromSet:set toMenu:menu];
	[ECVVideoFormat_PAL_M _addFromSet:set toMenu:menu];
	[ECVVideoFormat_NTSC_J _addFromSet:set toMenu:menu];
	NSMenuItem *const label50Hz = [menu addItemWithTitle:@"50Hz" action:NULL keyEquivalent:@""];
	[ECVVideoFormat_PAL_BGDHI _addFromSet:set toMenu:menu];
	[ECVVideoFormat_NTSC_443_50Hz _addFromSet:set toMenu:menu];
	[ECVVideoFormat_PAL_N _addFromSet:set toMenu:menu];
	[ECVVideoFormat_NTSC_N _addFromSet:set toMenu:menu];
	[ECVVideoFormat_SECAM _addFromSet:set toMenu:menu];
	[label60Hz setEnabled:NO];
	[label50Hz setEnabled:NO];
	return menu;
}

#pragma mark +ECVVideoFormat(Private)

+ (void)_addFromSet:(NSMutableSet *const)set toMenu:(NSMenu *const)menu
{
	ECVVideoFormat *const format = [set member:self];
	NSMenuItem *const item = [[[NSMenuItem alloc] initWithTitle:[format localizedName] action:NULL keyEquivalent:@""] autorelease];
	[item setIndentationLevel:1];
	[item setRepresentedObject:format];
	[menu addItem:item];
	[set removeObject:format];
}

#pragma mark -ECVVideoFormat

- (BOOL)is60Hz
{
	QTTime const r = [self frameRate];
	if(NSOrderedSame == QTTimeCompare(r, QTMakeTime(1001, 60000))) return YES;
	return NO;
}
- (BOOL)is50Hz
{
	QTTime const r = [self frameRate];
	if(NSOrderedSame == QTTimeCompare(r, QTMakeTime(1, 50))) return YES;
	return NO;
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

@implementation ECVCommon60HzVideoFormat
- (ECVIntegerSize)frameSize { return (ECVIntegerSize){704, 240}; }
- (BOOL)isInterlaced { return YES; }
- (BOOL)isProgressive { return NO; }
- (NSUInteger)frameGroupSize { return 2; }
- (QTTime)frameRate { return QTMakeTime(1001, 60000); }
- (BOOL)is60Hz { return YES; }
- (BOOL)is50Hz { return NO; }
@end
@implementation ECVCommon50HzVideoFormat
- (ECVIntegerSize)frameSize { return (ECVIntegerSize){704, 288}; }
- (BOOL)isInterlaced { return YES; }
- (BOOL)isProgressive { return NO; }
- (NSUInteger)frameGroupSize { return 2; }
- (QTTime)frameRate { return QTMakeTime(1, 50); }
- (BOOL)is60Hz { return NO; }
- (BOOL)is50Hz { return YES; }
@end

@implementation ECVVideoFormat_NTSC_M
- (NSString *)localizedName { return NSLocalizedString(@"NTSC", nil); }
@end
@implementation ECVVideoFormat_PAL_60
- (NSString *)localizedName { return NSLocalizedString(@"PAL-60", nil); }
@end
@implementation ECVVideoFormat_NTSC_443_60Hz
- (NSString *)localizedName { return NSLocalizedString(@"NTSC 4.43 (60Hz)", nil); }
@end
@implementation ECVVideoFormat_PAL_M
- (NSString *)localizedName { return NSLocalizedString(@"PAL-M", nil); }
@end
@implementation ECVVideoFormat_NTSC_J
- (NSString *)localizedName { return NSLocalizedString(@"NTSC-J", nil); }
@end

@implementation ECVVideoFormat_PAL_BGDHI
- (NSString *)localizedName { return NSLocalizedString(@"PAL", nil); }
@end
@implementation ECVVideoFormat_NTSC_443_50Hz
- (NSString *)localizedName { return NSLocalizedString(@"NTSC 4.43 (50Hz)", nil); }
@end
@implementation ECVVideoFormat_PAL_N
- (NSString *)localizedName { return NSLocalizedString(@"PAL-N", nil); }
@end
@implementation ECVVideoFormat_NTSC_N
- (NSString *)localizedName { return NSLocalizedString(@"NTSC-N", nil); }
@end
@implementation ECVVideoFormat_SECAM
- (NSString *)localizedName { return NSLocalizedString(@"SECAM", nil); }
@end
