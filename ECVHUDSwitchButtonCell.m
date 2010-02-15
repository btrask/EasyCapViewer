/* Copyright (c) 2010, Ben Trask
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
#import "ECVHUDSwitchButtonCell.h"

// Other Sources
#import "ECVAppKitAdditions.h"

#define ECVMarginVert 3.5f
#define ECVMarginHorz 3.5f

@implementation ECVHUDSwitchButtonCell

#pragma mark -NSButtonCell

- (void)drawImage:(NSImage *)image withFrame:(NSRect)r inView:(NSView *)controlView
{
	[NSGraphicsContext saveGraphicsState];

	NSShadow *const s = [[[NSShadow alloc] init] autorelease];
	[s setShadowOffset:NSMakeSize(0.0f, -1.0f)];
	[s setShadowBlurRadius:2.0f];
	[s set];

	BOOL const e = [self isEnabled];
	NSBezierPath *const p = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(r, ECVMarginHorz, ECVMarginVert) xRadius:1.0f yRadius:1.0f];
	[p ECV_fillWithHUDButtonGradientWithHighlight:[self isHighlighted] enabled:e];
	[[NSColor colorWithCalibratedWhite:0.75f alpha:e ? 0.9f : 0.5f] set];
	[p stroke];

	[NSGraphicsContext restoreGraphicsState];

	NSBezierPath *const markShape = [NSBezierPath bezierPath];
	[markShape setLineWidth:2.0f];
	switch([self state]) {
		case NSOnState:
			[markShape moveToPoint:NSMakePoint(NSMidX(r) - 3.0f, NSMidY(r) - 3.0f)];
			[markShape lineToPoint:NSMakePoint(NSMidX(r) + 0.0f, NSMidY(r) + 2.0f)];
			[markShape lineToPoint:NSMakePoint(NSMidX(r) + 6.0f, NSMidY(r) - 8.0f)];
			break;
		case NSMixedState:
			[markShape moveToPoint:NSMakePoint(NSMinX(r) + ECVMarginHorz + 2.0f, NSMidY(r))];
			[markShape lineToPoint:NSMakePoint(NSMaxX(r) - ECVMarginHorz + 2.0f, NSMidY(r))];
			break;
	}
	[[NSColor colorWithCalibratedWhite:1.0f alpha:e ? 0.9f : 0.7f] set];
	[markShape stroke];
}
- (NSRect)drawTitle:(NSAttributedString *)title withFrame:(NSRect)frame inView:(NSView *)controlView
{
	NSMutableAttributedString *const t = [[title mutableCopy] autorelease];
	[t addAttributes:[NSDictionary dictionaryWithObjectsAndKeys:
		[NSColor whiteColor], NSForegroundColorAttributeName,
		nil] range:NSMakeRange(0, [t length])];
	return [super drawTitle:t withFrame:frame inView:controlView];
}

@end
