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
#import "ECVFrame.h"

// Other Sources
#import "ECVDebug.h"
#import "NSMutableArrayAdditions.h"

NS_INLINE size_t ECVPixelFormatTypeBPP(OSType t)
{
	switch(t) {
		case k2vuyPixelFormat: return 2;
	}
	return 0;
}
NS_INLINE uint64_t ECVPixelFormatBlackPattern(OSType t)
{
	switch(t) {
		case k2vuyPixelFormat: return CFSwapInt64HostToBig(0x8010801080108010LL);
	}
	return 0;
}
NS_INLINE GLenum ECVPixelFormatTypeToGLFormat(OSType t)
{
	switch(t) {
		case k2vuyPixelFormat: return GL_YCBCR_422_APPLE;
	}
	return 0;
}
NS_INLINE GLenum ECVPixelFormatTypeToGLType(OSType t)
{
	switch(t) {
		case k2vuyPixelFormat: return GL_UNSIGNED_SHORT_8_8_APPLE;
	}
	return 0;
}

@interface ECVVideoView(Private)

- (GLuint)_textureNameAtIndex:(NSUInteger)index;
- (void *)_bufferBytesAtIndex:(NSUInteger)index;
- (void)_clearBufferAtIndex:(NSUInteger)index;

- (void)_drawOneFrame;
- (void)_drawBuffer:(NSUInteger)index opacity:(CGFloat)opacity;
- (void)_drawFrameDropIndicatorWithStrength:(CGFloat)strength;
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

- (void)configureWithPixelFormat:(OSType)formatType size:(ECVPixelSize)size numberOfBuffers:(NSUInteger)numberOfBuffers
{
	NSOpenGLContext *const context = [self openGLContext];
	CGLContextObj const contextObj = [context CGLContextObj];
	[context makeCurrentContext];
	CGLLockContext(contextObj);

	NSUInteger i;
	ECVglError(glEnable(GL_TEXTURE_RECTANGLE_EXT));

	_pixelFormatType = formatType;
	_pixelSize = size;

	_bufferSize = _pixelSize.width * _pixelSize.height * ECVPixelFormatTypeBPP(_pixelFormatType);
	_frameDropStrength = 0.0f;

	if(_textureNames) ECVglError(glDeleteTextures(_numberOfBuffers, [_textureNames bytes]));
	[_textureNames release];
	_textureNames = [[NSMutableData alloc] initWithLength:sizeof(GLuint) * numberOfBuffers];
	ECVglError(glGenTextures(numberOfBuffers, [_textureNames mutableBytes]));

	ECVglError(glTextureRangeAPPLE(GL_TEXTURE_RECTANGLE_EXT, 0, NULL));
	[_bufferData release];
	_bufferData = [[NSMutableData alloc] initWithLength:_bufferSize * numberOfBuffers];
	ECVglError(glTextureRangeAPPLE(GL_TEXTURE_RECTANGLE_EXT, [_bufferData length], [_bufferData bytes]));

	@synchronized(self) {
		[_readyBufferIndexQueue release];
		_readyBufferIndexQueue = [[NSMutableArray alloc] initWithCapacity:numberOfBuffers];
	}

	[self resetFrames];

	GLenum const format = ECVPixelFormatTypeToGLFormat(_pixelFormatType);
	GLenum const type = ECVPixelFormatTypeToGLType(_pixelFormatType);
	for(i = 0; i < numberOfBuffers; i++) {
		ECVglError(glBindTexture(GL_TEXTURE_RECTANGLE_EXT, [self _textureNameAtIndex:i]));
		ECVglError(glTexParameteri(GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_STORAGE_HINT_APPLE, GL_STORAGE_CACHED_APPLE));
		ECVglError(glPixelStorei(GL_UNPACK_CLIENT_STORAGE_APPLE, GL_TRUE));
		ECVglError(glTexParameteri(GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_MAG_FILTER, self.magFilter));
		ECVglError(glTexImage2D(GL_TEXTURE_RECTANGLE_EXT, 0, GL_RGBA, _pixelSize.width, _pixelSize.height, 0, format, type, [self _bufferBytesAtIndex:i]));
		[self _clearBufferAtIndex:i];
	}

	_numberOfBuffers = numberOfBuffers;

	ECVglError(glDisable(GL_TEXTURE_RECTANGLE_EXT));
	CGLUnlockContext(contextObj);
}

