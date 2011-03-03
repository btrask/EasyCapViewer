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
// Models
@class ECVCaptureDevice;

@interface ECVController : NSDocumentController
{
	@private
	IONotificationPortRef _notificationPort;
	NSMutableArray *_notifications;
	NSUInteger _playCount;
	NSTimer *_userActivityTimer;
}

+ (id)sharedController;

- (IBAction)configureDevice:(id)sender;
- (IBAction)showErrorLog:(id)sender;

@property(readonly) IONotificationPortRef notificationPort;
@property(nonatomic, assign) BOOL playing;

- (void)noteCaptureDeviceStartedPlaying:(ECVCaptureDevice *)device;
- (void)noteCaptureDeviceStoppedPlaying:(ECVCaptureDevice *)device;

- (void)workspaceDidWake:(NSNotification *)aNotif;

@end
