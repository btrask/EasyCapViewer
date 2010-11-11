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
#import "ECVVideoView.h"
#import <OpenGL/gl.h>
#import <OpenGL/glext.h>
#import <OpenGL/glu.h>

// Models
#import "ECVVideoStorage.h"
#import "ECVVideoFrame.h"

// Other Sources
#import "ECVAppKitAdditions.h"
#import "ECVDebug.h"
#import "ECVOpenGLAdditions.h"

NS_INLINE GLenum ECVPixelFormatTypeToGLFormat(OSType t)
{
	switch(t) {
		case kCVPixelFormatType_422YpCbCr8: return GL_YCBCR_422_APPLE;
	}
	return 0;
}
NS_INLINE GLenum ECVPixelFormatTypeToGLType(OSType t)
{
	switch(t) {
#if __LITTLE_ENDIAN__
		case kCVPixelFormatType_422YpCbCr8: return GL_UNSIGNED_SHORT_8_8_APPLE;
#else
		case kCVPixelFormatType_422YpCbCr8: return GL_UNSIGNED_SHORT_8_8_REV_APPLE;
#endif
	}
	return 0;
}

@interface ECVVideoView(Private)

- (GLuint)_textureNameAtIndex:(NSUInteger)index;

- (void)_drawOneFrame;
- (void)_drawFrame:(ECVVideoFrame *)frame;
- (void)_drawFrameDropIndicatorWithStrength:(CGFloat)strength;
- (void)_drawCropAdjustmentBox;
- (void)_drawResizeHandle;

@end

static CVReturn ECVDisplayLinkOutputCallback(CVDisplayLinkRef displayLink, const CVTimeStamp *inNow, const CVTimeStamp *inOutputTime, CVOptionFlags flagsIn, CVOptionFlags *flagsOut, ECVVideoView *view)
{
	NSAutoreleasePool *const pool = [[NSAutoreleasePool alloc] init];
	[view _drawOneFrame];
	[pool drain];
	return kCVReturnSuccess;
}

@implementation ECVVideoView

#pragma mark -ECVVideoView

- (void)startDrawing
{
	if(!_displayLink) {
		ECVCVReturn(CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink));
		ECVCVReturn(CVDisplayLinkSetOutputCallback(_displayLink, (CVDisplayLinkOutputCallback)ECVDisplayLinkOutputCallback, self));
		[self windowDidChangeScreenProfile:nil];
	}
	ECVCVReturn(CVDisplayLinkStart(_displayLink));
}
- (void)stopDrawing
{
	ECVCVReturn(CVDisplayLinkStop(_displayLink));
	[self setNeedsDisplay:YES];
}

#pragma mark -

