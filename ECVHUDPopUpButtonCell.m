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
#import "ECVHUDPopUpButtonCell.h"

// Other Sources
#import "ECVAppKitAdditions.h"

#define ECVMarginLeft 4.5f
#define ECVMarginRight 4.5f
#define ECVMarginHorz (ECVMarginLeft + ECVMarginRight)
#define ECVMarginTop 1.5f
#define ECVMarginBottom 3.5f
#define ECVMarginVert (ECVMarginTop + ECVMarginBottom)

#define ECVArrowSpacing 2.0f
#define ECVArrowCenterlineDistance (ECVArrowSpacing / 2.0f)
#define ECVArrowMarginVert (ECVArrowCenterlineDistance + 4.0f)
#define ECVArrowMarginRight 6.0f
#define ECVArrowWidthRatio 1.25f

@implementation ECVHUDPopUpButtonCell

#pragma mark -NSMenuItemCell

- (void)drawTitleWithFrame:(NSRect)r inView:(NSView *)controlView
{
	NSMutableParagraphStyle *const style = [[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
	[style setLineBreakMode:NSLineBreakByTruncatingTail];
	[[self title] drawInRect:[self titleRectForBounds:r] withAttributes:[NSDictionary dictionaryWithObjectsAndKeys:
		[NSColor colorWithCalibratedWhite:1.0f alpha:[self isEnabled] ? 1.0f : 0.67f], NSForegroundColorAttributeName,
		[NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:[self controlSize]]], NSFontAttributeName,
		style, NSParagraphStyleAttributeName,
		nil]];
}
- (void)drawBorderAndBackgroundWithFrame:(NSRect)r inView:(NSView *)controlView
{
	[NSGraphicsContext saveGraphicsState];

	NSShadow *const s = [[[NSShadow alloc] init] autorelease];
	[s setShadowOffset:NSMakeSize(0.0f, -1.0f)];
	[s setShadowBlurRadius:2.0f];
	[s set];

	CGContextRef const context = [[NSGraphicsContext currentContext] graphicsPort];
	CGContextBeginTransparencyLayerWithRect(context, NSRectToCGRect(r), nil);

	BOOL const e = [self isEnabled];

	NSBezierPath *const p = [NSBezierPath ECV_bezierPathWithRoundRect:NSMakeRect(NSMinX(r) + ECVMarginLeft, NSMinY(r) + ECVMarginTop, NSWidth(r) - ECVMarginHorz, NSHeight(r) - ECVMarginVert) cornerRadius:4.0f];

	NSColor *startColor = nil, *endColor = nil;
	if([self isHighlighted]) {
		startColor = [NSColor colorWithCalibratedWhite:0.95f alpha:e ? 0.8f : 0.4f];
		endColor = [NSColor colorWithCalibratedWhite:0.55f alpha:e ? 0.8f : 0.4f];
	} else {
		startColor = [NSColor colorWithCalibratedWhite:0.55f alpha:e ? 0.3f : 0.1f];
		endColor = [NSColor colorWithCalibratedWhite:0.1f alpha:e ? 0.3f : 0.1f];
	}
	[p ECV_fillWithGradientFromColor:startColor atPoint:NSMakePoint(NSMinX(r), NSMinY(r) + ECVMarginTop) toColor:endColor atPoint:NSMakePoint(NSMinX(r), NSMaxY(r) - ECVMarginBottom)];

	[[NSColor colorWithCalibratedWhite:0.75f alpha:e ? 0.9f : 0.5f] set];
	[p stroke];

	CGFloat const arrowHeight = round((NSHeight(r) - ECVMarginVert) / 2.0f - ECVArrowMarginVert);
	CGFloat const arrowWidth = round(arrowHeight * ECVArrowWidthRatio);
	NSPoint const o = NSMakePoint(round(NSMaxX(r) - ECVMarginRight - arrowWidth / 2.0f - ECVArrowMarginRight) + 0.5f, round(NSMinY(r) + (NSHeight(r) + ECVMarginTop - ECVMarginBottom) / 2.0f));
	NSBezierPath *const arrows = [NSBezierPath bezierPath];

	[arrows moveToPoint:NSMakePoint(o.x, o.y - ECVArrowCenterlineDistance - arrowHeight)];
	[arrows lineToPoint:NSMakePoint(o.x - arrowWidth / 2.0f, o.y - ECVArrowCenterlineDistance)];
	[arrows lineToPoint:NSMakePoint(o.x + arrowWidth / 2.0f, o.y - ECVArrowCenterlineDistance)];
	[arrows closePath];

	[arrows moveToPoint:NSMakePoint(o.x, o.y + ECVArrowCenterlineDistance + arrowHeight)];
	[arrows lineToPoint:NSMakePoint(o.x - arrowWidth / 2.0f, o.y + ECVArrowCenterlineDistance)];
	[arrows lineToPoint:NSMakePoint(o.x + arrowWidth / 2.0f, o.y + ECVArrowCenterlineDistance)];
	[arrows closePath];

	[[NSColor colorWithCalibratedWhite:1.0f alpha:e ? 0.9f : 0.5f] set];
	[arrows fill];

	CGContextEndTransparencyLayer(context);
	[NSGraphicsContext restoreGraphicsState];
}

@end
