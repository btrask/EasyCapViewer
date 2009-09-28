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

#define ECVMaxPendingDisplayFrames 1
#define ECVMaxPendingAttachedFrames 1
#define ECVFillingBuffers 1
#define ECVLastFilledBuffers 1
#define ECVLastDrawnBuffers 1
#define ECVUnassignedBuffers 1

#define ECVFieldBuffersPerFrame 2
#define ECVMaxPendingDisplayBuffers (ECVFieldBuffersPerFrame * ECVMaxPendingDisplayFrames)
#define ECVMaxPendingAttachedBuffers (ECVFieldBuffersPerFrame * ECVMaxPendingAttachedFrames)
#define ECVRequiredBufferCount (ECVMaxPendingDisplayBuffers + ECVMaxPendingAttachedBuffers + ECVFillingBuffers + ECVLastFilledBuffers + ECVLastDrawnBuffers + ECVUnassignedBuffers)

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
		case k2vuyPixelFormat: return CFSwapInt64HostToBig(0x8010801080108010ULL);
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
#if LITTLE_ENDIAN
		case k2vuyPixelFormat: return GL_UNSIGNED_SHORT_8_8_APPLE;
#else
		case k2vuyPixelFormat: return GL_UNSIGNED_SHORT_8_8_REV_APPLE;
#endif
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
- (void)tryToDetach;
- (void)detachWait:(BOOL)wait;

@end

@interface ECVVideoView(Private)

- (GLuint)_textureNameAtIndex:(NSUInteger)index;
- (void *)_bufferBytesAtIndex:(NSUInteger)index;
- (void)_clearBufferAtIndex:(NSUInteger)index;
- (void)_detachFrame:(ECVAttachedFrame *)frame;
- (NSUInteger)_unusedBufferIndex;

- (void)_drawOneFrame;
- (void)_drawBuffer:(NSUInteger)index;
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