@synthesize delegate;
- (ECVVideoStorage *)videoStorage
{
	return [[_videoStorage retain] autorelease];
}
- (void)setVideoStorage:(ECVVideoStorage *)storage
{
	if(storage == _videoStorage) return;
	CGLContextObj const contextObj = ECVLockContext([self openGLContext]);
	ECVGLError(glEnable(GL_TEXTURE_RECTANGLE_EXT));

	if(_textureNames) ECVGLError(glDeleteTextures([_videoStorage numberOfBuffers], [_textureNames bytes]));
	[_textureNames release];
	[_frames release];

	[_videoStorage release];
	_videoStorage = [storage retain];

	ECVGLError(glTextureRangeAPPLE(GL_TEXTURE_RECTANGLE_EXT, [_videoStorage bufferSize] * [_videoStorage numberOfBuffers], [_videoStorage allBufferBytes]));
	_textureNames = [[NSMutableData alloc] initWithLength:[_videoStorage numberOfBuffers] * sizeof(GLuint)];
	ECVGLError(glGenTextures([_videoStorage numberOfBuffers], [_textureNames mutableBytes]));
	_frames = [[NSMutableArray alloc] init];

	ECVPixelSize const s = [_videoStorage pixelSize];
	GLenum const format = ECVPixelFormatTypeToGLFormat([_videoStorage pixelFormatType]);
	GLenum const type = ECVPixelFormatTypeToGLType([_videoStorage pixelFormatType]);
	NSUInteger i = 0;
	for(; i < [_videoStorage numberOfBuffers]; i++) {
		ECVGLError(glBindTexture(GL_TEXTURE_RECTANGLE_EXT, [self _textureNameAtIndex:i]));
		ECVGLError(glTexParameteri(GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_STORAGE_HINT_APPLE, GL_STORAGE_CACHED_APPLE));
		ECVGLError(glPixelStorei(GL_UNPACK_CLIENT_STORAGE_APPLE, GL_TRUE));
		ECVGLError(glTexParameteri(GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_MAG_FILTER, [self magFilter]));
		ECVGLError(glTexImage2D(GL_TEXTURE_RECTANGLE_EXT, 0, GL_RGB, s.width, s.height, 0, format, type, [_videoStorage bufferBytesAtIndex:i]));
	}

	ECVGLError(glDisable(GL_TEXTURE_RECTANGLE_EXT));
	ECVUnlockContext(contextObj);
}
- (NSSize)aspectRatio
{
	CGLContextObj const contextObj = ECVLockContext([self openGLContext]);
	NSSize const r = _aspectRatio;
	ECVUnlockContext(contextObj);
	return r;
}
- (void)setAspectRatio:(NSSize)ratio
{
	CGLContextObj const contextObj = ECVLockContext([self openGLContext]);
	_aspectRatio = ratio;
	ECVUnlockContext(contextObj);
	[self reshape];
}
- (NSRect)cropRect
{
	CGLContextObj const contextObj = ECVLockContext([self openGLContext]);
	NSRect const r = _cropRect;
	ECVUnlockContext(contextObj);
	return r;
}
- (void)setCropRect:(NSRect)aRect
{
	CGLContextObj const contextObj = ECVLockContext([self openGLContext]);
	_cropRect = aRect;
	ECVUnlockContext(contextObj);
	[self setNeedsDisplay:YES];
}
- (BOOL)vsync
{
	CGLContextObj const contextObj = ECVLockContext([self openGLContext]);
	BOOL const r = _vsync;
	ECVUnlockContext(contextObj);
	return r;
}
- (void)setVsync:(BOOL)flag
{
	CGLContextObj const contextObj = ECVLockContext([self openGLContext]);
	_vsync = flag;
	GLint params[] = {!!flag};
	CGLSetParameter(CGLGetCurrentContext(), kCGLCPSwapInterval, params);
	ECVUnlockContext(contextObj);
}
- (GLint)magFilter
{
	CGLContextObj const contextObj = ECVLockContext([self openGLContext]);
	GLint const r = _magFilter;
	ECVUnlockContext(contextObj);
	return r;
}
- (void)setMagFilter:(GLint)filter
{
	CGLContextObj const contextObj = ECVLockContext([self openGLContext]);
	_magFilter = filter;
	NSUInteger i = 0;
	if(_textureNames) for(; i < [_videoStorage numberOfBuffers]; i++) {
		ECVGLError(glBindTexture(GL_TEXTURE_RECTANGLE_EXT, [self _textureNameAtIndex:i]));
		ECVGLError(glTexParameteri(GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_MAG_FILTER, _magFilter));
	}
	ECVUnlockContext(contextObj);
	[self setNeedsDisplay:YES];
}
@synthesize showDroppedFrames = _showDroppedFrames;
- (NSCell<ECVVideoViewCell> *)cell
{
	return [[_cell retain] autorelease];
}
- (void)setCell:(NSCell<ECVVideoViewCell> *)cell
{
	if(cell == _cell) return;
	[_cell release];
	_cell = [cell retain];
	[self setNeedsDisplay:YES];
	[[self window] invalidateCursorRectsForView:self];
}
- (void)pushFrame:(ECVVideoFrame *)frame
{
	if(!frame) return;
	CGLContextObj const contextObj = ECVLockContext([self openGLContext]);
	if([_videoStorage dropFramesFromArray:_frames]) _frameDropStrength = 1.0f;
	[_frames insertObject:frame atIndex:0];
	ECVUnlockContext(contextObj);
}

