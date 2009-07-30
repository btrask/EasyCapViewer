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
#import "MPLVideoView.h"
#import <OpenGL/gl.h>
#import <OpenGL/glu.h>

@implementation MPLVideoView

#pragma mark -MPLVideoView

@synthesize delegate;
- (CVImageBufferRef)imageBuffer
{
	return _imageBuffer;
}
- (void)setImageBuffer:(CVImageBufferRef)buffer
{
	@synchronized(self) {
		if(buffer == _imageBuffer) return;
		CVBufferRelease(_imageBuffer);
		_imageBuffer = CVBufferRetain(buffer);
	}
	[self drawRect:NSZeroRect];
}
@synthesize aspectRatio = _aspectRatio;
@synthesize blurFramesTogether = _blurFramesTogether;
@synthesize vsync = _vsync;
- (void)setVsync:(BOOL)flag
{
	_vsync = flag;
	
	CGLLockContext([[self openGLContext] CGLContextObj]);
	GLint params[] = {!!flag};
	CGLSetParameter(CGLGetCurrentContext(), kCGLCPSwapInterval, params);
	CGLUnlockContext([[self openGLContext] CGLContextObj]);
}
@synthesize showDroppedFrames = _showDroppedFrames;
@synthesize magFilter = _magFilter;

#pragma mark -

- (void)droppedFrame:(BOOL)flag
{
	@synchronized(self) {
		if(flag) _frameDropStrength = 1.0f;
		else _frameDropStrength *= 0.75f;
	}
}

#pragma mark -NSOpenGLView

- (id)initWithFrame:(NSRect)frameRect pixelFormat:(NSOpenGLPixelFormat*)format
{
	if((self = [super initWithFrame:frameRect pixelFormat:format])) {
		[self awakeFromNib];
	}
	return self;
}
- (void)update
{
	CGLLockContext([[self openGLContext] CGLContextObj]);
	[super update];
	CGLUnlockContext([[self openGLContext] CGLContextObj]);
}
- (void)reshape
{
	CGLLockContext([[self openGLContext] CGLContextObj]);

	[super reshape];

	NSRect const b = [self bounds];
	glViewport(NSMinX(b), NSMinY(b), NSWidth(b), NSHeight(b));
	glLoadIdentity();
	gluOrtho2D(NSMinX(b), NSWidth(b), NSMinY(b), NSHeight(b));

	glEnable(GL_BLEND);
	glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

	glClearColor(0.0f, 0.0f, 0.0f, 1.0f);

	CGLUnlockContext([[self openGLContext] CGLContextObj]);
}

#pragma mark -NSView

