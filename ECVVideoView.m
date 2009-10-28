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

// Other Sources
#import "ECVDebug.h"
#import "ECVOpenGLAdditions.h"

#define ECVMaxPendingDisplayFrames 1
#define ECVMaxPendingAttachedFrames 1
#define ECVFieldBuffersPerFrame 2

#define ECVCurrentFillBuffers 1
#define ECVPreviousFillBuffers 1
#define ECVCurrentDrawBuffers 1
#define ECVUnassignedBuffers 1
#define ECVMaxPendingDisplayBuffers (ECVFieldBuffersPerFrame * ECVMaxPendingDisplayFrames)
#define ECVMaxPendingAttachedBuffers (ECVFieldBuffersPerFrame * ECVMaxPendingAttachedFrames)

#define ECVRequiredBufferCount (ECVCurrentFillBuffers + ECVPreviousFillBuffers + ECVCurrentDrawBuffers + ECVUnassignedBuffers + ECVMaxPendingDisplayBuffers + ECVMaxPendingAttachedBuffers)

NS_INLINE size_t ECVPixelFormatTypeBytesPerPixel(OSType t)
{
	switch(t) {
		case kCVPixelFormatType_422YpCbCr8: return 2;
	}
	return 0;
}
NS_INLINE uint64_t ECVPixelFormatBlackPattern(OSType t)
{
	switch(t) {
		case kCVPixelFormatType_422YpCbCr8: return CFSwapInt64HostToBig(0x8010801080108010ULL);
	}
	return 0;
}
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
		case kCVPixelFormatType_422YpCbCr8: return GL_UNSIGNED_SHORT_8_8_APPLE;
	}
	return 0;
}

@interface ECVAttachedFrame : NSObject <ECVFrameReading>
{
	@private
	ECVVideoView *_videoView;
	NSUInteger _bufferIndex;
	NSLock *_videoViewLock;
}

- (id)initWithVideoView:(ECVVideoView *)view bufferIndex:(NSUInteger)index;
@property(readonly) NSUInteger bufferIndex;
- (void)invalidateWait:(BOOL)wait;
- (void)invalidate;
- (void)tryToInvalidate;

@end

@interface ECVVideoView(Private)

- (GLuint)_textureNameAtIndex:(NSUInteger)index;
- (void)_invalidateFrame:(ECVAttachedFrame *)frame;

- (void)_drawOneFrame;
- (void)_drawBuffer:(NSUInteger)index;
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