#pragma mark -ECVVideoView(Private)

- (GLuint)_textureNameAtIndex:(NSUInteger)i
{
	if(NSNotFound == i) return 0;
	return ((GLuint *)[_textureNames mutableBytes])[i];
}

#pragma mark -

- (void)_drawOneFrame
{
	CGLContextObj const contextObj = ECVLockContext([self openGLContext]);
	glClear(GL_COLOR_BUFFER_BIT);

	ECVVideoFrame *frame = nil;
	while([_frames count]) {
		frame = [[[_frames lastObject] retain] autorelease];
		[_frames removeLastObject];
		if([frame lockIfHasBuffer]) break;
		frame = nil;
	}
	if(!frame) {
		frame = [_videoStorage newestCompletedFrame];
		if(![frame lockIfHasBuffer]) frame = nil;
	}

	[self _drawFrame:frame];
	if(frame) _frameDropStrength *= 0.75f;
	else _frameDropStrength = 1.0f;
	[self _drawFrameDropIndicatorWithStrength:_frameDropStrength];
	[[self cell] drawWithFrame:_outputRect inVideoView:self playing:YES];
	[self _drawResizeHandle];
	glFinish();
	[frame unlock];

	ECVUnlockContext(contextObj);
}
- (void)_drawFrame:(ECVVideoFrame *)frame
{
	if(!frame) return;
	ECVGLError(glEnable(GL_TEXTURE_RECTANGLE_EXT));
	ECVPixelSize const s = [_videoStorage pixelSize];
	OSType const f = [_videoStorage pixelFormatType];
	ECVGLError(glBindTexture(GL_TEXTURE_RECTANGLE_EXT, [self _textureNameAtIndex:[frame bufferIndex]]));
	ECVGLError(glTexSubImage2D(GL_TEXTURE_RECTANGLE_EXT, 0, 0, 0, s.width, s.height, ECVPixelFormatTypeToGLFormat(f), ECVPixelFormatTypeToGLType(f), [frame bufferBytes]));
	glColor4f(1.0f, 1.0f, 1.0f, 1.0f);
	ECVGLDrawTextureInRectWithBounds(_outputRect, ECVScaledRect(_cropRect, ECVPixelSizeToNSSize(s)));
	ECVGLError(glDisable(GL_TEXTURE_RECTANGLE_EXT));
}
- (void)_drawFrameDropIndicatorWithStrength:(CGFloat)strength
{
	if(strength < 0.01f || ![self showDroppedFrames]) return;
	NSRect const b = [self bounds];
	glColor4f(1.0f, 0.0f, 0.0f, strength);
	ECVGLDrawBorder(NSInsetRect(b, 5.0f, 5.0f), b);
}
- (void)_drawResizeHandle
{
	NSWindow *const w = [self window];
	if(!w || ![w showsResizeIndicator] || !([w styleMask] & NSResizableWindowMask)) return;
	NSRect const b = [self bounds];

	glBegin(GL_LINES);
	glColor4f(0.85f, 0.85f, 0.85f, 0.5f);
	glVertex2f(NSMaxX(b) -  2.0f, NSMaxY(b) -  1.0f);
	glVertex2f(NSMaxX(b) -  1.0f, NSMaxY(b) -  2.0f);
	glVertex2f(NSMaxX(b) -  6.0f, NSMaxY(b) -  1.0f);
	glVertex2f(NSMaxX(b) -  1.0f, NSMaxY(b) -  6.0f);
	glVertex2f(NSMaxX(b) - 10.0f, NSMaxY(b) -  1.0f);
	glVertex2f(NSMaxX(b) -  1.0f, NSMaxY(b) - 10.0f);

	glColor4f(0.15f, 0.15f, 0.15f, 0.5f);
	glVertex2f(NSMaxX(b) -  3.0f, NSMaxY(b) -  1.0f);
	glVertex2f(NSMaxX(b) -  1.0f, NSMaxY(b) -  3.0f);
	glVertex2f(NSMaxX(b) -  7.0f, NSMaxY(b) -  1.0f);
	glVertex2f(NSMaxX(b) -  1.0f, NSMaxY(b) -  7.0f);
	glVertex2f(NSMaxX(b) - 11.0f, NSMaxY(b) -  1.0f);
	glVertex2f(NSMaxX(b) -  1.0f, NSMaxY(b) - 11.0f);

	glColor4f(0.0f, 0.0f, 0.0f, 0.15f);
	glVertex2f(NSMaxX(b) -  4.0f, NSMaxY(b) -  1.0f);
	glVertex2f(NSMaxX(b) -  1.0f, NSMaxY(b) -  4.0f);
	glVertex2f(NSMaxX(b) -  8.0f, NSMaxY(b) -  1.0f);
	glVertex2f(NSMaxX(b) -  1.0f, NSMaxY(b) -  8.0f);
	glVertex2f(NSMaxX(b) - 12.0f, NSMaxY(b) -  1.0f);
	glVertex2f(NSMaxX(b) -  1.0f, NSMaxY(b) - 12.0f);
	glEnd();
}

