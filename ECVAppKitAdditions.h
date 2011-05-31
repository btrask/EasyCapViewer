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
@interface NSBezierPath(ECVAppKitAdditions)

- (void)ECV_fillWithGradientFromColor:(NSColor *)startColor atPoint:(NSPoint)startPoint toColor:(NSColor *)endColor atPoint:(NSPoint)endPoint;
- (void)ECV_fillWithHUDButtonGradientWithHighlight:(BOOL)highlight enabled:(BOOL)enabled;

- (void)ECV_appendArcWithCenter:(NSPoint)center radius:(CGFloat)radius start:(CGFloat)start end:(CGFloat)end clockwise:(BOOL)clockwise;

@end

@interface NSBitmapImageRep(ECVAppKitAdditions)

- (GLuint)ECV_textureName;

@end

@interface NSWindowController(ECVAppKitAdditions)

- (IBAction)ECV_toggleWindow:(id)sender;

@end

static CGLContextObj ECVLockContext(NSOpenGLContext *context)
{
	CGLContextObj const contextObj = [context CGLContextObj];
	[context makeCurrentContext];
	CGLLockContext(contextObj);
	return contextObj;
}
NS_INLINE void ECVUnlockContext(CGLContextObj contextObj)
{
	CGLUnlockContext(contextObj);
}
