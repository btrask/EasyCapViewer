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
#import <mach/mach_port.h>
#import <IOKit/usb/IOUSBLib.h>

// Controllers
#import "ECVErrorLogController.h"

void ECVLog(ECVErrorLevel level, NSString *format, ...)
{
	va_list arguments;
	va_start(arguments, format);
	[[ECVErrorLogController sharedErrorLogController] logLevel:level format:format arguments:arguments];
	va_end(arguments);
}

#pragma mark -

#define ERROR_CASE(val) case (val): return [NSString stringWithUTF8String:#val];

NSString *ECVOSStatusToString(OSStatus error)
{
	switch(error) {
		/* Most are listed in MacErrors.h. There are WAY too many to define them all. */
		ERROR_CASE(noErr)
		ERROR_CASE(codecErr)
	}
	return [NSString stringWithFormat:@"Unknown error %d", error];
}
NSString *ECVIOKitErrorToString(IOReturn error)
{
	switch(error) {
		ERROR_CASE(kIOReturnSuccess)
		ERROR_CASE(kIOReturnError)
		ERROR_CASE(kIOReturnNoMemory)
		ERROR_CASE(kIOReturnNoResources)
		ERROR_CASE(kIOReturnIPCError)
		ERROR_CASE(kIOReturnNoDevice)
		ERROR_CASE(kIOReturnNotPrivileged)
		ERROR_CASE(kIOReturnBadArgument)
		ERROR_CASE(kIOReturnLockedRead)
		ERROR_CASE(kIOReturnLockedWrite)
		ERROR_CASE(kIOReturnExclusiveAccess)
		ERROR_CASE(kIOReturnBadMessageID)
		ERROR_CASE(kIOReturnUnsupported)
		ERROR_CASE(kIOReturnVMError)
		ERROR_CASE(kIOReturnInternalError)
		ERROR_CASE(kIOReturnIOError)
		ERROR_CASE(kIOReturnCannotLock)
		ERROR_CASE(kIOReturnNotOpen)
		ERROR_CASE(kIOReturnNotReadable)
		ERROR_CASE(kIOReturnNotWritable)
		ERROR_CASE(kIOReturnNotAligned)
		ERROR_CASE(kIOReturnBadMedia)
		ERROR_CASE(kIOReturnStillOpen)
		ERROR_CASE(kIOReturnRLDError)
		ERROR_CASE(kIOReturnDMAError)
		ERROR_CASE(kIOReturnBusy)
		ERROR_CASE(kIOReturnTimeout)
		ERROR_CASE(kIOReturnOffline)
		ERROR_CASE(kIOReturnNotReady)
		ERROR_CASE(kIOReturnNotAttached)
		ERROR_CASE(kIOReturnNoChannels)
		ERROR_CASE(kIOReturnNoSpace)
		ERROR_CASE(kIOReturnPortExists)
		ERROR_CASE(kIOReturnCannotWire)
		ERROR_CASE(kIOReturnNoInterrupt)
		ERROR_CASE(kIOReturnNoFrames)
		ERROR_CASE(kIOReturnMessageTooLarge)
		ERROR_CASE(kIOReturnNotPermitted)
		ERROR_CASE(kIOReturnNoPower)
		ERROR_CASE(kIOReturnNoMedia)
		ERROR_CASE(kIOReturnUnformattedMedia)
		ERROR_CASE(kIOReturnUnsupportedMode)
		ERROR_CASE(kIOReturnUnderrun)
		ERROR_CASE(kIOReturnOverrun)
		ERROR_CASE(kIOReturnDeviceError)
		ERROR_CASE(kIOReturnNoCompletion)
		ERROR_CASE(kIOReturnAborted)
		ERROR_CASE(kIOReturnNoBandwidth)
		ERROR_CASE(kIOReturnNotResponding)
		ERROR_CASE(kIOReturnIsoTooOld)
		ERROR_CASE(kIOReturnIsoTooNew)
		ERROR_CASE(kIOReturnNotFound)
		ERROR_CASE(kIOReturnInvalid)

		ERROR_CASE(kIOUSBUnknownPipeErr)
		ERROR_CASE(kIOUSBTooManyPipesErr)
		ERROR_CASE(kIOUSBNoAsyncPortErr)
		ERROR_CASE(kIOUSBNotEnoughPipesErr)
		ERROR_CASE(kIOUSBNotEnoughPowerErr)
		ERROR_CASE(kIOUSBEndpointNotFound)
		ERROR_CASE(kIOUSBConfigNotFound)
		ERROR_CASE(kIOUSBTransactionTimeout)
		ERROR_CASE(kIOUSBTransactionReturned)
		ERROR_CASE(kIOUSBPipeStalled)
		ERROR_CASE(kIOUSBInterfaceNotFound)
		ERROR_CASE(kIOUSBLowLatencyBufferNotPreviouslyAllocated)
		ERROR_CASE(kIOUSBLowLatencyFrameListNotPreviouslyAllocated)
		ERROR_CASE(kIOUSBHighSpeedSplitError)
		ERROR_CASE(kIOUSBSyncRequestOnWLThread)
		ERROR_CASE(kIOUSBDeviceNotHighSpeed)
		ERROR_CASE(kIOUSBLinkErr)
		ERROR_CASE(kIOUSBNotSent2Err)
		ERROR_CASE(kIOUSBNotSent1Err)
		ERROR_CASE(kIOUSBBufferUnderrunErr)
		ERROR_CASE(kIOUSBBufferOverrunErr)
		ERROR_CASE(kIOUSBReserved2Err)
		ERROR_CASE(kIOUSBReserved1Err)
		ERROR_CASE(kIOUSBWrongPIDErr)
		ERROR_CASE(kIOUSBPIDCheckErr)
		ERROR_CASE(kIOUSBDataToggleErr)
		ERROR_CASE(kIOUSBBitstufErr)
		ERROR_CASE(kIOUSBCRCErr)
	}
	return [NSString stringWithFormat:@"Unknown IOReturn %d (Code: 0x%x; Sub: 0x%x; System: 0x%x)", error, err_get_code(error), err_get_sub(error), err_get_system(error)];
}
NSString *ECVCVReturnToString(CVReturn error)
{
	switch(error) {
		ERROR_CASE(kCVReturnSuccess)
		ERROR_CASE(kCVReturnError)
		ERROR_CASE(kCVReturnInvalidArgument)
		ERROR_CASE(kCVReturnAllocationFailed)
		ERROR_CASE(kCVReturnInvalidDisplay)
		ERROR_CASE(kCVReturnDisplayLinkAlreadyRunning)
		ERROR_CASE(kCVReturnDisplayLinkNotRunning)
		ERROR_CASE(kCVReturnDisplayLinkCallbacksNotSet)
		ERROR_CASE(kCVReturnInvalidPixelFormat)
		ERROR_CASE(kCVReturnInvalidSize)
		ERROR_CASE(kCVReturnInvalidPixelBufferAttributes)
		ERROR_CASE(kCVReturnPixelBufferNotOpenGLCompatible)
		ERROR_CASE(kCVReturnPoolAllocationFailed)
		ERROR_CASE(kCVReturnInvalidPoolAttributes)
	}
	return [NSString stringWithFormat:@"Unknown CVReturn %d", error];
}
NSString *ECVOpenGLErrorToString(GLenum error)
{
	switch(error) {
		ERROR_CASE(GL_NO_ERROR)
		ERROR_CASE(GL_INVALID_ENUM)
		ERROR_CASE(GL_INVALID_VALUE)
		ERROR_CASE(GL_INVALID_OPERATION)
		ERROR_CASE(GL_STACK_OVERFLOW)
		ERROR_CASE(GL_STACK_UNDERFLOW)
		ERROR_CASE(GL_OUT_OF_MEMORY)
	}
	return [NSString stringWithFormat:@"Unknown OpenGL error 0x%03x", error];
}