#pragma mark -

- (void)beginNewFrameAtTime:(NSTimeInterval)time fill:(ECVBufferFillType)fill blendLastTwoBuffers:(BOOL)blend getLastFrame:(out ECVFrame **)outFrame
{
	NSUInteger const previousFullBufferIndex = _lastFilledBufferIndex;
	NSUInteger const latestFullBufferIndex = _fillingBufferIndex;

	NSUInteger newBufferIndex = NSNotFound;
	NSUInteger bufferToDraw = latestFullBufferIndex;

	NSArray *readyBufferIndexQueue = nil;
	@synchronized(self) {
		NSUInteger const count = [_readyBufferIndexQueue count];
		if(count > 2) {
			[_readyBufferIndexQueue removeObjectsInRange:NSMakeRange(count % 2, count - count % 2)];
			_frameDropStrength = 1.0f;
		} else _frameDropStrength *= 0.75f;
		readyBufferIndexQueue = [[_readyBufferIndexQueue copy] autorelease];
	}

	NSUInteger i;
	for(i = 0; i < _numberOfBuffers; i++) {
		if(previousFullBufferIndex == i || latestFullBufferIndex == i) continue;
		NSNumber *const number = [NSNumber numberWithUnsignedInteger:i];
		if([readyBufferIndexQueue containsObject:number]) continue;
		newBufferIndex = i;
		break;
	}
	switch(fill) {
		case ECVBufferFillClear:
			[self _clearBufferAtIndex:newBufferIndex];
			break;
		case ECVBufferFillPrevious:
			if(NSNotFound == latestFullBufferIndex) [self _clearBufferAtIndex:newBufferIndex];
			else memcpy([self _bufferBytesAtIndex:newBufferIndex], [self _bufferBytesAtIndex:latestFullBufferIndex], self.bufferSize);
			break;
	}
	if(blend && NSNotFound != latestFullBufferIndex && NSNotFound != previousFullBufferIndex) {
		bufferToDraw = previousFullBufferIndex;
		UInt8 *const dst = [self _bufferBytesAtIndex:bufferToDraw];
		UInt8 *const src = [self _bufferBytesAtIndex:latestFullBufferIndex];
		NSUInteger i;
		for(i = 0; i < _bufferSize; i++) dst[i] = dst[i] / 2 + src[i] / 2;
	}

	@synchronized(self) {
		if(NSNotFound != bufferToDraw) [_readyBufferIndexQueue ECV_enqueue:[NSNumber numberWithUnsignedInteger:bufferToDraw]];
	}

	if(outFrame) {
		*outFrame = [[[ECVFrame alloc] initWithData:[_bufferData subdataWithRange:NSMakeRange(bufferToDraw * _bufferSize, _bufferSize)] pixelSize:_pixelSize pixelFormatType:_pixelFormatType bytesPerRow:self.bytesPerRow] autorelease];
		(*outFrame).time = _frameStartTime;
	}
	_lastFilledBufferIndex = latestFullBufferIndex;
	_fillingBufferIndex = newBufferIndex;
	_frameStartTime = time;
}
- (void)resetFrames
{
	@synchronized(self) {
		[_readyBufferIndexQueue removeAllObjects];
		_frameDropStrength = 0.0f;
	}
	_fillingBufferIndex = NSNotFound;
	_lastFilledBufferIndex = NSNotFound;
}
- (void *)mutableBufferBytes
{
	return [self _bufferBytesAtIndex:_fillingBufferIndex];
}

#pragma mark -

