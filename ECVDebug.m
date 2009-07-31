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
#import "ECVDebug.h"
#include <mach/mach_port.h>

NSString *ECVIOKitErrorToString(IOReturn error)
{
#define ErrorCase(val) case (val): return [NSString stringWithUTF8String:(#val)]
	switch(error) {
		ErrorCase(kIOReturnSuccess);
		ErrorCase(kIOReturnError);
		ErrorCase(kIOReturnNoMemory);
		ErrorCase(kIOReturnNoResources);
		ErrorCase(kIOReturnIPCError);
		ErrorCase(kIOReturnNoDevice);
		ErrorCase(kIOReturnNotPrivileged);
		ErrorCase(kIOReturnBadArgument);
		ErrorCase(kIOReturnLockedRead);
		ErrorCase(kIOReturnLockedWrite);
		ErrorCase(kIOReturnExclusiveAccess);
		ErrorCase(kIOReturnBadMessageID);
		ErrorCase(kIOReturnUnsupported);
		ErrorCase(kIOReturnVMError);
		ErrorCase(kIOReturnInternalError);
		ErrorCase(kIOReturnIOError);
		ErrorCase(kIOReturnCannotLock);
		ErrorCase(kIOReturnNotOpen);
		ErrorCase(kIOReturnNotReadable);
		ErrorCase(kIOReturnNotWritable);
		ErrorCase(kIOReturnNotAligned);
		ErrorCase(kIOReturnBadMedia);
		ErrorCase(kIOReturnStillOpen);
		ErrorCase(kIOReturnRLDError);
		ErrorCase(kIOReturnDMAError);
		ErrorCase(kIOReturnBusy);
		ErrorCase(kIOReturnTimeout);
		ErrorCase(kIOReturnOffline);
		ErrorCase(kIOReturnNotReady);
		ErrorCase(kIOReturnNotAttached);
		ErrorCase(kIOReturnNoChannels);
		ErrorCase(kIOReturnNoSpace);
		ErrorCase(kIOReturnPortExists);
		ErrorCase(kIOReturnCannotWire);
		ErrorCase(kIOReturnNoInterrupt);
		ErrorCase(kIOReturnNoFrames);
		ErrorCase(kIOReturnMessageTooLarge);
		ErrorCase(kIOReturnNotPermitted);
		ErrorCase(kIOReturnNoPower);
		ErrorCase(kIOReturnNoMedia);
		ErrorCase(kIOReturnUnformattedMedia);
		ErrorCase(kIOReturnUnsupportedMode);
		ErrorCase(kIOReturnUnderrun);
		ErrorCase(kIOReturnOverrun);
		ErrorCase(kIOReturnDeviceError);
		ErrorCase(kIOReturnNoCompletion);
		ErrorCase(kIOReturnAborted);
		ErrorCase(kIOReturnNoBandwidth);
		ErrorCase(kIOReturnNotResponding);
		ErrorCase(kIOReturnIsoTooOld);
		ErrorCase(kIOReturnIsoTooNew);
		ErrorCase(kIOReturnNotFound);
		ErrorCase(kIOReturnInvalid);
		ErrorCase(kIOUSBUnknownPipeErr);
		ErrorCase(kIOUSBTooManyPipesErr);
		ErrorCase(kIOUSBNoAsyncPortErr);
		ErrorCase(kIOUSBNotEnoughPipesErr);
		ErrorCase(kIOUSBNotEnoughPowerErr);
		ErrorCase(kIOUSBEndpointNotFound);
		ErrorCase(kIOUSBConfigNotFound);
		ErrorCase(kIOUSBTransactionTimeout);
		ErrorCase(kIOUSBTransactionReturned);
		ErrorCase(kIOUSBPipeStalled);
		ErrorCase(kIOUSBInterfaceNotFound);
		ErrorCase(kIOUSBLinkErr);
		ErrorCase(kIOUSBNotSent2Err);
		ErrorCase(kIOUSBNotSent1Err);
		ErrorCase(kIOUSBBufferUnderrunErr);
		ErrorCase(kIOUSBBufferOverrunErr);
		ErrorCase(kIOUSBReserved2Err);
		ErrorCase(kIOUSBReserved1Err);
		ErrorCase(kIOUSBWrongPIDErr);
		ErrorCase(kIOUSBPIDCheckErr);
		ErrorCase(kIOUSBDataToggleErr);
		ErrorCase(kIOUSBBitstufErr);
		ErrorCase(kIOUSBCRCErr);
		ErrorCase(kIOUSBLowLatencyBufferNotPreviouslyAllocated);
		ErrorCase(kIOUSBLowLatencyFrameListNotPreviouslyAllocated);
	}
	return [NSString stringWithFormat:@"Unknown error %d (code:0x%x sub:0x%x system:0x%x)", error, err_get_code(error), err_get_sub(error), err_get_system(error)];
}
