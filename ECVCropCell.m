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
#import "ECVCropCell.h"

// Other Sources
#import "ECVAppKitAdditions.h"
#import "ECVDebug.h"
#import "ECVOpenGLAdditions.h"

#define ECVHandleSize 10
#define ECVMinimumCropSize 0.05f

static ECVRectEdgeMask const ECVHandlePositions[] = {
	ECVMinYMask | ECVMinXMask,
	ECVMinYMask | ECVRectMidX,
	ECVMinYMask | ECVMaxXMask,
	ECVRectMidY | ECVMinXMask,
	ECVRectMidY | ECVMaxXMask,
	ECVMaxYMask | ECVMinXMask,
	ECVMaxYMask | ECVRectMidX,
	ECVMaxYMask | ECVMaxXMask,
};

@implementation ECVCropCell

#pragma mark +NSCell

+ (BOOL)prefersTrackingUntilMouseUp
{
	return YES;
}

#pragma mark -ECVCropCell

- (id)initWithOpenGLContext:(NSOpenGLContext *)context
{
	if((self = [super init])) {
		_cropRect = ECVUncroppedRect;

		_handleRep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:ECVHandleSize pixelsHigh:ECVHandleSize bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:ECVHandleSize * 4 bitsPerPixel:0];
		NSGraphicsContext *const graphicsContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:_handleRep];
		[NSGraphicsContext setCurrentContext:graphicsContext];

		NSRect const r = NSInsetRect(NSMakeRect(0.0f, 0.0f, ECVHandleSize, ECVHandleSize), 1.0f, 1.0f);
		NSBezierPath *const p = [NSBezierPath bezierPathWithOvalInRect:r];
		[p setLineWidth:2.0f];
		[p ECV_fillWithGradientFromColor:[NSColor colorWithCalibratedWhite:0.7f alpha:1.0f] atPoint:ECVRectPoint(r, ECVMinXMaxYCorner) toColor:[NSColor colorWithCalibratedWhite:0.2f alpha:1.0f] atPoint:ECVRectPoint(r, ECVMinXMinYCorner)];
		[[NSColor whiteColor] set];
		[p stroke];

		[graphicsContext flushGraphics];

		[context makeCurrentContext];
		CGLLockContext([context CGLContextObj]);
		_handleTextureName = [_handleRep ECV_textureName];
		CGLUnlockContext([context CGLContextObj]);
	}
	return self;
}
@synthesize delegate;
- (NSRect)cropRect
{
	return _cropRect;
}
- (void)setCropRect:(NSRect)aRect
{
	_cropRect = aRect;
	_tempCropRect = aRect;
}

#pragma mark -

- (NSRect)maskRectWithCropRect:(NSRect)crop frame:(NSRect)frame
{
	NSRect r = NSOffsetRect(ECVScaledRect(crop, frame.size), NSMinX(frame), NSMinY(frame));
	r.origin.x = round(NSMinX(r));
	r.origin.y = round(NSMinY(r));
	r.size.width = round(NSWidth(r));
	r.size.height = round(NSHeight(r));
	return r;
}
- (NSRect)frameForHandlePosition:(ECVRectEdgeMask)pos maskRect:(NSRect)mask inFrame:(NSRect)frame
{
	NSPoint const c = ECVRectPoint(NSIntersectionRect(frame, NSInsetRect(mask, ECVHandleSize / -2.0f, ECVHandleSize / -2.0f)), pos);
	NSPoint const p = ECVRectPoint(NSMakeRect(0.0f, 0.0f, ECVHandleSize, ECVHandleSize), pos);
	return NSMakeRect(round(c.x - p.x), round(c.y - p.y), ECVHandleSize, ECVHandleSize);
}
- (ECVRectEdgeMask)handlePositionForPoint:(NSPoint)point withMaskRect:(NSRect)mask inFrame:(NSRect)frame view:(NSView *)aView
{
	NSUInteger i = numberof(ECVHandlePositions);
	while(i--) if([aView mouse:point inRect:[self frameForHandlePosition:ECVHandlePositions[i] maskRect:mask inFrame:frame]]) return ECVHandlePositions[i];
	return ECVRectCenter;
}
- (NSCursor *)cursorForHandlePosition:(ECVRectEdgeMask)pos
{
	switch(pos) {
		case ECVMinXMask:
		case ECVMaxXMask:
			return [NSCursor resizeLeftRightCursor];
		case ECVMinYMask:
		case ECVMaxYMask:
			return [NSCursor resizeUpDownCursor];
		case ECVMinXMinYCorner:
		case ECVMaxXMaxYCorner:
			return [[[NSCursor alloc] initWithImage:[NSImage imageNamed:@"Cursor-Resize-135"] hotSpot:NSMakePoint(8.0f, 8.0f)] autorelease];
		case ECVMinXMaxYCorner:
		case ECVMaxXMinYCorner:
			return [[[NSCursor alloc] initWithImage:[NSImage imageNamed:@"Cursor-Resize-45"] hotSpot:NSMakePoint(8.0f, 8.0f)] autorelease];
		default:
			return [NSCursor arrowCursor];
	}
}

