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
#import "ECVPlayButtonCell.h"

// Other Sources
#import "ECVAppKitAdditions.h"
#import "ECVDebug.h"
#import "ECVOpenGLAdditions.h"

#define ECVPlayButtonSize 75

@implementation ECVPlayButtonCell

#pragma mark +ECVPlayButtonCell

+ (NSImage *)playButtonImage
{
	NSBitmapImageRep *const rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:ECVPlayButtonSize pixelsHigh:ECVPlayButtonSize bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:ECVPlayButtonSize * 4 bitsPerPixel:0];
	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];

	[[NSColor clearColor] set];
	NSRect const b = NSMakeRect(0.0f, 0.0f, ECVPlayButtonSize, ECVPlayButtonSize);
	NSRectFill(b);
	[[NSColor colorWithDeviceWhite:0.5f alpha:0.67f] set];
	[[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(b, 0.5f, 0.5f)] fill];

	NSShadow *const shadow = [[[NSShadow alloc] init] autorelease];
	[shadow setShadowBlurRadius:4.0f];
	[shadow setShadowOffset:NSMakeSize(0.0f, -2.0f)];
	[shadow set];
	[[NSColor whiteColor] set];

	NSBezierPath *const iconPath = [NSBezierPath bezierPath];
	[iconPath moveToPoint:NSMakePoint(round(NSMinX(b) + NSWidth(b) * 0.75f), round(NSMidY(b)))];
	[iconPath lineToPoint:NSMakePoint(round(NSMinX(b) + NSWidth(b) * 0.33f), round(NSMinY(b) + NSHeight(b) * 0.7f))];
	[iconPath lineToPoint:NSMakePoint(round(NSMinX(b) + NSWidth(b) * 0.33f), round(NSMinY(b) + NSHeight(b) * 0.3f))];
	[iconPath closePath];
	[iconPath fill];

	NSImage *const image = [[[NSImage alloc] initWithSize:NSMakeSize(ECVPlayButtonSize, ECVPlayButtonSize)] autorelease];
	[image addRepresentation:rep];
	return image;
}

#pragma mark -ECVPlayButtonView

- (id)initWithOpenGLContext:(NSOpenGLContext *)context
{
	if((self = [super init])) {
		_context = [context retain];
	}
	return self;
}

#pragma mark -NSCell

- (void)setImage:(NSImage *)image
{
	[_context makeCurrentContext];
	CGLLockContext([_context CGLContextObj]);
	ECVGLError(glDeleteTextures(1, &_textureName));
	NSBitmapImageRep *const rep = (NSBitmapImageRep *)[image bestRepresentationForDevice:nil];
	if(rep) _textureName = [rep ECV_textureName];
	CGLUnlockContext([_context CGLContextObj]);
	[super setImage:image];
}

#pragma mark -NSObject

- (void)dealloc
{
	ECVGLError(glDeleteTextures(1, &_textureName));
	[_context release];
	[super dealloc];
}

#pragma mark -<ECVVideoViewCell>

- (void)drawWithFrame:(NSRect)r inVideoView:(ECVVideoView *)v playing:(BOOL)flag
{
	if(flag) return;
	ECVGLError(glEnable(GL_TEXTURE_RECTANGLE_EXT));
	ECVGLError(glBindTexture(GL_TEXTURE_RECTANGLE_EXT, _textureName));
	GLfloat const c = [self isHighlighted] ? 0.67f : 1.0f;
	glColor4f(c, c, c, 1.0f);
	ECVGLDrawTexture(NSMakeRect(round(NSMidX(r) - ECVPlayButtonSize / 2.0f), round(NSMinY(r) + (NSHeight(r) - ECVPlayButtonSize) * 0.67f), ECVPlayButtonSize, ECVPlayButtonSize), NSMakeRect(0.0f, 0.0f, ECVPlayButtonSize, ECVPlayButtonSize));
	ECVGLError(glDisable(GL_TEXTURE_RECTANGLE_EXT));
}

@end