#pragma mark -NSOpenGLView

- (id)initWithFrame:(NSRect)aRect pixelFormat:(NSOpenGLPixelFormat *)format
{
	if((self = [super initWithFrame:aRect pixelFormat:format])) {
		[self awakeFromNib];
	}
	return self;
}

#pragma mark -

- (void)update
{
	CGLContextObj const contextObj = ECVLockContext([self openGLContext]);
	[super update];
	ECVUnlockContext(contextObj);
}
- (void)reshape
{
	CGLContextObj const contextObj = ECVLockContext([self openGLContext]);

	[super reshape];

	NSRect const b = [self bounds];
	NSSize const aspectRatio = [self aspectRatio];
	_outputRect = b;
	CGFloat const r = (aspectRatio.width / aspectRatio.height) / (NSWidth(b) / NSHeight(b));
	if(r > 1.0f) _outputRect.size.height *= 1.0f / r;
	else _outputRect.size.width *= r;
	_outputRect.origin = NSMakePoint(NSMidX(b) - NSWidth(_outputRect) / 2.0f, NSMidY(b) - NSHeight(_outputRect) / 2.0f);

	glViewport(NSMinX(b), NSMinY(b), NSWidth(b), NSHeight(b));
	glLoadIdentity();
	gluOrtho2D(NSMinX(b), NSMaxX(b), NSMaxY(b), NSMinY(b));

	ECVGLError(glEnable(GL_BLEND));
	ECVGLError(glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA));

	glClearColor(0.0f, 0.0f, 0.0f, 1.0f);

	ECVUnlockContext(contextObj);
}

#pragma mark -NSView

- (BOOL)isFlipped
{
	return YES;
}
- (BOOL)isOpaque
{
	return YES;
}
- (void)drawRect:(NSRect)aRect
{
	CGLContextObj const contextObj = ECVLockContext([self openGLContext]);

	glClear(GL_COLOR_BUFFER_BIT);
	ECVVideoFrame *frame = [_videoStorage newestCompletedFrame];
	if(![frame lockIfHasBuffer]) frame = nil;
	[self _drawFrame:frame];
	[[self cell] drawWithFrame:_outputRect inVideoView:self playing:CVDisplayLinkIsRunning(_displayLink)];
	[self _drawResizeHandle];
	glFinish();
	[frame unlock];

	ECVUnlockContext(contextObj);
}
- (void)resetCursorRects
{
	[[self cell] resetCursorRect:_outputRect inView:self];
}
- (void)viewWillMoveToWindow:(NSWindow *)aWindow
{
	if([self window]) {
		[[NSNotificationCenter defaultCenter] removeObserver:self name:NSWindowDidChangeScreenNotification object:[self window]];
		[[NSNotificationCenter defaultCenter] removeObserver:self name:NSWindowDidChangeScreenProfileNotification object:[self window]];
	}
	if(aWindow) {
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowDidChangeScreen:) name:NSWindowDidChangeScreenNotification object:aWindow];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowDidChangeScreenProfile:) name:NSWindowDidChangeScreenProfileNotification object:aWindow];
	}
}
- (void)viewDidMoveToWindow
{
	[self windowDidChangeScreenProfile:nil];
}

