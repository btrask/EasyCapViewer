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
#import "ECVUSBTransferList.h"

// Other Sources
#import "ECVDebug.h"

@implementation ECVUSBTransferList

#pragma mark -ECVUSBTransferList

- (id)initWithInterface:(IOUSBInterfaceInterface300 **)interface numberOfTransfers:(NSUInteger)numberOfTransfers microframesPerTransfer:(NSUInteger)microframesPerTransfer frameRequestSize:(NSUInteger)frameRequestSize
{
	if((self = [super init])) {
		_interface = interface;
		(*_interface)->AddRef(_interface);
		_numberOfTransfers = numberOfTransfers;
		_microframesPerTransfer = microframesPerTransfer;
		_frameRequestSize = frameRequestSize;
		_transfers = calloc(_numberOfTransfers, sizeof(ECVUSBTransfer));
		if(!_transfers) goto bail;

        IOByteCount microframesPerTransferIOByteCount = (IOByteCount)_microframesPerTransfer;
        IOByteCount frameRequestSizeIOByteCount = (IOByteCount)_frameRequestSize;
        
		NSUInteger i;
		for(i = 0; i < _numberOfTransfers; ++i) {
			ECVUSBTransfer *const transfer = _transfers + i;
			if(kIOReturnSuccess != ECVIOReturn((*_interface)->LowLatencyCreateBuffer(_interface, (void **)&transfer->frames, sizeof(IOUSBLowLatencyIsocFrame) * microframesPerTransferIOByteCount, kUSBLowLatencyFrameListBuffer))) goto bail;
			if(kIOReturnSuccess != ECVIOReturn((*_interface)->LowLatencyCreateBuffer(_interface, (void **)&transfer->data, frameRequestSizeIOByteCount * microframesPerTransferIOByteCount, kUSBLowLatencyReadBuffer))) goto bail;
			NSUInteger j;
			for(j = 0; j < _microframesPerTransfer; ++j) {
				IOUSBLowLatencyIsocFrame *const frame = transfer->frames + j;
				frame->frStatus = kIOReturnInvalid; // Ignore them to start out.
				frame->frReqCount = _frameRequestSize;
			}
		}

	}
	return self;
bail:
	[self release];
	return nil;
}
- (NSUInteger)numberOfTransfers { return _numberOfTransfers; }
- (NSUInteger)microframesPerTransfer { return _microframesPerTransfer; }
- (NSUInteger)frameRequestSize { return _frameRequestSize; }

#pragma mark -

- (ECVUSBTransfer *)transfers
{
	return _transfers;
}
- (ECVUSBTransfer *)transferAtIndex:(NSUInteger)i
{
	NSParameterAssert(i < _numberOfTransfers);
	return _transfers + i;
}

#pragma mark -NSObject

- (void)dealloc
{
	if(_transfers) {
		NSUInteger i;
		for(i = 0; i < _numberOfTransfers; ++i) {
			if(_transfers[i].frames) (*_interface)->LowLatencyDestroyBuffer(_interface, _transfers[i].frames);
			if(_transfers[i].data) (*_interface)->LowLatencyDestroyBuffer(_interface, _transfers[i].data);
		}
		free(_transfers);
	}
	if(_interface) (*_interface)->Release(_interface);
	[super dealloc];
}

@end