- (BOOL)isOpaque
{
	return YES;
}
- (void)drawRect:(NSRect)aRect
{
	CVImageBufferRef imageBuffer = NULL;
	float frameDropStrength = 0;
	@synchronized(self) {
		imageBuffer = CVBufferRetain(_imageBuffer);
		frameDropStrength = _frameDropStrength;
	}
	GLint const magFilter = self.magFilter;
	NSSize const aspectRatio = self.aspectRatio;
	BOOL const blurFramesTogether = self.blurFramesTogether;

	[[self openGLContext] makeCurrentContext];
	CGLLockContext([[self openGLContext] CGLContextObj]);

	NSRect const b = [self bounds];
	glClear(GL_COLOR_BUFFER_BIT);
	if(imageBuffer) {
		CVOpenGLTextureRef textureBuffer = NULL;
		CVOpenGLTextureCacheCreateTextureFromImage(kCFAllocatorDefault, _cache, imageBuffer, NULL, &textureBuffer);
		CVBufferRelease(imageBuffer);
		imageBuffer = NULL;

		NSRect d = b;
		float const r = (aspectRatio.width / aspectRatio.height) / (NSWidth(b) / NSHeight(b));
		if(r > 1.0f) d.size.height *= 1.0f / r;
		else d.size.width *= r;
		d.origin = NSMakePoint(NSMidX(b) - NSWidth(d) / 2.0f, NSMidY(b) - NSHeight(d) / 2.0f);
		CGSize const s = CVImageBufferGetDisplaySize(textureBuffer);
		glColor4f(1.0f, 1.0f, 1.0f, 1.0f);

		if(blurFramesTogether) {
			glEnable(CVOpenGLTextureGetTarget(_previousTextureBuffer));
			glBindTexture(CVOpenGLTextureGetTarget(_previousTextureBuffer), CVOpenGLTextureGetName(_previousTextureBuffer));
			glTexParameteri(CVOpenGLTextureGetTarget(_previousTextureBuffer), GL_TEXTURE_MAG_FILTER, magFilter);

			glBegin(GL_QUADS);
			glTexCoord2f(0.0f, s.height);
			glVertex2f(NSMinX(d), NSMinY(d));
			glTexCoord2f(0.0f, 0.0f);
			glVertex2f(NSMinX(d), NSMaxY(d));
			glTexCoord2f(s.width, 0.0f);
			glVertex2f(NSMaxX(d), NSMaxY(d));
			glTexCoord2f(s.width, s.height);
			glVertex2f(NSMaxX(d), NSMinY(d));
			glEnd();

			glBindTexture(CVOpenGLTextureGetTarget(_previousTextureBuffer), 0);	
			glDisable(CVOpenGLTextureGetTarget(_previousTextureBuffer));
			CVOpenGLTextureRelease(_previousTextureBuffer);

			glColor4f(1.0f, 1.0f, 1.0f, 0.5f); // Draw the current frame with 50% opacity.
		}

		glEnable(CVOpenGLTextureGetTarget(textureBuffer));
		glBindTexture(CVOpenGLTextureGetTarget(textureBuffer), CVOpenGLTextureGetName(textureBuffer));
		glTexParameteri(CVOpenGLTextureGetTarget(textureBuffer), GL_TEXTURE_MAG_FILTER, magFilter);

		glBegin(GL_QUADS);
		glTexCoord2f(0.0f, s.height);
		glVertex2f(NSMinX(d), NSMinY(d));
		glTexCoord2f(0.0f, 0.0f);
		glVertex2f(NSMinX(d), NSMaxY(d));
		glTexCoord2f(s.width, 0.0f);
		glVertex2f(NSMaxX(d), NSMaxY(d));
		glTexCoord2f(s.width, s.height);
		glVertex2f(NSMaxX(d), NSMinY(d));
		glEnd();

		glBindTexture(CVOpenGLTextureGetTarget(textureBuffer), 0);	
		glDisable(CVOpenGLTextureGetTarget(textureBuffer));
		if(blurFramesTogether) _previousTextureBuffer = textureBuffer;
		else CVOpenGLTextureRelease(textureBuffer);
	}

	if(frameDropStrength > 0.01f && self.showDroppedFrames) {
		glColor4f(1.0f, 0.0f, 0.0f, frameDropStrength);
		float const t = 5.0f;
		glBegin(GL_QUADS);
		glVertex2f(NSMinX(b)    , NSMinY(b)    );
		glVertex2f(NSMinX(b)    , NSMaxY(b)    );
		glVertex2f(NSMinX(b) + t, NSMaxY(b)    );
		glVertex2f(NSMinX(b) + t, NSMinY(b)    );

		glVertex2f(NSMinX(b) + t, NSMaxY(b) - t);
		glVertex2f(NSMinX(b) + t, NSMaxY(b)    );
		glVertex2f(NSMaxX(b) - t, NSMaxY(b)    );
		glVertex2f(NSMaxX(b) - t, NSMaxY(b) - t);

		glVertex2f(NSMaxX(b) - t, NSMinY(b)    );
		glVertex2f(NSMaxX(b) - t, NSMaxY(b)    );
		glVertex2f(NSMaxX(b)    , NSMaxY(b)    );
		glVertex2f(NSMaxX(b)    , NSMinY(b)    );

		glVertex2f(NSMinX(b) + t, NSMinY(b)    );
		glVertex2f(NSMinX(b) + t, NSMinY(b) + t);
		glVertex2f(NSMaxX(b) - t, NSMinY(b) + t);
		glVertex2f(NSMaxX(b) - t, NSMinY(b)    );
		glEnd();
	}

	NSWindow *const w = [self window];
	if([w styleMask] & NSResizableWindowMask && [w showsResizeIndicator]) {
		glBegin(GL_LINES);
		glColor4f(0.85f, 0.85f, 0.85f, 0.5f);
		glVertex2f(NSMaxX(b) - 2.0f, NSMinY(b) + 1.0f);
		glVertex2f(NSMaxX(b) - 1.0f, NSMinY(b) + 2.0f);
		glVertex2f(NSMaxX(b) - 6.0f, NSMinY(b) + 1.0f);
		glVertex2f(NSMaxX(b) - 1.0f, NSMinY(b) + 6.0f);
		glVertex2f(NSMaxX(b) - 10.0f, NSMinY(b) + 1.0f);
		glVertex2f(NSMaxX(b) - 1.0f, NSMinY(b) + 10.0f);

		glColor4f(0.15f, 0.15f, 0.15f, 0.5f);
		glVertex2f(NSMaxX(b) - 3.0f, NSMinY(b) + 1.0f);
		glVertex2f(NSMaxX(b) - 1.0f, NSMinY(b) + 3.0f);
		glVertex2f(NSMaxX(b) - 7.0f, NSMinY(b) + 1.0f);
		glVertex2f(NSMaxX(b) - 1.0f, NSMinY(b) + 7.0f);
		glVertex2f(NSMaxX(b) - 11.0f, NSMinY(b) + 1.0f);
		glVertex2f(NSMaxX(b) - 1.0f, NSMinY(b) + 11.0f);

		glColor4f(0.0f, 0.0f, 0.0f, 0.15f);
		glVertex2f(NSMaxX(b) - 4.0f, NSMinY(b) + 1.0f);
		glVertex2f(NSMaxX(b) - 1.0f, NSMinY(b) + 4.0f);
		glVertex2f(NSMaxX(b) - 8.0f, NSMinY(b) + 1.0f);
		glVertex2f(NSMaxX(b) - 1.0f, NSMinY(b) + 8.0f);
		glVertex2f(NSMaxX(b) - 12.0f, NSMinY(b) + 1.0f);
		glVertex2f(NSMaxX(b) - 1.0f, NSMinY(b) + 12.0f);
		glEnd();
	}

	glFlush();
	if(!(++_flushCacheCounter % 300)) CVOpenGLTextureCacheFlush(_cache, 0);
	CGLUnlockContext([[self openGLContext] CGLContextObj]);
}