@synthesize delegate = delegate;
@synthesize blurFramesTogether = _blurFramesTogether;
@synthesize aspectRatio = _aspectRatio;
- (void)setAspectRatio:(NSSize)ratio
{
	_aspectRatio = ratio;
	[self reshape];
}
@synthesize vsync = _vsync;
- (void)setVsync:(BOOL)flag
{
	_vsync = flag;
	NSOpenGLContext *const context = [self openGLContext];
	CGLContextObj const contextObj = [context CGLContextObj];
	[context makeCurrentContext];
	CGLLockContext(contextObj);
	GLint params[] = {!!flag};
	CGLSetParameter(CGLGetCurrentContext(), kCGLCPSwapInterval, params);
	CGLUnlockContext(contextObj);
}
@synthesize magFilter = _magFilter;
- (void)setMagFilter:(GLint)filter
{
	_magFilter = filter;
	NSOpenGLContext *const context = [self openGLContext];
	CGLContextObj const contextObj = [context CGLContextObj];
	[context makeCurrentContext];
	CGLLockContext(contextObj);
	NSUInteger i = 0;
	for(i = 0; i < _numberOfBuffers; i++) {
		ECVglError(glBindTexture(GL_TEXTURE_RECTANGLE_EXT, [self _textureNameAtIndex:i]));
		ECVglError(glTexParameteri(GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_MAG_FILTER, _magFilter));
	}
	CGLUnlockContext(contextObj);
}
@synthesize showDroppedFrames = _showDroppedFrames;

#pragma mark -ECVVideoView(Private)

- (GLuint)_textureNameAtIndex:(NSUInteger)index
{
	if(NSNotFound == index) return 0;
	return ((GLuint *)[_textureNames mutableBytes])[index];
}
- (void *)_bufferBytesAtIndex:(NSUInteger)index
{
	if(NSNotFound == index) return NULL;
	return (char *)[_bufferData mutableBytes] + _bufferSize * index;
}
- (void)_clearBufferAtIndex:(NSUInteger)index
{
	if(NSNotFound == index) return;
	uint64_t const val = ECVPixelFormatBlackPattern(_pixelFormatType);
	memset_pattern8([self _bufferBytesAtIndex:index], &val, self.bufferSize);
}

#pragma mark -

- (void)_drawOneFrame
{
	NSNumber *number = nil;
	CGFloat frameDropStrength = 0.0f;
	@synchronized(self) {
		number = [_readyBufferIndexQueue ECV_dequeue];
		frameDropStrength = _frameDropStrength;
	}
	if(!number) return;

	NSUInteger const index = [number unsignedIntegerValue];
	NSParameterAssert(NSNotFound != index);

	NSOpenGLContext *const context = [self openGLContext];
	CGLContextObj const contextObj = [context CGLContextObj];
	[context makeCurrentContext];
	CGLLockContext(contextObj);

	glClear(GL_COLOR_BUFFER_BIT);
	ECVglError(glEnable(GL_TEXTURE_RECTANGLE_EXT));
	[self _drawBuffer:index opacity:1.0f];
	ECVglError(glDisable(GL_TEXTURE_RECTANGLE_EXT));
	[self _drawFrameDropIndicatorWithStrength:frameDropStrength];
	[self _drawResizeHandle];
	glFlush();

	CGLUnlockContext(contextObj);
}
- (void)_drawBuffer:(NSUInteger)index opacity:(CGFloat)opacity
{
	ECVglError(glBindTexture(GL_TEXTURE_RECTANGLE_EXT, [self _textureNameAtIndex:index]));
	ECVglError(glTexSubImage2D(GL_TEXTURE_RECTANGLE_EXT, 0, 0, 0, _pixelSize.width, _pixelSize.height, ECVPixelFormatTypeToGLFormat(_pixelFormatType), ECVPixelFormatTypeToGLType(_pixelFormatType), [self _bufferBytesAtIndex:index]));
	glColor4f(1.0f, 1.0f, 1.0f, opacity);
	glBegin(GL_QUADS);
	glTexCoord2f(0.0f, _pixelSize.height);
	glVertex2f(NSMinX(_outputRect), NSMinY(_outputRect));
	glTexCoord2f(0.0f, 0.0f);
	glVertex2f(NSMinX(_outputRect), NSMaxY(_outputRect));
	glTexCoord2f(_pixelSize.width, 0.0f);
	glVertex2f(NSMaxX(_outputRect), NSMaxY(_outputRect));
	glTexCoord2f(_pixelSize.width, _pixelSize.height);
	glVertex2f(NSMaxX(_outputRect), NSMinY(_outputRect));
	glEnd();
}
- (void)_drawFrameDropIndicatorWithStrength:(CGFloat)strength
{
	if(strength < 0.01f || !self.showDroppedFrames) return;
	CGFloat const t = 5.0f;
	NSRect const b = [self bounds];

	glColor4f(1.0f, 0.0f, 0.0f, strength);
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
- (void)_drawResizeHandle
{
	NSWindow *const w = [self window];
	if(!w || ![w showsResizeIndicator] || !([w styleMask] & NSResizableWindowMask)) return;
	NSRect const b = [self bounds];

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
	NSRect const b = [self bounds];

	NSSize const aspectRatio = self.aspectRatio;
	_outputRect = b;
	CGFloat const r = (aspectRatio.width / aspectRatio.height) / (NSWidth(b) / NSHeight(b));
	if(r > 1.0f) _outputRect.size.height *= 1.0f / r;
	else _outputRect.size.width *= r;
	_outputRect.origin = NSMakePoint(NSMidX(b) - NSWidth(_outputRect) / 2.0f, NSMidY(b) - NSHeight(_outputRect) / 2.0f);

	NSOpenGLContext *const context = [self openGLContext];
	CGLContextObj const contextObj = [context CGLContextObj];
	[context makeCurrentContext];
	CGLLockContext(contextObj);

	[super reshape];

	glViewport(NSMinX(b), NSMinY(b), NSWidth(b), NSHeight(b));
	glLoadIdentity();
	gluOrtho2D(NSMinX(b), NSWidth(b), NSMinY(b), NSHeight(b));

	ECVglError(glEnable(GL_BLEND));
	ECVglError(glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA));

	glClearColor(0.0f, 0.0f, 0.0f, 1.0f);

	CGLUnlockContext(contextObj);
}

