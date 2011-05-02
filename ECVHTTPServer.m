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
#import "ECVHTTPServer.h"
#import <sys/socket.h>

// Other Sources
#import "ECVFoundationAdditions.h"

// Very useful article at <http://macdevcenter.com/lpt/a/6773>.

@interface ECVHTTPServer(Private)

- (void)_accept:(NSSocketNativeHandle)socket;

@end

static void ECVAccept(CFSocketRef s, CFSocketCallBackType type, NSData *address, NSSocketNativeHandle *socket, ECVHTTPServer *server)
{
	NSCParameterAssert(kCFSocketAcceptCallBack == type);
	[server _accept:*socket];
}

@implementation ECVHTTPServer

#pragma mark -ECVHTTPServer

- (id)initWithPort:(UInt16)port
{
	if((self = [super init])) {
		CFSocketContext const context = {
			.version = 0,
			.info = self,
		};
		_socket = CFSocketCreate(kCFAllocatorDefault, PF_INET, SOCK_STREAM, IPPROTO_TCP, kCFSocketAcceptCallBack, (CFSocketCallBack)ECVAccept, &context);
		if(!_socket) {
			[self release];
			return nil;
		}

		int reuseAddress = true;
		setsockopt(CFSocketGetNative(_socket), SOL_SOCKET, SO_REUSEADDR, (void *)&reuseAddress, sizeof(reuseAddress));

		struct sockaddr_in const address = {
			.sin_len = sizeof(address),
			.sin_family = AF_INET,
			.sin_port = htons(port),
			.sin_addr = {
				.s_addr = htonl(INADDR_ANY),
			},
		};
		NSData *const addressData = [NSData dataWithBytes:&address length:sizeof(address)];
		CFSocketSetAddress(_socket, (CFDataRef)addressData);

		_source = CFSocketCreateRunLoopSource(kCFAllocatorDefault, _socket, 0);
		CFRunLoopAddSource(CFRunLoopGetCurrent(), _source, kCFRunLoopCommonModes);
	}
	return self;
}

#pragma mark -

@synthesize delegate = _delegate;
- (struct sockaddr_in)address
{
	NSData *const data = [(NSData *)CFSocketCopyAddress(_socket) autorelease];
	struct sockaddr_in address = {};
	if(data) memcpy(&address, [data bytes], MIN(sizeof(address), [data length]));
	return address;
}

#pragma mark -ECVHTTPServer(Private)

- (void)_accept:(NSSocketNativeHandle)socket
{
	NSObject<ECVHTTPServerDelegate> *const delegate = [self delegate];
	if(delegate) [delegate HTTPServer:self accept:socket];
	else close(socket);
}

#pragma mark -NSObject

- (void)dealloc
{
	if(_source) {
		CFRunLoopSourceInvalidate(_source);
		CFRelease(_source);
	}
	if(_socket) {
		CFSocketInvalidate(_socket);
		CFRelease(_socket);
	}
	[super dealloc];
}

@end