- (void)setPixelFormat:(OSType)formatType size:(ECVPixelSize)size
{
	[self resetFrames];

	NSOpenGLContext *const context = [self openGLContext];
	CGLContextObj const contextObj = [context CGLContextObj];
	[context makeCurrentContext];
	CGLLockContext(contextObj);
	ECVGLError(glEnable(GL_TEXTURE_RECTANGLE_EXT));

	NSUInteger i;

	_blurredBufferIndex = NSNotFound;

	[_bufferPoolLock lock];
	_pixelFormatType = formatType;
	_pixelSize = size;
	_bufferSize = _pixelSize.width * _pixelSize.height * ECVPixelFormatTypeBytesPerPixel(_pixelFormatType);
	_currentDrawBufferIndex = NSNotFound;
	[_bufferPoolLock unlock];

	[_attachedFrameLock lock];
	[_attachedFrames makeObjectsPerformSelector:@selector(invalidate)];
	[_attachedFrameLock unlock];

	if(_textureNames) ECVGLError(glDeleteTextures(ECVRequiredBufferCount, [_textureNames bytes]));
	[_textureNames release];
	_textureNames = [[NSMutableData alloc] initWithLength:sizeof(GLuint) * ECVRequiredBufferCount];
	ECVGLError(glGenTextures(ECVRequiredBufferCount, [_textureNames mutableBytes]));

	ECVGLError(glTextureRangeAPPLE(GL_TEXTURE_RECTANGLE_EXT, 0, NULL));
	[_bufferData release];
	_bufferData = [[NSMutableData alloc] initWithLength:_bufferSize * ECVRequiredBufferCount];
	ECVGLError(glTextureRangeAPPLE(GL_TEXTURE_RECTANGLE_EXT, [_bufferData length], [_bufferData bytes]));

	GLenum const format = ECVPixelFormatTypeToGLFormat(_pixelFormatType);
	GLenum const type = ECVPixelFormatTypeToGLType(_pixelFormatType);
	for(i = 0; i < ECVRequiredBufferCount; i++) {
		ECVGLError(glBindTexture(GL_TEXTURE_RECTANGLE_EXT, [self _textureNameAtIndex:i]));
		ECVGLError(glTexParameteri(GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_STORAGE_HINT_APPLE, GL_STORAGE_CACHED_APPLE));
		ECVGLError(glPixelStorei(GL_UNPACK_CLIENT_STORAGE_APPLE, GL_TRUE));
		ECVGLError(glTexParameteri(GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_MAG_FILTER, self.magFilter));
		ECVGLError(glTexImage2D(GL_TEXTURE_RECTANGLE_EXT, 0, GL_RGB, _pixelSize.width, _pixelSize.height, 0, format, type, [self bufferBytesAtIndex:i]));
		[self clearBufferAtIndex:i];
	}

	ECVGLError(glDisable(GL_TEXTURE_RECTANGLE_EXT));
	CGLUnlockContext(contextObj);
}
- (NSUInteger)bufferIndexByBlurringPastFrames
{
	NSUInteger const blurredBufferIndex = _blurredBufferIndex;
	_blurredBufferIndex = _currentFillBufferIndex;
	if(NSNotFound == _currentFillBufferIndex || NSNotFound == blurredBufferIndex) return _currentFillBufferIndex;
	UInt8 *const src = [self bufferBytesAtIndex:_currentFillBufferIndex];
	UInt8 *const dst = [self bufferBytesAtIndex:blurredBufferIndex];
	NSUInteger i;
	for(i = 0; i < _bufferSize; i++) dst[i] = dst[i] / 2 + src[i] / 2;
	return blurredBufferIndex;
}
- (NSUInteger)nextFillBufferIndex:(NSUInteger)bufferToDraw
{
	[_attachedFrameLock lock];
	NSUInteger const attachedFrameCount = [_attachedFrames count];
	NSUInteger const keep = attachedFrameCount % ECVMaxPendingAttachedBuffers;
	if(attachedFrameCount > ECVMaxPendingAttachedBuffers) [[_attachedFrames subarrayWithRange:NSMakeRange(keep, attachedFrameCount - keep)] makeObjectsPerformSelector:@selector(tryToInvalidate)];
	NSIndexSet *const attachedFrameIndexes = [[_attachedFrameIndexes copy] autorelease];
	[_attachedFrameLock unlock];

	[_bufferPoolLock lock];
	NSUInteger const readyBufferCount = [_readyBufferIndexQueue count];
	if(readyBufferCount > ECVMaxPendingDisplayBuffers) {
		NSUInteger const keep = readyBufferCount % ECVMaxPendingDisplayBuffers;
		[_readyBufferIndexQueue removeObjectsInRange:NSMakeRange(keep, readyBufferCount - keep)];
		_frameDropStrength = 1.0f;
	} else _frameDropStrength *= 0.75f;
	NSArray *const readyBufferIndexQueue = [[_readyBufferIndexQueue copy] autorelease];
	NSUInteger const lastDrawnBufferIndex = _currentDrawBufferIndex;
	[_bufferPoolLock unlock];

	NSUInteger i;
	for(i = 0; i < ECVRequiredBufferCount; i++) {
		if(_currentFillBufferIndex == i || bufferToDraw == i || lastDrawnBufferIndex == i) continue;
		if([attachedFrameIndexes containsIndex:i]) continue;
		if([readyBufferIndexQueue containsObject:[NSNumber numberWithUnsignedInteger:i]]) continue;
		return i;
	}
	return NSNotFound;
}
- (void)drawBufferIndex:(NSUInteger)index
{
	if(NSNotFound == index) return;
	[_bufferPoolLock lock];
	[_readyBufferIndexQueue insertObject:[NSNumber numberWithUnsignedInteger:index] atIndex:0];
	[_bufferPoolLock unlock];
}
- (id<ECVFrameReading>)frameWithBufferAtIndex:(NSUInteger)index
{
	if(NSNotFound == index) return nil;
	ECVAttachedFrame *const frame = [[[ECVAttachedFrame alloc] initWithVideoView:self bufferIndex:index] autorelease];
	[_attachedFrameLock lock];
	[_attachedFrames insertObject:frame atIndex:0];
	[_attachedFrameIndexes addIndex:index];
	[_attachedFrameLock unlock];
	return frame;
}
- (void *)bufferBytesAtIndex:(NSUInteger)index
{
	if(NSNotFound == index) return NULL;
	return (char *)[_bufferData mutableBytes] + _bufferSize * index;
}
- (void)clearBufferAtIndex:(NSUInteger)index
{
	if(NSNotFound == index) return;
	uint64_t const val = ECVPixelFormatBlackPattern(_pixelFormatType);
	memset_pattern8([self bufferBytesAtIndex:index], &val, self.bufferSize);
}
- (void)resetFrames
{
	[_bufferPoolLock lock];
	[_readyBufferIndexQueue removeAllObjects];
	_frameDropStrength = 0.0f;
	[_bufferPoolLock unlock];
	_currentFillBufferIndex = NSNotFound;
}
@synthesize currentFillBufferIndex = _currentFillBufferIndex;

