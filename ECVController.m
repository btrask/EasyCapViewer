/* Copyright (c) 2009, Ben Trask
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * The names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

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

// Controllers
#import "ECVCaptureController.h"
#import "ECVConfigController.h"

// Other Sources
#import "ECVDebug.h"

NSString *const ECVGeneralErrorDomain = @"ECVGeneralErrorDomain";

static ECVController *ECVSharedController;

static void ECVDeviceAdded(Class controllerClass, io_iterator_t iterator)
{
	(void)[controllerClass deviceAddedWithIterator:iterator];
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
	[[ECVConfigController sharedConfigController] showWindow:sender];
}

#pragma mark -

@synthesize notificationPort = _notificationPort;

#pragma mark -NSObject

- (void)dealloc
{
	CFRunLoopRemoveSource(CFRunLoopGetCurrent(), IONotificationPortGetRunLoopSource(_notificationPort), kCFRunLoopCommonModes);
	IONotificationPortDestroy(_notificationPort);
	[super dealloc];
}

#pragma mark -NSObject(NSNibAwaking)

- (void)awakeFromNib
{
	if(!ECVSharedController) ECVSharedController = [self retain];
	_notificationPort = IONotificationPortCreate(kIOMasterPortDefault);
	CFRunLoopAddSource(CFRunLoopGetCurrent(), IONotificationPortGetRunLoopSource(_notificationPort), kCFRunLoopDefaultMode);
	NSArray *const types = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"ECVCaptureTypes"];
	BOOL found = NO;
	for(NSDictionary *const type in types) {
		Class const class = NSClassFromString([type objectForKey:@"ECVCaptureClass"]);
		if(!class) continue;

		NSMutableDictionary *const match = (NSMutableDictionary *)IOServiceMatching(kIOUSBDeviceClassName);
		[match setObject:[type objectForKey:@"ECVVendorID"] forKey:[NSString stringWithUTF8String:kUSBVendorID]];
		[match setObject:[type objectForKey:@"ECVProductID"] forKey:[NSString stringWithUTF8String:kUSBProductID]];
		io_iterator_t iterator = IO_OBJECT_NULL;
		ECVIOReturn(IOServiceAddMatchingNotification(_notificationPort, kIOFirstMatchNotification, (CFDictionaryRef)match, (IOServiceMatchingCallback)ECVDeviceAdded, class, &iterator));
ECVGenericError:
ECVNoDeviceError:
		if([class deviceAddedWithIterator:iterator]) found = YES;
	}
	if(found) return;
	NSAlert *const alert = [[[NSAlert alloc] init] autorelease];
	[alert setMessageText:NSLocalizedString(@"No supported capture hardware was found.", nil)];
	[alert setInformativeText:NSLocalizedString(@"Please connect an EasyCap DC60 to your computer. Please note that the DC60+ is not supported.", nil)];
	[alert addButtonWithTitle:NSLocalizedString(@"OK", nil)];
	[alert runModal];
}

@end
