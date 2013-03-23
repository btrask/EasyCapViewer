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
#import <IOKit/usb/IOUSBLib.h>

// Models
#import "ECVCaptureDocument.h"

// Controllers
#import "ECVConfigController.h"
#import "ECVErrorLogController.h"

// Other Sources
#import "ECVAppKitAdditions.h"
#import "ECVDebug.h"

static NSArray *ECVUSBDevices(void) // TODO: Put this somewhere better.
{
	NSMutableArray *const devices = [NSMutableArray array];
	io_iterator_t iterator = IO_OBJECT_NULL;
	ECVIOReturn(IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching(kIOUSBDeviceClassName), &iterator));
	io_service_t service = IO_OBJECT_NULL;
	while((service = IOIteratorNext(iterator))) {
		NSMutableDictionary *properties = nil;
		ECVIOReturn(IORegistryEntryCreateCFProperties(service, (CFMutableDictionaryRef *)&properties, kCFAllocatorDefault, kNilOptions));
		[properties autorelease];
		[devices addObject:[NSString stringWithFormat:@"(%04x:%04x) %@ - %@",
			[[properties objectForKey:[NSString stringWithUTF8String:kUSBVendorID]] unsignedIntValue],
			[[properties objectForKey:[NSString stringWithUTF8String:kUSBProductID]] unsignedIntValue],
			[properties objectForKey:[NSString stringWithUTF8String:kUSBVendorString]] ?: @"????",
			[properties objectForKey:[NSString stringWithUTF8String:kUSBProductString]] ?: @"????"
			]];
		IOObjectRelease(service);
	}
ECVNoDeviceError:
ECVGenericError:
	return devices;
}

static ECVController *ECVSharedController;

@interface ECVController(Private)

- (void)_userActivity;

@end

static void ECVDeviceAdded(Class deviceClass, io_iterator_t iterator)
{
	[[deviceClass devicesWithIterator:iterator] makeObjectsPerformSelector:@selector(ECV_display)];
	// Don't release the iterator because we want to continue receiving notifications.
}

@implementation ECVController

#pragma mark +ECVController

+ (id)sharedController
{
	return ECVSharedController;
}

#pragma mark -ECVController

- (IBAction)configureDevice:(id)sender
{
	[[ECVConfigController sharedConfigController] ECV_toggleWindow:sender];
}
- (IBAction)showErrorLog:(id)sender
{
	[[ECVErrorLogController sharedErrorLogController] ECV_toggleWindow:sender];
}

#pragma mark -

@synthesize notificationPort = _notificationPort;
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

- (void)noteCaptureDocumentStartedPlaying:(ECVCaptureDocument *)document
{
	[self setPlaying:YES];
}
- (void)noteCaptureDocumentStoppedPlaying:(ECVCaptureDocument *)document
{
	[self setPlaying:NO];
}

#pragma mark -

- (void)workspaceDidWake:(NSNotification *)aNotif
{
	for(NSNumber *const notif in _notifications) IOObjectRelease([notif unsignedIntValue]);
	[_notifications removeAllObjects];

	NSMutableArray *const devices = [NSMutableArray array];
	for(Class const class in [ECVCaptureDevice deviceClasses]) {
		NSDictionary *const matchingDict = [class matchingDictionary];
		io_iterator_t iterator = IO_OBJECT_NULL;
		ECVIOReturn(IOServiceAddMatchingNotification(_notificationPort, kIOFirstMatchNotification, (CFDictionaryRef)[matchingDict retain], (IOServiceMatchingCallback)ECVDeviceAdded, class, &iterator));
		[devices addObjectsFromArray:[class devicesWithIterator:iterator]];
		[_notifications addObject:[NSNumber numberWithUnsignedInt:iterator]];
ECVGenericError:
ECVNoDeviceError: (void)0;
	}
	ECVLog(ECVNotice, @"USB Devices: %@", ECVUSBDevices());
	if([devices count]) return [devices makeObjectsPerformSelector:@selector(ECV_display)];
	NSAlert *const alert = [[[NSAlert alloc] init] autorelease];
	[alert setMessageText:NSLocalizedString(@"No supported capture hardware was found.", nil)];
	[alert setInformativeText:NSLocalizedString(@"Please connect an EasyCap DC60 to your computer. Please note that the DC60+ is not supported.", nil)];
	[alert addButtonWithTitle:NSLocalizedString(@"OK", nil)];
	[alert addButtonWithTitle:NSLocalizedString(@"Show Error Log", nil)];
	if(NSAlertSecondButtonReturn == [alert runModal]) [[ECVErrorLogController sharedErrorLogController] showWindow:nil];
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
		_notificationPort = IONotificationPortCreate(kIOMasterPortDefault);
		_notifications = [[NSMutableArray alloc] init];
		CFRunLoopAddSource(CFRunLoopGetCurrent(), IONotificationPortGetRunLoopSource(_notificationPort), kCFRunLoopDefaultMode);
	}
	return self;
}
- (void)dealloc
{
	CFRunLoopRemoveSource(CFRunLoopGetCurrent(), IONotificationPortGetRunLoopSource(_notificationPort), kCFRunLoopCommonModes);
	for(NSNumber *const notif in _notifications) IOObjectRelease([notif unsignedIntValue]);

	[_notifications release];
	IONotificationPortDestroy(_notificationPort);
	[_userActivityTimer invalidate];
	[super dealloc];
}

#pragma mark -NSObject(NSNibAwaking)

- (void)awakeFromNib
{
	[[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(workspaceDidWake:) name:NSWorkspaceDidWakeNotification object:[NSWorkspace sharedWorkspace]];
	[self workspaceDidWake:nil];
}

@end

@implementation ECVCaptureDevice(ECVDisplaying)

- (void)ECV_display
{
	[self performSelector:@selector(ECV_createDocument) withObject:nil afterDelay:1.0 inModes:[NSArray arrayWithObject:(NSString *)kCFRunLoopCommonModes]]; // This is the easiest and most sensible way to ensure that the device is entirely reset before we start using it. In particular, calling SetConfiguration() causes any audio devices associated with the hardware to be lost, and we don't know if there are any or when they will be found.
}
- (void)ECV_createDocument
{
	ECVCaptureDocument *const doc = [[[ECVCaptureDocument alloc] init] autorelease];
	[doc setVideoDevice:self];
	[[NSDocumentController sharedDocumentController] addDocument:doc];
	[doc makeWindowControllers];
	[doc showWindows];
}

@end

@implementation NSError(ECVDisplaying)

- (void)ECV_display
{
	[[NSAlert alertWithError:self] runModal];
}

@end