#pragma mark -

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
@synthesize aspectRatio = _aspectRatio;
- (void)setAspectRatio:(NSSize)ratio
{
	NSOpenGLContext *const context = [self openGLContext];
	CGLContextObj const contextObj = [context CGLContextObj];
	[context makeCurrentContext];
	CGLLockContext(contextObj);
	_aspectRatio = ratio;
	CGLUnlockContext(contextObj);
	[self reshape];
}
@synthesize cropRect = _cropRect;
- (void)setCropRect:(NSRect)aRect
{
	NSOpenGLContext *const context = [self openGLContext];
	CGLContextObj const contextObj = [context CGLContextObj];
	[context makeCurrentContext];
	CGLLockContext(contextObj);
	_cropRect = aRect;
	CGLUnlockContext(contextObj);
	[self setNeedsDisplay:YES];
}
@synthesize vsync = _vsync;
- (void)setVsync:(BOOL)flag
{
	NSOpenGLContext *const context = [self openGLContext];
	CGLContextObj const contextObj = [context CGLContextObj];
	[context makeCurrentContext];
	CGLLockContext(contextObj);
	_vsync = flag;
	GLint params[] = {!!flag};
	CGLSetParameter(CGLGetCurrentContext(), kCGLCPSwapInterval, params);
	CGLUnlockContext(contextObj);
}
@synthesize magFilter = _magFilter;
- (void)setMagFilter:(GLint)filter
{
	NSOpenGLContext *const context = [self openGLContext];
	CGLContextObj const contextObj = [context CGLContextObj];
	[context makeCurrentContext];
	CGLLockContext(contextObj);
	_magFilter = filter;
	NSUInteger i = 0;
	if(_textureNames) for(; i < ECVRequiredBufferCount; i++) {
		ECVGLError(glBindTexture(GL_TEXTURE_RECTANGLE_EXT, [self _textureNameAtIndex:i]));
		ECVGLError(glTexParameteri(GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_MAG_FILTER, _magFilter));
	}
	CGLUnlockContext(contextObj);
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

#pragma mark -

- (NSUInteger)currentDrawBufferIndex
{
	[_bufferPoolLock lock];
	NSUInteger const i = _currentDrawBufferIndex;
	[_bufferPoolLock unlock];
	return i;
}

#pragma mark -ECVVideoView(Private)

- (GLuint)_textureNameAtIndex:(NSUInteger)index
{
	if(NSNotFound == index) return 0;
	return ((GLuint *)[_textureNames mutableBytes])[index];
}
- (void)_invalidateFrame:(ECVAttachedFrame *)frame
{
	[_attachedFrameLock lock];
	[_attachedFrames removeObjectIdenticalTo:frame];
	[_attachedFrameIndexes removeIndex:frame.bufferIndex];
	[_attachedFrameLock unlock];
}

#pragma mark -

- (void)_drawOneFrame
{
	[_bufferPoolLock lock];
	NSNumber *const number = [_readyBufferIndexQueue lastObject];
	CGFloat const frameDropStrength = _frameDropStrength;
	NSCell<ECVVideoViewCell> *cell = self.cell;
	[_bufferPoolLock unlock];
	if(!number) return;

	NSUInteger const index = [number unsignedIntegerValue];
	NSParameterAssert(NSNotFound != index);

	NSOpenGLContext *const context = [self openGLContext];
	CGLContextObj const contextObj = [context CGLContextObj];
	[context makeCurrentContext];
	CGLLockContext(contextObj);
	glClear(GL_COLOR_BUFFER_BIT);
	[self _drawBuffer:index];
	[self _drawFrameDropIndicatorWithStrength:frameDropStrength];
	[cell drawWithFrame:_outputRect inVideoView:self playing:YES];
	[self _drawResizeHandle];
	glFlush();
	CGLUnlockContext(contextObj);

	[_bufferPoolLock lock];
	[_readyBufferIndexQueue removeLastObject];
	_currentDrawBufferIndex = index;
	[_bufferPoolLock unlock];
}
- (void)_drawBuffer:(NSUInteger)index
{
	ECVGLError(glEnable(GL_TEXTURE_RECTANGLE_EXT));
	ECVGLError(glBindTexture(GL_TEXTURE_RECTANGLE_EXT, [self _textureNameAtIndex:index]));
	ECVGLError(glTexSubImage2D(GL_TEXTURE_RECTANGLE_EXT, 0, 0, 0, _pixelSize.width, _pixelSize.height, ECVPixelFormatTypeToGLFormat(_pixelFormatType), ECVPixelFormatTypeToGLType(_pixelFormatType), [self bufferBytesAtIndex:index]));
	glColor4f(1.0f, 1.0f, 1.0f, 1.0f);
	ECVGLDrawTextureInRectWithBounds(_outputRect, ECVScaledRect(_cropRect, ECVPixelSizeToSize(_pixelSize)));
	ECVGLError(glDisable(GL_TEXTURE_RECTANGLE_EXT));
}
- (void)_drawFrameDropIndicatorWithStrength:(CGFloat)strength
{
	if(strength < 0.01f || !self.showDroppedFrames) return;
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
	NSOpenGLContext *const context = [self openGLContext];
	CGLContextObj const contextObj = [context CGLContextObj];
	[context makeCurrentContext];
	CGLLockContext(contextObj);
	[super update];
	CGLUnlockContext(contextObj);
}
- (void)reshape
{
	NSOpenGLContext *const context = [self openGLContext];
	CGLContextObj const contextObj = [context CGLContextObj];
	[context makeCurrentContext];
	CGLLockContext(contextObj);

	[super reshape];

	NSRect const b = [self bounds];
	NSSize const aspectRatio = self.aspectRatio;
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

	CGLUnlockContext(contextObj);
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
	NSOpenGLContext *const context = [self openGLContext];
	CGLContextObj const contextObj = [context CGLContextObj];
	[context makeCurrentContext];
	CGLLockContext(contextObj);

	glClear(GL_COLOR_BUFFER_BIT);
	[_bufferPoolLock lock];
	if(NSNotFound != _currentDrawBufferIndex) [self _drawBuffer:_currentDrawBufferIndex];
	[_bufferPoolLock unlock];
	[self.cell drawWithFrame:_outputRect inVideoView:self playing:CVDisplayLinkIsRunning(_displayLink)];
	[self _drawResizeHandle];
	glFlush();

	CGLUnlockContext(contextObj);
}
- (void)resetCursorRects
{
	[self.cell resetCursorRect:_outputRect inView:self];
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
	if(![self.delegate videoView:self handleKeyDown:anEvent]) [super keyDown:anEvent];
}
- (void)mouseDown:(NSEvent *)anEvent
{
	if([[self.cell class] prefersTrackingUntilMouseUp]) {
		[self.cell trackMouse:anEvent inRect:_outputRect ofView:self untilMouseUp:YES];
		return;
	}
	BOOL const playing = CVDisplayLinkIsRunning(_displayLink);
	NSEvent *latestEvent = anEvent;
	do {
		if([self mouse:[self convertPoint:[latestEvent locationInWindow] fromView:nil] inRect:_outputRect]) {
			[self.cell setHighlighted:YES];
			if(!playing) [self setNeedsDisplay:YES];
			if([self.cell trackMouse:latestEvent inRect:_outputRect ofView:self untilMouseUp:NO]) break;
			[self.cell setHighlighted:NO];
			if(!playing) [self setNeedsDisplay:YES];
		}
		latestEvent = [[self window] nextEventMatchingMask:NSLeftMouseUpMask | NSLeftMouseDraggedMask untilDate:[NSDate distantFuture] inMode:NSEventTrackingRunLoopMode dequeue:YES];
	} while([latestEvent type] != NSLeftMouseUp);
	[[self window] discardEventsMatchingMask:NSAnyEventMask beforeEvent:latestEvent];
	[self.cell setHighlighted:NO];
	if(!playing) [self setNeedsDisplay:YES];
}

#pragma mark -NSObject

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	if(_displayLink && CVDisplayLinkIsRunning(_displayLink)) ECVCVReturn(CVDisplayLinkStop(_displayLink));
	[[[_attachedFrames copy] autorelease] makeObjectsPerformSelector:@selector(invalidate)];

	ECVGLError(glTextureRangeAPPLE(GL_TEXTURE_RECTANGLE_EXT, 0, NULL));
	ECVGLError(glDeleteTextures(ECVRequiredBufferCount, [_textureNames bytes]));

	[_bufferPoolLock release];
	[_bufferData release];
	[_textureNames release];
	[_readyBufferIndexQueue release];
	[_attachedFrameLock release];
	[_attachedFrames release];
	[_attachedFrameIndexes release];
	CVDisplayLinkRelease(_displayLink);
	[_cell release];
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
	_bufferPoolLock = [[NSLock alloc] init];
	_attachedFrameLock = [[NSRecursiveLock alloc] init];
	_cropRect = ECVUncroppedRect;
	_magFilter = GL_LINEAR;
	_readyBufferIndexQueue = [[NSMutableArray alloc] init];
	_attachedFrames = [[NSMutableArray alloc] init];
	_attachedFrameIndexes = [[NSMutableIndexSet alloc] init];
	[self resetFrames];
}