- (void)configureWithPixelFormat:(OSType)formatType size:(ECVPixelSize)size
{
	[self resetFrames];

	NSOpenGLContext *const context = [self openGLContext];
	CGLContextObj const contextObj = [context CGLContextObj];
	[context makeCurrentContext];
	CGLLockContext(contextObj);

	NSUInteger i;
	ECVglError(glEnable(GL_TEXTURE_RECTANGLE_EXT));

	[_bufferPoolLock lock];
	_pixelFormatType = formatType;
	_pixelSize = size;
	_bufferSize = _pixelSize.width * _pixelSize.height * ECVPixelFormatTypeBPP(_pixelFormatType);
	[_bufferPoolLock unlock];

	if(_textureNames) ECVglError(glDeleteTextures(_numberOfBuffers, [_textureNames bytes]));
	[_textureNames release];
	_textureNames = [[NSMutableData alloc] initWithLength:sizeof(GLuint) * ECVRequiredBufferCount];
	ECVglError(glGenTextures(ECVRequiredBufferCount, [_textureNames mutableBytes]));

	ECVglError(glTextureRangeAPPLE(GL_TEXTURE_RECTANGLE_EXT, 0, NULL));
	[_bufferData release];
	_bufferData = [[NSMutableData alloc] initWithLength:_bufferSize * ECVRequiredBufferCount];
	ECVglError(glTextureRangeAPPLE(GL_TEXTURE_RECTANGLE_EXT, [_bufferData length], [_bufferData bytes]));

	GLenum const format = ECVPixelFormatTypeToGLFormat(_pixelFormatType);
	GLenum const type = ECVPixelFormatTypeToGLType(_pixelFormatType);
	for(i = 0; i < ECVRequiredBufferCount; i++) {
		ECVglError(glBindTexture(GL_TEXTURE_RECTANGLE_EXT, [self _textureNameAtIndex:i]));
		ECVglError(glTexParameteri(GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_STORAGE_HINT_APPLE, GL_STORAGE_CACHED_APPLE));
		ECVglError(glPixelStorei(GL_UNPACK_CLIENT_STORAGE_APPLE, GL_TRUE));
		ECVglError(glTexParameteri(GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_MAG_FILTER, self.magFilter));
		ECVglError(glTexImage2D(GL_TEXTURE_RECTANGLE_EXT, 0, GL_RGBA, _pixelSize.width, _pixelSize.height, 0, format, type, [self _bufferBytesAtIndex:i]));
		[self _clearBufferAtIndex:i];
	}

	_numberOfBuffers = ECVRequiredBufferCount;

	ECVglError(glDisable(GL_TEXTURE_RECTANGLE_EXT));
	CGLUnlockContext(contextObj);
}
- (BOOL)beginNewFrameWithFill:(ECVBufferFillType)fill getLastFrame:(out id<ECVFrameReading> *)outFrame
{
	NSUInteger const previousFullBufferIndex = _lastFilledBufferIndex;
	NSUInteger const latestFullBufferIndex = _fillingBufferIndex;
	NSUInteger const newBufferIndex = self._unusedBufferIndex;
	if(NSNotFound == newBufferIndex) {
		_fillingBufferIndex = NSNotFound;
		return NO;
	}

	NSUInteger bufferToDraw = latestFullBufferIndex;
	switch(fill) {
		case ECVBufferFillClear:
			[self _clearBufferAtIndex:newBufferIndex];
			break;
		case ECVBufferFillPrevious:
			if(NSNotFound == latestFullBufferIndex) {
				[_bufferPoolLock lock];
				BOOL const hasDrawnBuffer = NSNotFound != _lastDrawnBufferIndex;
				if(hasDrawnBuffer) memcpy([self _bufferBytesAtIndex:newBufferIndex], [self _bufferBytesAtIndex:_lastDrawnBufferIndex], _bufferSize);
				[_bufferPoolLock unlock];
				if(!hasDrawnBuffer) [self _clearBufferAtIndex:newBufferIndex];
			} else memcpy([self _bufferBytesAtIndex:newBufferIndex], [self _bufferBytesAtIndex:latestFullBufferIndex], self.bufferSize);
			break;
	}
	if(self.blurFramesTogether && NSNotFound != latestFullBufferIndex && NSNotFound != previousFullBufferIndex) {
		bufferToDraw = previousFullBufferIndex;
		UInt8 *const dst = [self _bufferBytesAtIndex:bufferToDraw];
		UInt8 *const src = [self _bufferBytesAtIndex:latestFullBufferIndex];
		NSUInteger i;
		for(i = 0; i < _bufferSize; i++) dst[i] = dst[i] / 2 + src[i] / 2;
	}

	[_bufferPoolLock lock];
	if(NSNotFound != bufferToDraw) {
		[_readyBufferIndexQueue insertObject:[NSNumber numberWithUnsignedInteger:bufferToDraw] atIndex:0];
		if(outFrame) {
			ECVAttachedFrame *const frame = [[[ECVAttachedFrame alloc] initWithVideoView:self bufferIndex:bufferToDraw] autorelease];
			[_attachedFrameLock lock];
			[_attachedFrames addObject:frame];
			[_attachedFrameIndexes addIndex:bufferToDraw];
			[_attachedFrameLock unlock];
			*outFrame = frame;
		}
	}
	[_bufferPoolLock unlock];

	_lastFilledBufferIndex = latestFullBufferIndex;
	_fillingBufferIndex = newBufferIndex;
	return YES;
}
- (void)resetFrames
{
	[_bufferPoolLock lock];
	[_readyBufferIndexQueue removeAllObjects];
	_frameDropStrength = 0.0f;
	[_bufferPoolLock unlock];
	_fillingBufferIndex = NSNotFound;
	_lastFilledBufferIndex = NSNotFound;
}
- (void *)mutableBufferBytes
{
	return [self _bufferBytesAtIndex:_fillingBufferIndex];
}

#pragma mark -

@synthesize delegate;
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
}

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
- (void)_detachFrame:(ECVAttachedFrame *)frame
{
	[_attachedFrameLock lock];
	[_attachedFrames removeObject:frame];
	[_attachedFrameIndexes removeIndex:frame.bufferIndex];
	[_attachedFrameLock unlock];
}
- (NSUInteger)_unusedBufferIndex
{
	[_attachedFrameLock lock];
	NSUInteger const attachedFrameCount = [_attachedFrames count];
	NSUInteger const keep = attachedFrameCount % ECVMaxPendingAttachedBuffers;
	if(attachedFrameCount > ECVMaxPendingAttachedBuffers) [[_attachedFrames subarrayWithRange:NSMakeRange(keep, attachedFrameCount - keep)] makeObjectsPerformSelector:@selector(tryToDetach)];
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
	NSUInteger const lastDrawnBufferIndex = _lastDrawnBufferIndex;
	[_bufferPoolLock unlock];

	NSUInteger i;
	for(i = 0; i < _numberOfBuffers; i++) {
		if(_lastFilledBufferIndex == i || _fillingBufferIndex == i || lastDrawnBufferIndex == i) continue;
		if([attachedFrameIndexes containsIndex:i]) continue;
		if([readyBufferIndexQueue containsObject:[NSNumber numberWithUnsignedInteger:i]]) continue;
		return i;
	}
	return NSNotFound;
}

#pragma mark -

