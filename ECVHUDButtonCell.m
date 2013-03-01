/* Copyright (c) 2013, Ben Trask
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE AUTHORS ''AS IS'' AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. */
#import "ECVHUDButtonCell.h"
#import "ECVAppKitAdditions.h"

#define ECVMarginVert 3.5f
#define ECVMarginHorz 3.5f

@implementation ECVHUDButtonCell

#pragma mark -NSButtonCell

- (void)drawBezelWithFrame:(NSRect const)r inView:(NSView *const)controlView
{
	[NSGraphicsContext saveGraphicsState];

	NSShadow *const s = [[[NSShadow alloc] init] autorelease];
	[s setShadowOffset:NSMakeSize(0.0f, -1.0f)];
	[s setShadowBlurRadius:2.0f];
	[s set];

	BOOL const e = [self isEnabled];
	NSBezierPath *const p = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(r, ECVMarginHorz, ECVMarginVert) xRadius:4.0f yRadius:4.0f];
	[p ECV_fillWithHUDButtonGradientWithHighlight:[self isHighlighted] enabled:e];
	[[NSColor colorWithCalibratedWhite:0.75f alpha:e ? 0.9f : 0.5f] set];
	[p stroke];

	[NSGraphicsContext restoreGraphicsState];
}
- (NSRect)drawTitle:(NSAttributedString *const)title withFrame:(NSRect const)frame inView:(NSView *const)controlView
{
	NSMutableAttributedString *const t = [[title mutableCopy] autorelease];
	[t addAttributes:[NSDictionary dictionaryWithObjectsAndKeys:
		[NSColor whiteColor], NSForegroundColorAttributeName,
		nil] range:NSMakeRange(0, [t length])];
	return [super drawTitle:t withFrame:frame inView:controlView];
}

@end
