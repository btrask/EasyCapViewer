/* Copyright (c) 2009, Ben Trask
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
#import "ECVController.h"
//#import <IOKit/usb/IOUSBLib.h>

// Models
#import "ECVCaptureDocument.h"

// Controllers
#import "ECVOpenController.h"
#import "ECVConfigController.h"
#import "ECVErrorLogController.h"

// Other Sources
#import "ECVAppKitAdditions.h"
#import "ECVDebug.h"

static ECVController *ECVSharedController;

//@interface ECVCaptureDevice(ECVDisplaying)
//
//- (void)ECV_display;
//
//@end

@interface NSError(ECVDisplaying)

- (void)ECV_display;

@end

@interface ECVController(Private)

- (void)_userActivity;

@end

static void ECVSourceAdded(Class deviceClass, io_iterator_t iterator)
{
//	[[deviceClass devicesWithIterator:iterator] makeObjectsPerformSelector:@selector(ECV_display)];
	// Don't release the iterator because we want to continue receiving notifications.
}

@implementation ECVController

#pragma mark +ECVController

+ (id)sharedController
{
	return ECVSharedController;
}

#pragma mark -ECVController

//- (IBAction)configureDevice:(id)sender
//{
//	[[ECVConfigController sharedConfigController] ECV_toggleWindow:sender];
//}
- (IBAction)showErrorLog:(id)sender
{
	[[ECVErrorLogController sharedErrorLogController] ECV_toggleWindow:sender];
}

#pragma mark -

//@synthesize notificationPort = _notificationPort;
- (BOOL)playing
{
	return !!_playCount;
}
- (void)setPlaying:(BOOL)flag
{
	if(flag) {
		if(_playCount < NSUIntegerMax) _playCount++;
		if(1 == _playCount) _userActivityTimer = [NSTimer scheduledTimerWithTimeInterval:30.0f target:self selector:@selector(_userActivity) userInfo:nil repeats:YES];
	} else {
		NSParameterAssert(_playCount);
		_playCount--;
		if(!_playCount) {
			[_userActivityTimer invalidate];
			_userActivityTimer = nil;
		}
	}
}

#pragma mark -

//- (void)noteCaptureDeviceStartedPlaying:(ECVCaptureDevice *)device
//{
//	[self setPlaying:YES];
//}
//- (void)noteCaptureDeviceStoppedPlaying:(ECVCaptureDevice *)device
//{
//	[self setPlaying:NO];
//}

#pragma mark -

- (void)workspaceDidWake:(NSNotification *)aNotif
{
//	for(NSNumber *const notif in _notifications) IOObjectRelease([notif unsignedIntValue]);
//	[_notifications removeAllObjects];
//
//	NSMutableArray *const devices = [NSMutableArray array];
//	for(Class const class in [ECVCaptureDevice deviceClasses]) {
//		NSDictionary *const matchingDict = [class matchingDictionary];
//		io_iterator_t iterator = IO_OBJECT_NULL;
//		ECVIOReturn(IOServiceAddMatchingNotification(_notificationPort, kIOFirstMatchNotification, (CFDictionaryRef)[matchingDict retain], (IOServiceMatchingCallback)ECVSourceAdded, class, &iterator));
//		[devices addObjectsFromArray:[class devicesWithIterator:iterator]];
//		[_notifications addObject:[NSNumber numberWithUnsignedInt:iterator]];
//ECVGenericError:
//ECVNoDeviceError: 0;
//	}
//	if([devices count]) return [devices makeObjectsPerformSelector:@selector(ECV_display)];
//	NSAlert *const alert = [[[NSAlert alloc] init] autorelease];
//	[alert setMessageText:NSLocalizedString(@"No supported capture hardware was found.", nil)];
//	[alert setInformativeText:NSLocalizedString(@"Please connect an EasyCap DC60 to your computer. Please note that the DC60+ is not supported.", nil)];
//	[alert addButtonWithTitle:NSLocalizedString(@"OK", nil)];
//	[alert runModal];
}

#pragma mark -ECVController(Private)

- (void)_userActivity
{
	UpdateSystemActivity(UsrActivity);
}

#pragma mark -NSObject

- (id)init
{
	if((self = [super init])) {
		if(!ECVSharedController) ECVSharedController = [self retain];
//		_notificationPort = IONotificationPortCreate(kIOMasterPortDefault);
//		_notifications = [[NSMutableArray alloc] init];
//		CFRunLoopAddSource(CFRunLoopGetCurrent(), IONotificationPortGetRunLoopSource(_notificationPort), kCFRunLoopDefaultMode);
	}
	return self;
}
- (void)dealloc
{
//	CFRunLoopRemoveSource(CFRunLoopGetCurrent(), IONotificationPortGetRunLoopSource(_notificationPort), kCFRunLoopCommonModes);
//	for(NSNumber *const notif in _notifications) IOObjectRelease([notif unsignedIntValue]);
//
//	[_notifications release];
//	IONotificationPortDestroy(_notificationPort);
	[_userActivityTimer invalidate];
	[super dealloc];
}

#pragma mark -NSObject(NSNibAwaking)

- (void)awakeFromNib
{
	[[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(workspaceDidWake:) name:NSWorkspaceDidWakeNotification object:[NSWorkspace sharedWorkspace]];
	[self workspaceDidWake:nil];
}

#pragma mark -<NSApplicationDelegate>

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
	[(ECVOpenController *)[[[ECVOpenController alloc] init] autorelease] runModal];
}

@end

//@implementation ECVCaptureDevice(ECVDisplaying)
//
//- (void)ECV_display
//{
//	[[NSDocumentController sharedDocumentController] addDocument:self];
//	[self makeWindowControllers];
//	[self showWindows];
//}
//
//@end

//@implementation NSError(ECVDisplaying)
//
//- (void)ECV_display
//{
//	[[NSAlert alertWithError:self] runModal];
//}
//
//@end