#pragma mark -NSCell

- (BOOL)trackMouse:(NSEvent *)firstEvent inRect:(NSRect)aRect ofView:(NSView *)aView untilMouseUp:(BOOL)flag
{
	NSPoint const firstLocation = [aView convertPoint:[firstEvent locationInWindow] fromView:nil];
	NSRect const firstMaskRect = [self maskRectWithCropRect:_cropRect frame:aRect];
	ECVRectEdgeMask const handle = [self handlePositionForPoint:firstLocation withMaskRect:firstMaskRect inFrame:aRect view:aView];
	if(!handle) {
		[self.delegate cropCellDidFinishCropping:self];
		return YES; // Claim the mouse is up.
	}
	NSPoint const handlePoint = ECVRectPoint(firstMaskRect, handle);
	NSSize const handleOffset = NSMakeSize(handlePoint.x - firstLocation.x, handlePoint.y - firstLocation.y);

	[[aView window] disableCursorRects];
	NSEvent *latestEvent = nil;
	while((latestEvent = [[aView window] nextEventMatchingMask:NSLeftMouseUpMask | NSLeftMouseDraggedMask untilDate:[NSDate distantFuture] inMode:NSEventTrackingRunLoopMode dequeue:YES]) && [latestEvent type] != NSLeftMouseUp) {
		NSPoint const latestLocation = [aView convertPoint:[latestEvent locationInWindow] fromView:nil];
		NSRect const maskRect = [self maskRectWithCropRect:_cropRect frame:aRect];
		NSRect const r = ECVRectByScalingEdgeToPoint(maskRect, handle, NSMakePoint(latestLocation.x + handleOffset.width, latestLocation.y + handleOffset.height), NSMakeSize(ECVHandleSize * 2.0f, ECVHandleSize * 2.0f), aRect);
		_tempCropRect = ECVScaledRect(NSOffsetRect(r, -NSMinX(aRect), -NSMinY(aRect)), NSMakeSize(1.0f / NSWidth(aRect), 1.0f / NSHeight(aRect)));
		[aView setNeedsDisplay:YES];
	}
	[[aView window] discardEventsMatchingMask:NSAnyEventMask beforeEvent:latestEvent];
	[[aView window] invalidateCursorRectsForView:aView];
	[[aView window] enableCursorRects];
	_cropRect = _tempCropRect;
	return YES;
}
- (void)resetCursorRect:(NSRect)cellFrame inView:(NSView *)controlView
{
	NSUInteger i = 0;
	NSRect const maskRect = [self maskRectWithCropRect:_tempCropRect frame:cellFrame];
	for(; i < numberof(ECVHandlePositions); i++) [controlView addCursorRect:[self frameForHandlePosition:ECVHandlePositions[i] maskRect:maskRect inFrame:cellFrame] cursor:[self cursorForHandlePosition:ECVHandlePositions[i]]];
}

#pragma mark -NSObject

- (void)dealloc
{
	ECVGLError(glDeleteTextures(1, &_handleTextureName));
	[_handleRep release];
	[super dealloc];
}

#pragma mark -<ECVVideoViewCell>

- (void)drawWithFrame:(NSRect)aRect inVideoView:(ECVVideoView *)view playing:(BOOL)flag
{
	NSRect const maskRect = [self maskRectWithCropRect:_tempCropRect frame:aRect];

	glColor4f(0.0f, 0.0f, 0.0f, 0.5f);
	ECVGLDrawBorder(maskRect, aRect);
	glColor4f(1.0f, 1.0f, 1.0f, 1.0f);
	ECVGLDrawBorder(maskRect, NSInsetRect(maskRect, -1.0f, -1.0f));

	ECVGLError(glEnable(GL_TEXTURE_RECTANGLE_EXT));
	ECVGLError(glBindTexture(GL_TEXTURE_RECTANGLE_EXT, _handleTextureName));
	NSUInteger i = 0;
	for(; i < numberof(ECVHandlePositions); i++) ECVGLDrawTextureInRect([self frameForHandlePosition:ECVHandlePositions[i] maskRect:maskRect inFrame:aRect]);
	ECVGLError(glDisable(GL_TEXTURE_RECTANGLE_EXT));
}

@end

@implementation NSObject(ECVCropCellDelegate)

- (void)cropCellDidFinishCropping:(ECVCropCell *)sender {}

@end
