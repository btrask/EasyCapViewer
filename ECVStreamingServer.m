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

enum {
	ECVRunCondition,
	ECVWaitCondition,
};

@interface ECVStreamingServer(Private)

- (void)_receive;
- (void)_sendVideoFrame:(ECVVideoFrame *)frame toFileHandles:(NSArray *)fileHandles;

@end

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

#pragma mark -ECVStreamingServer(Private)

- (void)_receive
{
	NSAutoreleasePool *const pool = [[NSAutoreleasePool alloc] init];
	[_receiveThreadLock lock];

	BOOL receive = YES;
	while(receive) {
		NSAutoreleasePool *const innerPool = [[NSAutoreleasePool alloc] init];

		[_receiveLock lockWhenCondition:ECVRunCondition];
		NSArray *const videoFrames = [_videoFrames autorelease];
		_videoFrames = [[NSMutableArray alloc] init];
		NSArray *const fileHandles = [[_fileHandles copy] autorelease];
		if(!_receive) receive = NO;
		[_receiveLock unlockWithCondition:ECVWaitCondition];

		for(ECVVideoFrame *const frame in videoFrames) [self _sendVideoFrame:frame toFileHandles:fileHandles];

		[innerPool drain];
	}

	[_receiveThreadLock unlock];
	[pool drain];
}
- (void)_sendVideoFrame:(ECVVideoFrame *)frame toFileHandles:(NSArray *)fileHandles
{
	NSData *const data = [_encoder encodedDataWithVideoFrame:frame];
	for(NSFileHandle *const handle in fileHandles) {
		@try {
			[handle writeData:data];
		}
		@catch(id error) {
			[_receiveLock lock];
			[_fileHandles removeObjectIdenticalTo:handle];
			[_receiveLock unlock];
		}
	}
}

#pragma mark -NSObject

- (id)init
{
	if((self = [super init])) {
		_receiveThreadLock = [[NSLock alloc] init];
		_receiveLock = [[NSConditionLock alloc] init];
		_videoFrames = [[NSMutableArray alloc] init];
		_fileHandles = [[NSMutableArray alloc] init];
	}
	return self;
}
- (void)dealloc
{
	[_server release];
	[_encoder release];
	[_receiveThreadLock release];
	[_receiveLock release];
	[_videoFrames release];
	[_fileHandles release];
	[super dealloc];
}

#pragma mark -<ECVAVReceiving>

- (void)play
{
	[_receiveLock lock];
	_receive = YES;
	[_receiveLock unlock];
	[NSThread detachNewThreadSelector:@selector(_receive) toTarget:self withObject:nil];
}
- (void)stop
{
	[_receiveLock lock];
	[_videoFrames removeAllObjects];
	_receive = NO;
	[_receiveLock unlockWithCondition:ECVRunCondition];
}
- (void)receiveVideoFrame:(ECVVideoFrame *)frame
{
	[_receiveLock lock];
	if(_receive) [_videoFrames addObject:frame];
	[_receiveLock unlockWithCondition:ECVRunCondition];
}

#pragma mark -<ECVHTTPServerDelegate>

- (void)HTTPServer:(ECVHTTPServer *)server accept:(NSSocketNativeHandle)socket
{
	NSString *const HTTPHeader = [NSString stringWithFormat:
		@"HTTP/1.0 200 OK\r\n"
		@"Pragma: no-cache\r\n"
		@"Cache-Control: no-cache\r\n"
		@"Content-Type: %@\r\n"
		@"\r\n", [_encoder MIMEType]];
	NSLog(@"%@", HTTPHeader);
	int flag = YES;
	if(setsockopt(socket, SOL_SOCKET, SO_NOSIGPIPE, &flag, sizeof(flag)) != 0) {
		(void)close(socket);
		return;
	}
	NSFileHandle *const handle = [[NSFileHandle alloc] initWithFileDescriptor:socket closeOnDealloc:YES];
	[handle writeData:[HTTPHeader dataUsingEncoding:NSUTF8StringEncoding]];
	[handle writeData:[_encoder header]];
	[_receiveLock lock];
	[_fileHandles addObject:handle];
	[_receiveLock unlock];
}

@end
