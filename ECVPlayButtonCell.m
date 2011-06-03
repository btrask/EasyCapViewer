/* Copyright (c) 2009, Ben Trask
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
	NSBitmapImageRep *const rep = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:ECVPlayButtonSize pixelsHigh:ECVPlayButtonSize bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:ECVPlayButtonSize * 4 bitsPerPixel:0] autorelease];
	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];

	[[NSColor clearColor] set];
	NSRect const b = NSMakeRect(0.0f, 0.0f, ECVPlayButtonSize, ECVPlayButtonSize);
	NSRectFill(b);
	[[NSColor colorWithCalibratedWhite:0.5f alpha:0.67f] set];
	[[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(b, 0.5f, 0.5f)] fill];

	NSShadow *const s = [[[NSShadow alloc] init] autorelease];
	[s setShadowBlurRadius:4.0f];
	[s setShadowOffset:NSMakeSize(0.0f, -2.0f)];
	[s set];
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
+ (NSImage *)logoImage
{
	NSImage *const logo = [NSImage imageNamed:@"RTC-Logo"];
	NSRect const b = (NSRect){NSZeroPoint, [logo size]};

	NSBitmapImageRep *const rep = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:NSWidth(b) pixelsHigh:NSHeight(b) bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:NSWidth(b) * 4 bitsPerPixel:0] autorelease];
	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];

	[[NSColor clearColor] set];
	NSRectFill(b);

	[[NSColor colorWithDeviceWhite:0.0 alpha:0.75] set];
	[[NSBezierPath bezierPathWithRoundedRect:b xRadius:10.0 yRadius:10.0] fill];

	[logo drawInRect:b fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];

	NSImage *const image = [[[NSImage alloc] initWithSize:b.size] autorelease];
	[image addRepresentation:rep];
	return image;
}

#pragma mark -ECVPlayButtonView

- (id)initWithOpenGLContext:(NSOpenGLContext *)context
{
	if((self = [super init])) {
		_once = YES;
		_context = [context retain];
		CGLContextObj const contextObj = ECVLockContext(_context);

		_buttonImage = [[[self class] playButtonImage] retain];
		_buttonTextureName = [(NSBitmapImageRep *)[_buttonImage bestRepresentationForDevice:nil] ECV_textureName];

		_logoImage = [[[self class] logoImage] retain];
		_logoTextureName = [(NSBitmapImageRep *)[_logoImage bestRepresentationForDevice:nil] ECV_textureName];

		ECVUnlockContext(contextObj);
	}
	return self;
}

#pragma mark -NSObject

- (void)dealloc
{
	[_buttonImage release];
	[_logoImage release];
	ECVGLError(glDeleteTextures(1, &_buttonTextureName));
	ECVGLError(glDeleteTextures(1, &_logoTextureName));
	[_context release];
	[super dealloc];
}

#pragma mark -<ECVVideoViewCell>

- (void)drawWithFrame:(NSRect)r inVideoView:(ECVVideoView *)v playing:(BOOL)flag
{
	if(flag) {
		_once = NO;
		return;
	}
	ECVGLError(glEnable(GL_TEXTURE_RECTANGLE_EXT));

	if(_once) {
		ECVGLError(glBindTexture(GL_TEXTURE_RECTANGLE_EXT, _logoTextureName));
		glColor4f(1.0f, 1.0f, 1.0f, 1.0f);
		NSRect const b = [v bounds];
		NSSize s = [_logoImage size];
		CGFloat scaleX = MIN(1.0, NSWidth(b) / round(s.width));
		CGFloat scaleY = MIN(1.0, NSHeight(b) / round(s.height));
		scaleX = scaleY = MIN(scaleX, scaleY);
		ECVGLDrawTextureInRectWithBounds(
			NSMakeRect(
				round(NSMinX(r) + (NSWidth(r) - (s.width * scaleX)) / 2.0f),
				round(NSMinY(r) + (NSHeight(r) - (s.height * scaleY)) * 0.25),
				round(s.width * scaleX),
				round(s.height * scaleY)
			),
			(NSRect){NSZeroPoint, s}
		);
	}

	ECVGLError(glBindTexture(GL_TEXTURE_RECTANGLE_EXT, _buttonTextureName));
	GLfloat const c = [self isHighlighted] ? 0.67f : 1.0f;
	glColor4f(c, c, c, 1.0f);
	ECVGLDrawTextureInRect(NSMakeRect(round(NSMidX(r) - ECVPlayButtonSize / 2.0f), round(NSMinY(r) + (NSHeight(r) - ECVPlayButtonSize) * 0.75f), ECVPlayButtonSize, ECVPlayButtonSize));

	ECVGLError(glDisable(GL_TEXTURE_RECTANGLE_EXT));
}

@end