#pragma mark -<ECVFrameReading>

- (BOOL)isValid
{
	return NO;
}
- (void *)bufferBytes
{
	return NULL;
}
- (NSUInteger)bufferSize
{
	[_bufferPoolLock lock];
	NSUInteger const b = _bufferSize;
	[_bufferPoolLock unlock];
	return b;
}
- (ECVPixelSize)pixelSize
{
	[_bufferPoolLock lock];
	ECVPixelSize const p = _pixelSize;
	[_bufferPoolLock unlock];
	return p;
}
- (OSType)pixelFormatType
{
	[_bufferPoolLock lock];
	OSType const t = _pixelFormatType;
	[_bufferPoolLock unlock];
	return t;
}
- (size_t)bytesPerRow
{
	[_bufferPoolLock lock];
	size_t const bpr = _pixelSize.width * ECVPixelFormatTypeBytesPerPixel(_pixelFormatType);
	[_bufferPoolLock unlock];
	return bpr;
}
- (void)markAsInvalid {}

#pragma mark -<NSLocking>

- (void)lock
{
	[_bufferPoolLock lock];
}
- (void)unlock
{
	[_bufferPoolLock unlock];
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

@implementation ECVAttachedFrame

#pragma mark -ECVAttachedFrame

- (id)initWithVideoView:(ECVVideoView *)view bufferIndex:(NSUInteger)index
{
	if((self = [super init])) {
		_videoView = view;
		_bufferIndex = index;
		_videoViewLock = [[NSLock alloc] init];
	}
	return self;
}
- (NSUInteger)bufferIndex
{
	return _bufferIndex;
}
- (void)invalidateWait:(BOOL)wait
{
	if(wait) [_videoViewLock lock];
	else if(![_videoViewLock tryLock]) return;
	[self markAsInvalid];
	[_videoViewLock unlock];
}
- (void)invalidate
{
	[self invalidateWait:YES];
}
- (void)tryToInvalidate
{
	[self invalidateWait:NO];
}

#pragma mark -NSObject

- (void)dealloc
{
	NSParameterAssert(!_videoView);
	[_videoViewLock release];
	[super dealloc];
}

#pragma mark -<ECVFrameReading>

- (BOOL)isValid
{
	return !!_videoView;
}
- (void *)bufferBytes
{
	return [_videoView bufferBytesAtIndex:_bufferIndex];
}
- (NSUInteger)bufferSize
{
	return _videoView.bufferSize;
}
- (ECVPixelSize)pixelSize
{
	return _videoView.pixelSize;
}
- (OSType)pixelFormatType
{
	return _videoView.pixelFormatType;
}
- (size_t)bytesPerRow
{
	return _videoView.bytesPerRow;
}
- (void)markAsInvalid
{
	[_videoView _invalidateFrame:self];
	_videoView = nil;
}

#pragma mark -<NSLocking>

- (void)lock
{
	[_videoViewLock lock];
}
- (void)unlock
{
	[_videoViewLock unlock];
}

@end
