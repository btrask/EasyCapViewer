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
#import "ECVAppKitAdditions.h"

// Other Sources
#import "ECVDebug.h"

@implementation NSBezierPath(ECVAppKitAdditions)

#pragma mark +NSBezierPath(ECVAppKitAdditions)

+ (NSBezierPath *)ECV_bezierPathWithRoundRect:(NSRect)aRect cornerRadius:(CGFloat)radius
{
	NSBezierPath *const path = [self bezierPath];
	[path appendBezierPathWithArcWithCenter:NSMakePoint(NSMaxX(aRect) - radius, NSMaxY(aRect) - radius) radius:radius startAngle:0.0f endAngle:90.0f];
	[path appendBezierPathWithArcWithCenter:NSMakePoint(NSMinX(aRect) + radius, NSMaxY(aRect) - radius) radius:radius startAngle:90.0f endAngle:180.0f];
	[path appendBezierPathWithArcWithCenter:NSMakePoint(NSMinX(aRect) + radius, NSMinY(aRect) + radius) radius:radius startAngle:180.0f endAngle:270.0f];
	[path appendBezierPathWithArcWithCenter:NSMakePoint(NSMaxX(aRect) - radius, NSMinY(aRect) + radius) radius:radius startAngle:270.0f endAngle:0.0f];
	[path closePath];
	return path;
}

#pragma mark -NSBezierPath(ECVAppKitAdditions)

#define ECVNumberOfColorSpaceComponents 4
static void ECVGradientCallback(CGFloat colors[2][ECVNumberOfColorSpaceComponents], CGFloat const x[1], CGFloat y[ECVNumberOfColorSpaceComponents])
{
	NSUInteger i = 0;
	for(; i < ECVNumberOfColorSpaceComponents; i++) y[i] = (1.0f - x[0]) * colors[0][i] + x[0] * colors[1][i];
}
- (void)ECV_fillWithGradientFromColor:(NSColor *)startColor atPoint:(NSPoint)startPoint toColor:(NSColor *)endColor atPoint:(NSPoint)endPoint
{
	NSColorSpace *const colorSpace = [NSColorSpace genericRGBColorSpace];
	CGFloat const domain[] = {0.0f, 1.0f};
	CGFloat const range[ECVNumberOfColorSpaceComponents * 2] = {
		0.0f, 1.0f,
		0.0f, 1.0f,
		0.0f, 1.0f,
		0.0f, 1.0f,
	};
	CGFloat colors[2][ECVNumberOfColorSpaceComponents] = {};
	[[startColor colorUsingColorSpace:colorSpace] getComponents:colors[0]];
	[[endColor colorUsingColorSpace:colorSpace] getComponents:colors[1]];

	[NSGraphicsContext saveGraphicsState];
	[self addClip];
	CGFunctionCallbacks const callbacks = {0, (CGFunctionEvaluateCallback)ECVGradientCallback, NULL};
	CGFunctionRef const function = CGFunctionCreate(colors, 1, domain, ECVNumberOfColorSpaceComponents, range, &callbacks);
	CGShadingRef const shading = CGShadingCreateAxial([colorSpace CGColorSpace], NSPointToCGPoint(startPoint), NSPointToCGPoint(endPoint), function, true, true);
	CGFunctionRelease(function);
	CGContextDrawShading([[NSGraphicsContext currentContext] graphicsPort], shading);
	CGShadingRelease(shading);
	[NSGraphicsContext restoreGraphicsState];
}

@end

@implementation NSBitmapImageRep(ECVAppKitAdditions)

- (GLuint)ECV_textureName
{
	GLuint textureName = 0;
	ECVGLError(glGenTextures(1, &textureName));
	ECVGLError(glEnable(GL_TEXTURE_RECTANGLE_EXT));
	ECVGLError(glBindTexture(GL_TEXTURE_RECTANGLE_EXT, textureName));
	ECVGLError(glTexImage2D(GL_TEXTURE_RECTANGLE_EXT, 0, GL_RGBA, [self pixelsWide], [self pixelsHigh], 0, GL_RGBA, GL_UNSIGNED_BYTE, [self bitmapData]));
	ECVGLError(glDisable(GL_TEXTURE_RECTANGLE_EXT));
	return textureName;
}

@end
