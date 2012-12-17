/* Copyright (c) 2012, Ben Trask
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE AUTHORS ''AS IS'' AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. */
#import "ECVCaptureDocument.h"

#import "ECVAudioDevice.h"
#import "ECVAudioPipe.h"
#import "ECVCaptureController.h"
#import "ECVController.h"
#import "ECVDebug.h"
#import "ECVReadWriteLock.h"

NSString *const ECVCaptureDeviceVolumeDidChangeNotification = @"ECVCaptureDeviceVolumeDidChange";

static NSString *const ECVVolumeKey = @"ECVVolume";
static NSString *const ECVAudioInputUIDKey = @"ECVAudioInputUID";
static NSString *const ECVUpconvertsFromMonoKey = @"ECVUpconvertsFromMono";

static NSString *const ECVAudioInputNone = @"ECVAudioInputNone";

@implementation ECVCaptureDocument

#pragma mark -ECVCaptureDocument

- (ECVCaptureDevice *)videoDevice
{
	return [[_videoDevice retain] autorelease];
}
- (void)setVideoDevice:(ECVCaptureDevice *const)source
{
	if(source == _videoDevice) return;
	[_videoDevice release];
	_videoDevice = [source retain];
	// TODO: Set source's target to us.
}
- (NSUserDefaults *)defaults
{
	return [_videoDevice defaults];
}

#pragma mark -

- (BOOL)isPaused
{
	return _paused;
}
- (void)setPaused:(BOOL const)flag
{
	if(!!flag == _paused) return;
	_paused = !!flag;
	if(_paused) [self stop];
	else [self play];
}
- (void)togglePaused
{
	[self setPaused:![self isPaused]];
}
- (void)play
{
	[self startAudio];
	[_videoDevice play];
	[[ECVController sharedController] noteCaptureDocumentStartedPlaying:self];
	[[self windowControllers] makeObjectsPerformSelector:@selector(startPlaying)];
}
- (void)stop
{
	[_videoDevice stop];
	[[self windowControllers] makeObjectsPerformSelector:@selector(stopPlaying)];
	[[ECVController sharedController] noteCaptureDocumentStoppedPlaying:self];
	[self stopAudio];
}

#pragma mark -

- (void)workspaceWillSleep:(NSNotification *const)aNotif
{
	// TODO: Do something.
//	[self setPausedFromUI:YES];
//	[self noteDeviceRemoved];
}

#pragma mark -

- (ECVAudioInput *)audioInput
{
	if(!_audioInput) {
		NSString *const UID = [[self defaults] objectForKey:ECVAudioInputUIDKey];
		if(!BTEqualObjects(ECVAudioInputNone, UID)) {
			if(UID) _audioInput = [[ECVAudioInput deviceWithUID:UID] retain];
			if(!_audioInput) _audioInput = [[[self videoDevice] builtInAudioInput] retain];
		}
	}
	return [[_audioInput retain] autorelease];
}
- (void)setAudioInput:(ECVAudioInput *const)input
{
	if(!BTEqualObjects(input, _audioInput)) {
		[self setPaused:YES];
		[_audioInput release];
		_audioInput = [input retain];
		[_audioPreviewingPipe release];
		_audioPreviewingPipe = nil;
		[self setPaused:NO];
	}
	if(BTEqualObjects([[self videoDevice] builtInAudioInput], input)) {
		[[self defaults] removeObjectForKey:ECVAudioInputUIDKey];
	} else if(input) {
		[[self defaults] setObject:[input UID] forKey:ECVAudioInputUIDKey];
	} else {
		[[self defaults] setObject:ECVAudioInputNone forKey:ECVAudioInputUIDKey];
	}
}
- (ECVAudioOutput *)audioOutput
{
	if(!_audioOutput) return _audioOutput = [[ECVAudioOutput defaultDevice] retain];
	return [[_audioOutput retain] autorelease];
}
- (void)setAudioOutput:(ECVAudioOutput *const)output
{
	if(BTEqualObjects(output, _audioOutput)) return;
	[self setPaused:YES];
	[_audioOutput release];
	_audioOutput = [output retain];
	[_audioPreviewingPipe release];
	_audioPreviewingPipe = nil;
	[self setPaused:NO];
}
- (BOOL)startAudio
{
	NSAssert(!_audioPreviewingPipe, @"Audio pipe should be cleared before restarting audio.");

	ECVAudioInput *const input = [self audioInput];
	ECVAudioOutput *const output = [self audioOutput];
	if(input && output) {
		ECVAudioStream *const inputStream = [[[input streams] objectEnumerator] nextObject];
		if(!inputStream) {
			ECVLog(ECVNotice, @"This device may not support audio (input: %@; stream: %@).", input, inputStream);
			return NO;
		}
		ECVAudioStream *const outputStream = [[[output streams] objectEnumerator] nextObject];
		if(!outputStream) {
			ECVLog(ECVWarning, @"Audio output could not be started (output: %@; stream: %@).", output, outputStream);
			return NO;
		}

		_audioPreviewingPipe = [[ECVAudioPipe alloc] initWithInputDescription:[inputStream basicDescription] outputDescription:[outputStream basicDescription] upconvertFromMono:[self upconvertsFromMono]];
		[_audioPreviewingPipe setVolume:_muted ? 0.0f : _volume];
		[input setDelegate:self];
		[output setDelegate:self];

		if(![input start]) {
			ECVLog(ECVWarning, @"Audio input could not be restarted (input: %@).", input);
			return NO;
		}
		if(![output start]) {
			[output stop];
			ECVLog(ECVWarning, @"Audio output could not be restarted (output: %@).", output);
			return NO;
		}
	}
	return YES;
}
- (void)stopAudio
{
	ECVAudioInput *const input = [self audioInput];
	ECVAudioOutput *const output = [self audioOutput];
	[input stop];
	[output stop];
	[input setDelegate:nil];
	[output setDelegate:nil];
	[_audioPreviewingPipe release];
	_audioPreviewingPipe = nil;
}

