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
enum {
	ECVNotice,
	ECVWarning,
	ECVError,
	ECVCritical,
};
typedef NSUInteger ECVErrorLevel;

extern void ECVLog(ECVErrorLevel level, NSString *format, ...) __attribute__((format(__NSString__, 2, 3)));
extern NSString *ECVOSStatusToString(OSStatus error);
extern NSString *ECVIOKitErrorToString(IOReturn error);
extern NSString *ECVCVReturnToString(CVReturn error);
extern NSString *ECVOpenGLErrorToString(GLenum error);
extern NSString *ECVErrnoToString(int error);

#define ECVOSStatus(x) do {\
	OSStatus const __e = (x);\
	if(noErr == __e) break;\
	ECVLog(ECVError, @"%s:%d %s: %@", __PRETTY_FUNCTION__, __LINE__, #x, ECVOSStatusToString(__e));\
} while(NO)

#define ECVOSErr(x) ECVOSStatus((OSStatus)(x))
#define ECVComponentResult(x) ECVOSStatus((OSSTatus)(x))

#define ECVIOReturn(x) do {\
	IOReturn const __e = (x);\
	if(kIOReturnSuccess == __e) break;\
	ECVLog(ECVWarning, @"%s:%d %s: %@", __PRETTY_FUNCTION__, __LINE__, #x, ECVIOKitErrorToString(__e));\
	if(kIOReturnNoDevice == __e) goto ECVNoDeviceError;\
	goto ECVGenericError;\
} while(NO)

#define ECVCVReturn(x) do {\
	CVReturn const __e = (x);\
	if(kCVReturnSuccess == __e) break;\
	ECVLog(ECVError, @"%s:%d %s: %@", __PRETTY_FUNCTION__, __LINE__, #x, ECVCVReturnToString(__e));\
} while(NO)

#define ECVGLError(x) do {\
	(x);\
	GLenum __e;\
	while((__e = glGetError()) != GL_NO_ERROR) ECVLog(ECVError, @"%s:%d %s: %@", __PRETTY_FUNCTION__, __LINE__, #x, ECVOpenGLErrorToString(__e));\
} while(NO)

#define ECVErrno(x) do {\
	int const __e = (x);\
	if(__e) ECVLog(ECVError, @"%s:%d: %@", __PRETTY_FUNCTION__, __LINE__, #x, ECVErrnoToString(__e));\
} while(NO)

#define ECVAssertNotReached(desc) [[NSAssertionHandler currentHandler] handleFailureInMethod:_cmd object:self file:[NSString stringWithUTF8String:__FILE__] lineNumber:__LINE__ description:(desc)]
#define ECVCAssertNotReached(desc) [[NSAssertionHandler currentHandler] handleFailureInFunction:[NSString stringWithUTF8String:__PRETTY_FUNCTION__] file:[NSString stringWithUTF8String:__FILE__] lineNumber:__LINE__ description:(desc)]