- (void)_drawOneFrame
{
	NSOpenGLContext *const context = [self openGLContext];
	CGLContextObj const contextObj = [context CGLContextObj];
	[context makeCurrentContext];
	CGLLockContext(contextObj);

	[_bufferPoolLock lock];
	NSNumber *const number = [_readyBufferIndexQueue lastObject];
	CGFloat const frameDropStrength = _frameDropStrength;
	[_bufferPoolLock unlock];

	if(number) {
		NSUInteger const index = [number unsignedIntegerValue];
		NSParameterAssert(NSNotFound != index);

		glClear(GL_COLOR_BUFFER_BIT);
		[self _drawBuffer:index];
		[self _drawFrameDropIndicatorWithStrength:frameDropStrength];
		[self _drawResizeHandle];
		glFlush();

		[_bufferPoolLock lock];
		[_readyBufferIndexQueue removeLastObject];
		_lastDrawnBufferIndex = index;
		[_bufferPoolLock unlock];
	}

	CGLUnlockContext(contextObj);
}
- (void)_drawBuffer:(NSUInteger)index
{
	ECVglError(glEnable(GL_TEXTURE_RECTANGLE_EXT));
	ECVglError(glBindTexture(GL_TEXTURE_RECTANGLE_EXT, [self _textureNameAtIndex:index]));
	ECVglError(glTexSubImage2D(GL_TEXTURE_RECTANGLE_EXT, 0, 0, 0, _pixelSize.width, _pixelSize.height, ECVPixelFormatTypeToGLFormat(_pixelFormatType), ECVPixelFormatTypeToGLType(_pixelFormatType), [self _bufferBytesAtIndex:index]));
	glColor4f(1.0f, 1.0f, 1.0f, 1.0f);
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
	ECVglError(glDisable(GL_TEXTURE_RECTANGLE_EXT));
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
	// We do our normal drawing from -_drawOneFrame.
	NSOpenGLContext *const context = [self openGLContext];
	CGLContextObj const contextObj = [context CGLContextObj];
	[context makeCurrentContext];
	CGLLockContext(contextObj);

	glClear(GL_COLOR_BUFFER_BIT);
	[_bufferPoolLock lock];
	if(NSNotFound != _lastDrawnBufferIndex) [self _drawBuffer:_lastDrawnBufferIndex];
	[_bufferPoolLock unlock];
	[self _drawResizeHandle];
	glFlush();

	CGLUnlockContext(contextObj);
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
	if(![self.delegate videoView:self handleMouseDown:anEvent]) [super mouseDown:anEvent];
}

#pragma mark -NSObject

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	ECVCVReturn(CVDisplayLinkStop(_displayLink));
	[[[_attachedFrames copy] autorelease] makeObjectsPerformSelector:@selector(detach)];
	ECVglError(glTextureRangeAPPLE(GL_TEXTURE_RECTANGLE_EXT, 0, NULL));
	ECVglError(glDeleteTextures(_numberOfBuffers, [_textureNames bytes]));
	[_bufferPoolLock release];
	[_bufferData release];
	[_textureNames release];
	[_readyBufferIndexQueue release];
	[_attachedFrameLock release];
	[_attachedFrames release];
	[_attachedFrameIndexes release];
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
	_bufferPoolLock = [[NSLock alloc] init];
	_attachedFrameLock = [[NSRecursiveLock alloc] init];
	_magFilter = GL_LINEAR;
	_readyBufferIndexQueue = [[NSMutableArray alloc] init];
	_attachedFrames = (NSMutableArray *)CFArrayCreateMutable(kCFAllocatorDefault, 0, NULL);
	_attachedFrameIndexes = [[NSMutableIndexSet alloc] init];
	[self resetFrames];
}

#pragma mark -<ECVFrameReading>

- (BOOL)isValid
{
	return NO;
}
- (void const *)bufferData
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
	size_t const bpr = _pixelSize.width * ECVPixelFormatTypeBPP(_pixelFormatType);
	[_bufferPoolLock unlock];
	return bpr;
}

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
- (BOOL)videoView:(ECVVideoView *)sender handleMouseDown:(NSEvent *)anEvent
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
- (void)tryToDetach
{
	[self detachWait:NO];
}
- (void)detachWait:(BOOL)wait
{
	if(wait) [_videoViewLock lock];
	else if(![_videoViewLock tryLock]) return;
	[_videoView _detachFrame:self];
	_videoView = nil;
	[_videoViewLock unlock];
}

#pragma mark -NSObject

- (void)dealloc
{
	[self detachWait:YES];
	[_videoViewLock release];
	[super dealloc];
}

#pragma mark -<ECVFrameReading>

- (BOOL)isValid
{
	return !!_videoView;
}
- (void const *)bufferData
{
	return [_videoView _bufferBytesAtIndex:_bufferIndex];
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