#pragma mark -NSResponder

- (BOOL)acceptsFirstResponder
{
	return YES;
}
- (void)keyDown:(NSEvent *)anEvent
{
	if(![self.delegate videoView:self handleKeyDown:anEvent]) [super keyDown:anEvent];
}

#pragma mark -NSObject

- (void)dealloc
{
	self.imageBuffer = nil;
	CVOpenGLTextureRelease(_previousTextureBuffer);
	CVOpenGLTextureCacheRelease(_cache);
	[super dealloc];
}

#pragma mark -NSObejct(NSKeyboardUI)

- (BOOL)canBecomeKeyView
{
	return YES;
}

#pragma mark -NSObject(NSNibAwaking)

- (void)awakeFromNib
{
	CVOpenGLTextureCacheCreate(kCFAllocatorDefault, NULL, [[self openGLContext] CGLContextObj], [[self pixelFormat] CGLPixelFormatObj], (CFDictionaryRef)[NSDictionary dictionaryWithObjectsAndKeys:
		(NSString *)kCVOpenGLTextureCacheChromaSamplingModeBestPerformance, (NSString *)kCVOpenGLTextureCacheChromaSamplingModeKey,
		nil], &_cache);
}

@end

@implementation NSObject (MPLVideoViewDelegate)

- (BOOL)videoView:(MPLVideoView *)sender
        handleKeyDown:(NSEvent *)anEvent
{
	return NO;
}

@end
