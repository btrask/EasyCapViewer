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
#import "ECVStreamingServer.h"

// Models
#import "ECVEncoder.h"

@implementation ECVStreamingServer

#pragma mark -ECVStreamingServer

- (ECVHTTPServer *)server
{
	return [[_server retain] autorelease];
}
- (void)setServer:(ECVHTTPServer *)server
{
	if(server == _server) return;
	[_server setDelegate:nil];
	[_server release];
	_server = [server retain];
	[_server setDelegate:self];
}
@synthesize encoder = _encoder;

#pragma mark -NSObject

- (id)init
{
	if((self = [super init])) {
		_fileHandles = [[NSMutableArray alloc] init];
	}
	return self;
}
- (void)dealloc
{
	[_server release];
	[_encoder release];
	[_fileHandles release];
	[super dealloc];
}

#pragma mark -<ECVAVReceiving>

- (void)play
{
}
- (void)stop
{
}
- (void)receiveVideoFrame:(ECVVideoFrame *)frame
{
	NSData *const data = [_encoder encodedDataWithVideoFrame:frame];
	@synchronized(self) {
		for(NSFileHandle *const handle in [[_fileHandles copy] autorelease]) {
			@try {
				[handle writeData:data];
			}
			@catch(id error) {
				[_fileHandles removeObjectIdenticalTo:handle];
			}
		}
	}
}

#pragma mark -<ECVHTTPServerDelegate>

- (void)HTTPServer:(ECVHTTPServer *)server accept:(NSSocketNativeHandle)socket
{
	NSString *const HTTPHeader =
		@"HTTP/1.0 200 OK\r\n"
		@"Pragma: no-cache\r\n"
		@"Cache-Control: no-cache\r\n"
		@"Content-Type: application/x-octet-stream\r\n"
		@"\r\n";
	NSFileHandle *const handle = [[NSFileHandle alloc] initWithFileDescriptor:socket closeOnDealloc:YES];
	[handle writeData:[HTTPHeader dataUsingEncoding:NSUTF8StringEncoding]];
	[handle writeData:[_encoder header]];
	@synchronized(self) {
		[_fileHandles addObject:handle];
	}
}

@end