#pragma mark -NSResponder

- (BOOL)acceptsFirstResponder
{
	return YES;
}
- (void)keyDown:(NSEvent *)anEvent
{
	if(![[self delegate] videoView:self handleKeyDown:anEvent]) [super keyDown:anEvent];
}
- (void)mouseDown:(NSEvent *)anEvent
{
	NSCell *const cell = [self cell];
	if([[cell class] prefersTrackingUntilMouseUp]) {
		[cell trackMouse:anEvent inRect:_outputRect ofView:self untilMouseUp:YES];
		return;
	}
	BOOL const playing = CVDisplayLinkIsRunning(_displayLink);
	NSEvent *latestEvent = anEvent;
	do {
		if([self mouse:[self convertPoint:[latestEvent locationInWindow] fromView:nil] inRect:_outputRect]) {
			[cell setHighlighted:YES];
			if(!playing) [self setNeedsDisplay:YES];
			if([cell trackMouse:latestEvent inRect:_outputRect ofView:self untilMouseUp:NO]) break;
			[cell setHighlighted:NO];
			if(!playing) [self setNeedsDisplay:YES];
		}
		latestEvent = [[self window] nextEventMatchingMask:NSLeftMouseUpMask | NSLeftMouseDraggedMask untilDate:[NSDate distantFuture] inMode:NSEventTrackingRunLoopMode dequeue:YES];
	} while([latestEvent type] != NSLeftMouseUp);
	[[self window] discardEventsMatchingMask:NSAnyEventMask beforeEvent:latestEvent];
	[cell setHighlighted:NO];
	if(!playing) [self setNeedsDisplay:YES];
}

#pragma mark -NSObject

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	if(_displayLink && CVDisplayLinkIsRunning(_displayLink)) ECVCVReturn(CVDisplayLinkStop(_displayLink));

	ECVGLError(glTextureRangeAPPLE(GL_TEXTURE_RECTANGLE_EXT, 0, NULL));
	ECVGLError(glDeleteTextures([[self videoStorage] numberOfBuffers], [_textureNames bytes]));

	[_videoStorage release];
	[_textureNames release];
	[_frames release];
	CVDisplayLinkRelease(_displayLink);
	[_cell release];
	[super dealloc];
}

#pragma mark -NSObject(NSNibAwaking)

- (void)awakeFromNib
{
	_cropRect = ECVUncroppedRect;
	_magFilter = GL_LINEAR;
}

#pragma mark -<NSWindowDelegate>

- (void)windowDidChangeScreen:(NSNotification *)aNotif
{
	[self windowDidChangeScreenProfile:nil];
}
- (void)windowDidChangeScreenProfile:(NSNotification *)aNotif
{
	if(!_displayLink) return;
	BOOL const drawing = CVDisplayLinkIsRunning(_displayLink);
	if(drawing) [self stopDrawing];
	ECVCVReturn(CVDisplayLinkSetCurrentCGDisplayFromOpenGLContext(_displayLink, [[self openGLContext] CGLContextObj], [[self pixelFormat] CGLPixelFormatObj]));
	if(drawing) [self startDrawing];
}

@end

@implementation NSObject(ECVVideoViewDelegate)

- (BOOL)videoView:(ECVVideoView *)sender handleKeyDown:(NSEvent *)anEvent
{
	return NO;
}

@end
