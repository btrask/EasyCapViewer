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
#import "ECVTickMarkView.h"

#define ECVNumberOfTickMarks 9
#define ECVMiddleTickMark ((ECVNumberOfTickMarks - 1) / 2)
#define ECVTickMarkThickness 1.0f

@implementation ECVTickMarkView

#pragma mark -NSView

- (void)drawRect:(NSRect)aRect
{
	NSRect const b = [self bounds];
	CGFloat const step = (NSWidth(b) - ECVTickMarkThickness) / (ECVNumberOfTickMarks + 1.0f);
	CGFloat const start = NSMinX(b) + step;
	NSUInteger i = 0;
	for(; i < ECVNumberOfTickMarks; i++) {
		[[NSColor colorWithDeviceWhite:0.67f alpha:ECVMiddleTickMark == i ? 0.75f : 0.4f] set];
		NSRectFill(NSMakeRect(round(start + step * i), NSMinY(b), ECVTickMarkThickness, NSHeight(b)));
	}
}

@end
