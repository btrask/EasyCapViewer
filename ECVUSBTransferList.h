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
#import <IOKit/usb/IOUSBLib.h>

typedef struct {
	IOUSBLowLatencyIsocFrame *frames;
	UInt8 *data;
} ECVUSBTransfer;

@interface ECVUSBTransferList : NSObject
{
	@private
	IOUSBInterfaceInterface300 **_interface;
	NSUInteger _numberOfTransfers;
	NSUInteger _microframesPerTransfer;
	NSUInteger _frameRequestSize;
	ECVUSBTransfer *_transfers;
}

- (id)initWithInterface:(IOUSBInterfaceInterface300 **)interface numberOfTransfers:(NSUInteger)numberOfTransfers microframesPerTransfer:(NSUInteger)microframesPerTransfer frameRequestSize:(NSUInteger)frameRequestSize;
@property(readonly) NSUInteger numberOfTransfers;
@property(readonly) NSUInteger microframesPerTransfer;
@property(readonly) NSUInteger frameRequestSize;

- (ECVUSBTransfer *)transfers;
- (ECVUSBTransfer *)transferAtIndex:(NSUInteger)i;

@end
