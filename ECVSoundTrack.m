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
#if !__LP64__
#import "ECVSoundTrack.h"

// Other Sources
#import "ECVDebug.h"

@implementation ECVSoundTrack

#pragma mark -ECVSoundTrack

- (id)initWithTrack:(QTTrack *)track description:(AudioStreamBasicDescription)desc
{
	if((self = [super initWithTrack:track])) {
		_basicDescription = desc;
		ECVOSStatus(QTSoundDescriptionCreate(&desc, NULL, 0, NULL, 0, kQTSoundDescriptionKind_Movie_AnyVersion, &_soundDescriptionHandle));
	}
	return self;
}

#pragma mark -

- (void)addSample:(AudioBuffer const *)buffer
{
	ByteCount const size = buffer->mDataByteSize;
	AddMediaSample2([[self.track media] quickTimeMedia], buffer->mData, size, 1, 0, (SampleDescriptionHandle)_soundDescriptionHandle, size / _basicDescription.mBytesPerFrame, 0, NULL);
}
- (void)addSamples:(AudioBufferList const *)bufferList
{
	UInt32 i = 0;
	for(; i < bufferList->mNumberBuffers; i++) [self addSample:&bufferList->mBuffers[i]];
}

#pragma mark -NSObject

- (void)dealloc
{
	if(_soundDescriptionHandle) DisposeHandle((Handle)_soundDescriptionHandle);
	[super dealloc];
}

@end

@implementation QTMovie(ECVSoundTrackCreation)

- (ECVSoundTrack *)ECV_soundTrackWithDescription:(AudioStreamBasicDescription)desc volume:(CGFloat)volume
{
	NSParameterAssert([[[self movieAttributes] objectForKey:QTMovieEditableAttribute] boolValue]);
	Track const track = NewMovieTrack([self quickTimeMovie], 0, 0, (short)round(volume * kFullVolume));
	if(!track) return nil;
	Media const media = NewTrackMedia(track, SoundMediaType, desc.mSampleRate, NULL, 0);
	if(!media) {
		DisposeMovieTrack(track);
		return nil;
	}
	return [[[ECVSoundTrack alloc] initWithTrack:[QTTrack trackWithQuickTimeTrack:track error:nil] description:desc] autorelease];
}

@end

#endif
