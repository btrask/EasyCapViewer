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

#define ECVHandleSize 16

static void ECVDrawHandleAtPoint(CGFloat x, CGFloat y)
{
	ECVGLDrawTexture(NSMakeRect(x, y, ECVHandleSize, ECVHandleSize), NSMakeRect(0.0f, 0.0f, ECVHandleSize, ECVHandleSize));
}

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
		[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:_handleRep]];

		[[NSColor colorWithDeviceWhite:1.0f alpha:0.75f] set];
		NSRectFill(NSMakeRect(0.0f, 0.0f, ECVHandleSize, ECVHandleSize));
		[[NSColor colorWithDeviceWhite:0.0f alpha:1.0f] set];
		NSFrameRect(NSMakeRect(0.0f, 0.0f, ECVHandleSize, ECVHandleSize));

		[context makeCurrentContext];
		CGLLockContext([context CGLContextObj]);
		_handleTextureName = [_handleRep ECV_textureName];
		CGLUnlockContext([context CGLContextObj]);
	}
	return self;
}
@synthesize cropRect = _cropRect;

#pragma mark -NSCell

- (BOOL)trackMouse:(NSEvent *)theEvent inRect:(NSRect)cellFrame ofView:(NSView *)controlView untilMouseUp:(BOOL)flag
{
}
- (void)resetCursorRect:(NSRect)cellFrame inView:(NSView *)controlView
{
}

#pragma mark -NSObject

- (void)dealloc
{
	ECVGLError(glDeleteTextures(1, &_handleTextureName));
	[_handleRep release];
	[super dealloc];
}

#pragma mark -<ECVVideoViewCell>

- (void)drawWithFrame:(NSRect)r inVideoView:(ECVVideoView *)v playing:(BOOL)flag
{
	if(NSEqualRects(_cropRect, ECVUncroppedRect)) return;
	NSRect const cropRect = NSIntegralRect(NSOffsetRect(ECVScaledRect(_cropRect, r.size), NSMinX(r), NSMinY(r)));

	glColor4f(0.0f, 0.0f, 0.0f, 0.5f);
	ECVGLDrawBorder(cropRect, r);
	glColor4f(1.0f, 1.0f, 1.0f, 1.0f);
	ECVGLDrawBorder(cropRect, NSInsetRect(cropRect, -1.0f, -1.0f));

	ECVGLError(glEnable(GL_TEXTURE_RECTANGLE_EXT));
	ECVGLError(glBindTexture(GL_TEXTURE_RECTANGLE_EXT, _handleTextureName));
	ECVDrawHandleAtPoint(NSMinX(cropRect), NSMinY(cropRect));
	ECVDrawHandleAtPoint(roundf(NSMidX(cropRect) - ECVHandleSize / 2.0f), NSMinY(cropRect));
	ECVDrawHandleAtPoint(NSMaxX(cropRect) - ECVHandleSize, NSMinY(cropRect));

	ECVDrawHandleAtPoint(NSMinX(cropRect), roundf(NSMidY(cropRect) - ECVHandleSize / 2.0f));
	ECVDrawHandleAtPoint(NSMaxX(cropRect) - ECVHandleSize, roundf(NSMidY(cropRect) - ECVHandleSize / 2.0f));

	ECVDrawHandleAtPoint(NSMinX(cropRect), NSMaxY(cropRect) - ECVHandleSize);
	ECVDrawHandleAtPoint(roundf(NSMidX(cropRect) - ECVHandleSize / 2.0f), NSMaxY(cropRect) - ECVHandleSize);
	ECVDrawHandleAtPoint(NSMaxX(cropRect) - ECVHandleSize, NSMaxY(cropRect) - ECVHandleSize);
	ECVGLError(glDisable(GL_TEXTURE_RECTANGLE_EXT));
}

@end
