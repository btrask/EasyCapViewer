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
#import "ECVCaptureDocument.h"

// Models/Storage/Video
#import "ECVVideoStorage.h"

// Controllers
#import "ECVCaptureController.h"

// Other Sources
#import "ECVReadWriteLock.h"

@implementation ECVCaptureDocument

#pragma mark -ECVCaptureDocument

- (BOOL)isPlaying
{
	return /*[_audioStorage isPlaying] || */[_videoStorage isPlaying];
}
- (void)setPlaying:(BOOL)flag
{
	if([self isPlaying] == flag) return;
//	[_audioStorage setPlaying:flag];
	[_videoStorage setPlaying:flag];
	if(flag) [self play];
	else [self stop];
}

#pragma mark -

- (ECVVideoStorage *)videoStorage
{
	return [[_videoStorage retain] autorelease];
}

#pragma mark -

- (NSArray *)receivers
{
	return [[_receivers copy] autorelease];
}
- (void)addReceiver:(id<ECVAVReceiving>)receiver
{
	[_lock writeLock];
	[_receivers addObject:receiver];
	[_lock unlock];
}
- (void)removeReceiver:(id<ECVAVReceiving>)receiver
{
	[_lock writeLock];
	[_receivers removeObjectIdenticalTo:receiver];
	[_lock unlock];
}

#pragma mark -

- (void)play
{
	[_receivers makeObjectsPerformSelector:@selector(play)];
}
- (void)stop
{
	[_receivers makeObjectsPerformSelector:@selector(stop)];
}

#pragma mark -NSDocument

- (void)makeWindowControllers
{
	ECVCaptureController *const controller = [[[ECVCaptureController alloc] init] autorelease];
	[self addWindowController:controller];
	[self addReceiver:controller];
}
- (NSString *)displayName
{
	return [[NSBundle mainBundle] objectForInfoDictionaryKey:(NSString *)kCFBundleNameKey];
}
- (void)close
{
	[self setPlaying:NO];
	[super close];
}

#pragma mark -NSObject

- (id)init
{
	if((self = [super init])) {
//		_audioStorage = [[ECVAudioStorage alloc] init];
//		[_audioStorage setDelegate:self];
		_videoStorage = [[ECVVideoStorage alloc] init];
		[_videoStorage setDelegate:self];
		_lock = [[ECVReadWriteLock alloc] init];
		_receivers = [[NSMutableArray alloc] init];
	}
	return self;
}
- (void)dealloc
{
	[self setPlaying:NO];
//	[_audioStorage setDelegate:nil];
	[_videoStorage setDelegate:nil];
//	[_audioStorage release];
	[_videoStorage release];
	[_lock release];
	[_receivers release];
	[super dealloc];
}

#pragma mark -<ECVAudioStorageDelegate>

// TODO: Some sort of delegate method.

#pragma mark -<ECVVideoStorageDelegate>

- (void)videoStorage:(ECVVideoStorage *)storage didFinishFrame:(ECVVideoFrame *)frame
{
	[_lock readLock];
	[_receivers makeObjectsPerformSelector:@selector(receiveVideoFrame:) withObject:frame];
	[_lock unlock];
}

@end
