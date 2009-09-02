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
#import "ECVVideoTrack.h"

// Models
#import "ECVFrameReading.h"
#import "ECVFrame.h"

// Other Sources
#import "ECVDebug.h"

@implementation ECVVideoTrack

#pragma mark +ECVVideoTrack

+ (id)videoTrackWithMovie:(QTMovie *)movie size:(NSSize)aSize
{
	NSParameterAssert([[[movie movieAttributes] objectForKey:QTMovieEditableAttribute] boolValue]);
	Track const track = NewMovieTrack([movie quickTimeMovie], FixRatio(roundf(aSize.width), 1), FixRatio(roundf(aSize.height), 1), kNoVolume);
	if(!track) return nil;
	Media const media = NewTrackMedia(track, VideoMediaType, 600, NULL, 0);
	if(!media) {
		DisposeMovieTrack(track);
		return nil;
	}
	return [[[self alloc] initWithTrack:[QTTrack trackWithQuickTimeTrack:track error:NULL]] autorelease];
}

#pragma mark -ECVVideoTrack

- (id)initWithTrack:(QTTrack *)track
{
	if((self = [super init])) {
		_track = [track retain];
	}
	return self;
}
@synthesize track = _track;

#pragma mark -

@synthesize codecType = _codecType;
@synthesize quality = _quality;
@synthesize hasPendingFrame = _hasPendingFrame;
- (void)clearPendingFrame
{
	_hasPendingFrame = NO;
}
- (void)prepareToAddFrame:(id<ECVFrameReading>)frame
{
	NSParameterAssert(!_hasPendingFrame);

	Rect r;
	ECVPixelSize const s = frame.pixelSize;
	SetRect(&r, 0, 0, s.width, s.height);

	GWorldPtr gWorld = NULL;
	ECVOSStatus(QTNewGWorldFromPtr(&gWorld, frame.pixelFormatType, &r, NULL, NULL, 0, (void *)[frame.bufferData bytes], frame.bytesPerRow), ECVRetryDefault);
	PixMapHandle const pixMap = GetGWorldPixMap(gWorld);

	Size maxSize = 0;
	ECVOSStatus(GetMaxCompressionSize(pixMap, &r, 24, self.quality, self.codecType, NULL, &maxSize), ECVRetryDefault);
	if(_pendingFrame && GetHandleSize(_pendingFrame) < maxSize) {
		DisposeHandle(_pendingFrame);
		_pendingFrame = NULL;
	}
	if(!_pendingFrame) _pendingFrame = NewHandle(maxSize);
	if(!_pendingFrameDescription) _pendingFrameDescription = (ImageDescriptionHandle)NewHandle(sizeof(ImageDescription));

	HLock(_pendingFrame);
	ECVOSStatus(CompressImage(pixMap, &r, (CodecQ)roundf(self.quality * codecMaxQuality), self.codecType, _pendingFrameDescription, *_pendingFrame), ECVRetryDefault);
	HUnlock(_pendingFrame);
	DisposeGWorld(gWorld);

	_hasPendingFrame = YES;
}
- (void)addFrameWithDuration:(NSTimeInterval)interval
{
	NSParameterAssert(_hasPendingFrame);
	NSParameterAssert(_pendingFrame);
	NSParameterAssert(_pendingFrameDescription);
	ECVOSStatus(AddMediaSample([[self.track media] quickTimeMedia], _pendingFrame, 0, (**_pendingFrameDescription).dataSize, interval * [[[self.track trackAttributes] objectForKey:QTTrackTimeScaleAttribute] longValue], (SampleDescriptionHandle)_pendingFrameDescription, 1, kNilOptions, NULL), ECVRetryDefault);
	_hasPendingFrame = NO;
}
- (void)addFrame:(id<ECVFrameReading>)frame time:(NSTimeInterval)time
{
	if(_hasPendingFrame) [self addFrameWithDuration:time - _pendingFrameStartTime];
	if(frame) [self prepareToAddFrame:frame];
	_pendingFrameStartTime = time;
}
- (void)addFrame:(ECVFrame *)frame
{
	[self addFrame:frame time:frame.time];
}

#pragma mark -NSObject

- (void)dealloc
{
	[_track release];
	if(_pendingFrame) DisposeHandle(_pendingFrame);
	if(_pendingFrameDescription) DisposeHandle((Handle)_pendingFrameDescription);
	[super dealloc];
}

@end
