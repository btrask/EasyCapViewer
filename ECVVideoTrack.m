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

// Other Sources
#import "ECVDebug.h"

@implementation ECVVideoTrack

#pragma mark +ECVVideoTrack

+ (id)videoTrackWithMovie:(QTMovie *)movie size:(NSSize)aSize
{
	NSParameterAssert([[[movie movieAttributes] objectForKey:QTMovieEditableAttribute] boolValue]);
	Track const track = NewMovieTrack([movie quickTimeMovie], FixRatio(roundf(aSize.width), 1), FixRatio(roundf(aSize.height), 1), kNoVolume);
	if(!track) return nil;
	Media const media = NewTrackMedia(track, VideoMediaType, [[[movie movieAttributes] objectForKey:QTMovieTimeScaleAttribute] longValue], NULL, 0);
	if(!media) {
		DisposeMovieTrack(track);
		return nil;
	}
	return [self trackWithQuickTimeTrack:track error:nil];
}

#pragma mark -ECVVideoTrack

@synthesize hasPendingFrame = _hasPendingFrame;
- (void)clearPendingFrame
{
	_hasPendingFrame = NO;
}
- (void)prepareToAddFrameWithPixelBuffer:(CVPixelBufferRef)buffer codecType:(CodecType)type quality:(float)quality
{
	NSParameterAssert(!_hasPendingFrame);
	CVPixelBufferLockBaseAddress(buffer, 0);

	Rect r;
	CGSize const s = CVImageBufferGetDisplaySize(buffer);
	SetRect(&r, 0, 0, roundf(s.width), roundf(s.height));

	GWorldPtr gWorld = NULL;
	ECVOSStatus(QTNewGWorldFromPtr(&gWorld, CVPixelBufferGetPixelFormatType(buffer), &r, NULL, NULL, 0, CVPixelBufferGetBaseAddress(buffer), CVPixelBufferGetBytesPerRow(buffer)));
	PixMapHandle const pixMap = GetGWorldPixMap(gWorld);

	Size maxSize = 0;
	ECVOSStatus(GetMaxCompressionSize(pixMap, &r, 24, quality, type, NULL, &maxSize));
	if(_pendingFrame && GetHandleSize(_pendingFrame) < maxSize) {
		DisposeHandle(_pendingFrame);
		_pendingFrame = NULL;
	}
	if(!_pendingFrame) _pendingFrame = NewHandle(maxSize);
	if(!_pendingFrameDescription) _pendingFrameDescription = (ImageDescriptionHandle)NewHandle(sizeof(ImageDescription));

	HLock(_pendingFrame);
	ECVOSStatus(CompressImage(pixMap, &r, (CodecQ)roundf(quality * codecMaxQuality), type, _pendingFrameDescription, *_pendingFrame));
	HUnlock(_pendingFrame);
	DisposeGWorld(gWorld);

	CVPixelBufferUnlockBaseAddress(buffer, 0);
	_hasPendingFrame = YES;
}
- (void)addFrameWithDuration:(NSTimeInterval)interval
{
	NSParameterAssert(_hasPendingFrame);
	NSParameterAssert(_pendingFrame);
	NSParameterAssert(_pendingFrameDescription);
	ECVOSStatus(AddMediaSample([[self media] quickTimeMedia], _pendingFrame, 0, (**_pendingFrameDescription).dataSize, interval * [[[self trackAttributes] objectForKey:QTTrackTimeScaleAttribute] longValue], (SampleDescriptionHandle)_pendingFrameDescription, 1, kNilOptions, NULL));
	_hasPendingFrame = NO;
}
- (void)addFrameWithPixelBuffer:(CVPixelBufferRef)buffer codecType:(CodecType)type quality:(float)quality time:(NSTimeInterval)time
{
	if(_hasPendingFrame) [self addFrameWithDuration:time - _pendingFrameStartTime];
	if(buffer) [self prepareToAddFrameWithPixelBuffer:buffer codecType:type quality:quality];
	_pendingFrameStartTime = time;
}

#pragma mark -NSObject

- (void)dealloc
{
	if(_pendingFrame) DisposeHandle(_pendingFrame);
	if(_pendingFrameDescription) DisposeHandle((Handle)_pendingFrameDescription);
	[super dealloc];
}

@end