#pragma mark -NSView

- (BOOL)isOpaque
{
	return YES;
}
- (void)drawRect:(NSRect)aRect
{
	// We do our drawing from -_drawOneFrame.
	NSOpenGLContext *const context = [self openGLContext];
	CGLContextObj const contextObj = [context CGLContextObj];
	[context makeCurrentContext];
	CGLLockContext(contextObj);

	glClear(GL_COLOR_BUFFER_BIT);
	[self _drawResizeHandle];
	glFlush();

	CGLUnlockContext(contextObj);
}
- (void)viewDidMoveToWindow
{
	CVDisplayLinkStop(_displayLink);
	if(![self window]) return;
	CVDisplayLinkSetCurrentCGDisplayFromOpenGLContext(_displayLink, [[self openGLContext] CGLContextObj], [[self pixelFormat] CGLPixelFormatObj]);
	CVDisplayLinkStart(_displayLink);
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
	CVDisplayLinkStop(_displayLink);
	ECVglError(glTextureRangeAPPLE(GL_TEXTURE_RECTANGLE_EXT, 0, NULL));
	ECVglError(glDeleteTextures(_numberOfBuffers, [_textureNames bytes]));
	[_bufferData release];
	[_textureNames release];
	[_readyBufferIndexQueue release];
	CVDisplayLinkRelease(_displayLink);
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
	[self resetFrames];
	CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink);
	CVDisplayLinkSetOutputCallback(_displayLink, (CVDisplayLinkOutputCallback)ECVDisplayLinkOutputCallback, self);
	[self viewDidMoveToWindow];
}

#pragma mark -<ECVFrameReading>

- (NSData *)bufferData
{
	return [_bufferData subdataWithRange:NSMakeRange(_fillingBufferIndex * _bufferSize, _bufferSize)];
}
@synthesize bufferSize = _bufferSize;
@synthesize pixelSize = _pixelSize;
@synthesize pixelFormatType = _pixelFormatType;
- (size_t)bytesPerRow
{
	return _pixelSize.width * ECVPixelFormatTypeBPP(_pixelFormatType);
}

@end

@implementation NSObject (ECVVideoViewDelegate)

- (BOOL)videoView:(ECVVideoView *)sender
        handleKeyDown:(NSEvent *)anEvent
{
	return NO;
}

@end