#pragma mark -ECVCaptureDocument<ECVAudioDeviceDelegate>

- (void)audioInput:(ECVAudioInput *)sender didReceiveBufferList:(AudioBufferList const *)bufferList atTime:(AudioTimeStamp const *)t
{
	if(sender != _audioInput) return;
	[_audioPreviewingPipe receiveInputBufferList:bufferList];
	[_windowControllersLock readLock];
	[_windowControllers2 makeObjectsPerformSelector:@selector(threaded_pushAudioBufferListValue:) withObject:[NSValue valueWithPointer:bufferList]];
	[_windowControllersLock unlock];
}
- (void)audioOutput:(ECVAudioOutput *)sender didRequestBufferList:(inout AudioBufferList *)bufferList forTime:(AudioTimeStamp const *)t
{
	if(sender != _audioOutput) return;
	[_audioPreviewingPipe requestOutputBufferList:bufferList];
}

#pragma mark -ECVCaptureDocument<ECVCaptureDocumentConfiguring>

- (BOOL)isMuted
{
	return _muted;
}
- (void)setMuted:(BOOL)flag
{
	if(flag == _muted) return;
	_muted = flag;
	[_audioPreviewingPipe setVolume:_muted ? 0.0f : _volume];
	[[NSNotificationCenter defaultCenter] postNotificationName:ECVCaptureDeviceVolumeDidChangeNotification object:self];
}
- (CGFloat)volume
{
	return _volume;
}
- (void)setVolume:(CGFloat)value
{
	_volume = CLAMP(0.0f, value, 1.0f);
	[_audioPreviewingPipe setVolume:_muted ? 0.0f : _volume];
	[[self defaults] setDouble:value forKey:ECVVolumeKey];
	[[NSNotificationCenter defaultCenter] postNotificationName:ECVCaptureDeviceVolumeDidChangeNotification object:self];
}
- (BOOL)upconvertsFromMono
{
	return _upconvertsFromMono;
}
- (void)setUpconvertsFromMono:(BOOL)flag
{
	[self setPaused:YES];
	_upconvertsFromMono = flag;
	[self setPaused:NO];
	[[self defaults] setBool:flag forKey:ECVUpconvertsFromMonoKey];
}

#pragma mark -NSDocument

- (void)addWindowController:(NSWindowController *)windowController
{
	[super addWindowController:windowController];
	[_windowControllersLock writeLock];
	if(NSNotFound == [_windowControllers2 indexOfObjectIdenticalTo:windowController]) [_windowControllers2 addObject:windowController];
	[_windowControllersLock unlock];
}
- (void)removeWindowController:(NSWindowController *)windowController
{
	[super removeWindowController:windowController];
	[_windowControllersLock writeLock];
	[_windowControllers2 removeObjectIdenticalTo:windowController];
	[_windowControllersLock unlock];
}
- (void)makeWindowControllers
{
	[self addWindowController:[[[ECVCaptureController alloc] init] autorelease]];
}

#pragma mark -

- (NSString *)displayName
{
	return [_videoDevice name] ?: @"";
}
- (void)close
{
	[self setPaused:YES];
	[super close];
}

#pragma mark -NSObject

- (id)init
{
	if((self = [super init])) {
		_paused = YES;

		_windowControllersLock = [[ECVReadWriteLock alloc] init];
		_windowControllers2 = [[NSMutableArray alloc] init];

		[self setVolume:[[self defaults] doubleForKey:ECVVolumeKey]];
		[self setUpconvertsFromMono:[[self defaults] boolForKey:ECVUpconvertsFromMonoKey]];

		[[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(workspaceWillSleep:) name:NSWorkspaceWillSleepNotification object:[NSWorkspace sharedWorkspace]];

		NSUserDefaults *const defaults = [_videoDevice defaults];
		[defaults registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
			[NSNumber numberWithDouble:1.0f], ECVVolumeKey,
			[NSNumber numberWithBool:NO], ECVUpconvertsFromMonoKey,
			nil]];
	}
	return self;
}
- (void)dealloc
{
	[[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];

	ECVConfigController *const config = [ECVConfigController sharedConfigController];
	if([config captureDocument] == self) [config setCaptureDocument:nil];

	[_windowControllersLock release];
	[_windowControllers2 release];

	[_audioInput release];
	[_audioOutput release];
	[_audioPreviewingPipe release];

	[super dealloc];
}

@end

@implementation ECVCaptureDevice(ECVAudio)

- (ECVAudioInput *)builtInAudioInput
{
	ECVAudioInput *const input = [ECVAudioInput deviceWithIODevice:[self service]];
	[input setName:[self name]];
	return input;
}

@end
