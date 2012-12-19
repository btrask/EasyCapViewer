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
#import "ECVAudioTarget.h"
#import "ECVAudioPipe.h"
#import "ECVCaptureDocument.h"
#import "ECVDebug.h"

#define ECVFramesPerPacket 1
#define ECVChannelsPerFrame 2

NSString *const ECVCaptureDeviceVolumeDidChangeNotification = @"ECVCaptureDeviceVolumeDidChange";

static NSString *const ECVVolumeKey = @"ECVVolume";
static NSString *const ECVUpconvertsFromMonoKey = @"ECVUpconvertsFromMono";

@implementation ECVAudioTarget

- (ECVCaptureDocument *)captureDocument
{
	return _captureDocument;
}
- (void)setCaptureDocument:(ECVCaptureDocument *const)doc
{
	_captureDocument = doc;
}
- (NSUserDefaults *)defaults
{
	return [_captureDocument defaults];
}

#pragma mark -

- (ECVAudioOutput *)audioOutput
{
	if(!_audioOutput) _audioOutput = [[ECVAudioOutput defaultDevice] retain];
	return [[_audioOutput retain] autorelease];
}
- (void)setAudioOutput:(ECVAudioOutput *const)output
{
	if(BTEqualObjects(output, _audioOutput)) return;
	[_captureDocument setPaused:YES];
	[_audioOutput release];
	_audioOutput = [output retain];
	[_audioPipe release];
	_audioPipe = nil;
	[_captureDocument setPaused:NO];
}
- (void)setInputBasicDescription:(AudioStreamBasicDescription const)desc
{
	_inputDescription = desc;
}
- (BOOL)isMuted
{
	return _muted;
}
- (void)setMuted:(BOOL)flag
{
	if(flag == _muted) return;
	_muted = flag;
	[_audioPipe setVolume:_muted ? 0.0f : _volume];
	[[NSNotificationCenter defaultCenter] postNotificationName:ECVCaptureDeviceVolumeDidChangeNotification object:self];
}
- (CGFloat)volume
{
	return _volume;
}
- (void)setVolume:(CGFloat)value
{
	_volume = CLAMP(0.0f, value, 1.0f);
	[_audioPipe setVolume:_muted ? 0.0f : _volume];
	[[self defaults] setDouble:value forKey:ECVVolumeKey];
	[[NSNotificationCenter defaultCenter] postNotificationName:ECVCaptureDeviceVolumeDidChangeNotification object:self];
}
- (BOOL)upconvertsFromMono
{
	return _upconvertsFromMono;
}
- (void)setUpconvertsFromMono:(BOOL)flag
{
	[_captureDocument setPaused:YES];
	_upconvertsFromMono = flag;
	[_captureDocument setPaused:NO];
	[[self defaults] setBool:flag forKey:ECVUpconvertsFromMonoKey];
}

#pragma mark -ECVAudioTarget<ECVAudioDeviceDelegate>

- (void)audioOutput:(ECVAudioOutput *)sender didRequestBufferList:(inout AudioBufferList *)bufferList forTime:(AudioTimeStamp const *)t
{
	if(sender != _audioOutput) return;
	[_audioPipe requestOutputBufferList:bufferList];
}

#pragma mark -NSObject

- (id)init
{
	if((self = [super init])) {
		// FIXME: The defaults object is not set yet at this point.
		NSUserDefaults *const d = [self defaults];
		[d registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
			[NSNumber numberWithDouble:1.0f], ECVVolumeKey,
			[NSNumber numberWithBool:NO], ECVUpconvertsFromMonoKey,
			nil]];
		_inputDescription = ECVStandardAudioStreamBasicDescription;
	}
	return self;
}
- (void)dealloc
{
	[self stop];
	[super dealloc];
}

#pragma mark -ECVAudioTarget<ECVAVTarget>

- (void)play
{
	NSAssert(!_audioPipe, @"Audio pipe should be cleared before restarting audio.");
	ECVAudioStream *const outputStream = [_audioOutput stream];
	AudioStreamBasicDescription const outputDescription = [outputStream basicDescription];
	_audioPipe = [[ECVAudioPipe alloc] initWithInputDescription:_inputDescription outputDescription:outputDescription upconvertFromMono:_upconvertsFromMono];
	[_audioPipe setVolume:_muted ? 0.0 : _volume];
	[_audioOutput setDelegate:self];
	if(![_audioOutput start]) {
		ECVLog(ECVWarning, @"Audio output could not be started (%@, %@)", _audioOutput, outputStream);
		[self stop];
	}
}
- (void)stop
{
	[_audioOutput stop];
	[_audioOutput setDelegate:nil];
	[_audioPipe release];
	_audioPipe = nil;
}
- (void)pushVideoFrame:(ECVVideoFrame *const)frame {}
- (void)pushAudioBufferListValue:(NSValue *const)bufferListValue
{
	[_audioPipe receiveInputBufferList:[bufferListValue pointerValue]];
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
