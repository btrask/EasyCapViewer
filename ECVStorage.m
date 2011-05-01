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
#import "ECVStorage.h"

// Models/Pipes
#import "ECVPipe.h"

@implementation ECVStorage

#pragma mark -ECVStorage

- (BOOL)isPlaying
{
	return _playing;
}
- (void)setPlaying:(BOOL)flag
{
	if(_playing == flag) return;
	_playing = flag;
	if(flag) [self play];
	for(ECVPipe *const pipe in [self pipes]) [pipe setPlaying:flag];
	if(!flag) [self stop];
}

#pragma mark -

- (NSArray *)pipes
{
	return [[_pipes copy] autorelease];
}
- (void)addPipe:(id)pipe
{
	[_pipes addObject:pipe];
	[pipe setStorage:self];
}
- (void)removePipe:(id)pipe
{
	[pipe setStorage:nil];
	[_pipes removeObjectIdenticalTo:pipe];
}

#pragma mark -

- (void)play {}
- (void)stop {}

#pragma mark -NSObject

- (id)init
{
	if((self = [super init])) {
		_pipes = [[NSMutableArray alloc] init];
	}
	return self;
}
- (void)dealloc
{
	[_pipes release];
	[super dealloc];
}

@end
