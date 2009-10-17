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
#define ECVFieldBuffersPerFrame 2

#define ECVCurrentFillBuffers 1
#define ECVPreviousFillBuffers 1
#define ECVCurrentDrawBuffers 1
#define ECVUnassignedBuffers 1
#define ECVMaxPendingDisplayBuffers (ECVFieldBuffersPerFrame * ECVMaxPendingDisplayFrames)
#define ECVMaxPendingAttachedBuffers (ECVFieldBuffersPerFrame * ECVMaxPendingAttachedFrames)

#define ECVRequiredBufferCount (ECVCurrentFillBuffers + ECVPreviousFillBuffers + ECVCurrentDrawBuffers + ECVUnassignedBuffers + ECVMaxPendingDisplayBuffers + ECVMaxPendingAttachedBuffers)

#define ECVPlayButtonSize 75

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
#if LITTLE_ENDIAN
		case kCVPixelFormatType_422YpCbCr8: return GL_UNSIGNED_SHORT_8_8_APPLE;
#else
		case kCVPixelFormatType_422YpCbCr8: return GL_UNSIGNED_SHORT_8_8_REV_APPLE;
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
- (void)invalidateWait:(BOOL)wait;
- (void)invalidate;
- (void)tryToInvalidate;

@end

@interface ECVVideoView(Private)

- (void)_generatePlayButton;

- (GLuint)_textureNameAtIndex:(NSUInteger)index;
- (void)_invalidateFrame:(ECVAttachedFrame *)frame;

- (void)_drawOneFrame;
- (void)_drawBuffer:(NSUInteger)index;
- (void)_drawFrameDropIndicatorWithStrength:(CGFloat)strength;
- (void)_drawPlayButton;
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
	ECVglError(glEnable(GL_TEXTURE_RECTANGLE_EXT));

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

	if(_textureNames) ECVglError(glDeleteTextures(ECVRequiredBufferCount, [_textureNames bytes]));
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
		ECVglError(glTexImage2D(GL_TEXTURE_RECTANGLE_EXT, 0, GL_RGB, _pixelSize.width, _pixelSize.height, 0, format, type, [self bufferBytesAtIndex:i]));
		[self clearBufferAtIndex:i];
	}

	ECVglError(glDisable(GL_TEXTURE_RECTANGLE_EXT));
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
@synthesize target;
@synthesize action;
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
		ECVglError(glBindTexture(GL_TEXTURE_RECTANGLE_EXT, [self _textureNameAtIndex:i]));
		ECVglError(glTexParameteri(GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_MAG_FILTER, _magFilter));
	}
	CGLUnlockContext(contextObj);
}
@synthesize showDroppedFrames = _showDroppedFrames;

#pragma mark -

- (NSUInteger)currentDrawBufferIndex
{
	[_bufferPoolLock lock];
	NSUInteger const i = _currentDrawBufferIndex;
	[_bufferPoolLock unlock];
	return i;
}

#pragma mark -ECVVideoView(Private)

- (void)_generatePlayButton
{
	if(_playButtonTextureName) ECVglError(glDeleteTextures(1, &_playButtonTextureName));
	[_playButton release];
	_playButton = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:ECVPlayButtonSize pixelsHigh:ECVPlayButtonSize bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:ECVPlayButtonSize * 4 bitsPerPixel:32];
	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:_playButton]];

	[[NSColor clearColor] set];
	NSRect const b = NSMakeRect(0.0f, 0.0f, ECVPlayButtonSize, ECVPlayButtonSize);
	NSRectFill(b);
	[[NSColor colorWithDeviceWhite:0.5f alpha:0.67f] set];
	[[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(b, 0.5f, 0.5f)] fill];

	NSShadow *const shadow = [[[NSShadow alloc] init] autorelease];
	[shadow setShadowBlurRadius:4.0f];
	[shadow setShadowOffset:NSMakeSize(0.0f, -2.0f)];
	[shadow set];
	[[NSColor whiteColor] set];

	NSBezierPath *const iconPath = [NSBezierPath bezierPath];
	[iconPath moveToPoint:NSMakePoint(round(NSMinX(b) + NSWidth(b) * 0.75f), round(NSMidY(b)))];
	[iconPath lineToPoint:NSMakePoint(round(NSMinX(b) + NSWidth(b) * 0.33f), round(NSMinY(b) + NSHeight(b) * 0.7f))];
	[iconPath lineToPoint:NSMakePoint(round(NSMinX(b) + NSWidth(b) * 0.33f), round(NSMinY(b) + NSHeight(b) * 0.3f))];
	[iconPath closePath];
	[iconPath fill];

	NSOpenGLContext *const context = [self openGLContext];
	CGLContextObj const contextObj = [context CGLContextObj];
	[context makeCurrentContext];
	CGLLockContext(contextObj);
	ECVglError(glEnable(GL_TEXTURE_RECTANGLE_EXT));

	ECVglError(glGenTextures(1, &_playButtonTextureName));
	ECVglError(glBindTexture(GL_TEXTURE_RECTANGLE_EXT, _playButtonTextureName));
	ECVglError(glTexImage2D(GL_TEXTURE_RECTANGLE_EXT, 0, GL_RGBA, [_playButton pixelsWide], [_playButton pixelsHigh], 0, GL_RGBA, GL_UNSIGNED_BYTE, [_playButton bitmapData]));

	ECVglError(glDisable(GL_TEXTURE_RECTANGLE_EXT));
	CGLUnlockContext(contextObj);
}

#pragma mark -

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
	ECVglError(glEnable(GL_TEXTURE_RECTANGLE_EXT));
	ECVglError(glBindTexture(GL_TEXTURE_RECTANGLE_EXT, [self _textureNameAtIndex:index]));
	ECVglError(glTexSubImage2D(GL_TEXTURE_RECTANGLE_EXT, 0, 0, 0, _pixelSize.width, _pixelSize.height, ECVPixelFormatTypeToGLFormat(_pixelFormatType), ECVPixelFormatTypeToGLType(_pixelFormatType), [self bufferBytesAtIndex:index]));
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
- (void)_drawPlayButton
{
	if(_displayLink && CVDisplayLinkIsRunning(_displayLink)) return;
	ECVglError(glEnable(GL_TEXTURE_RECTANGLE_EXT));
	ECVglError(glBindTexture(GL_TEXTURE_RECTANGLE_EXT, _playButtonTextureName));

	NSRect const b = [self bounds];
	NSRect const playButtonRect = NSMakeRect(round(NSMidX(b) - ECVPlayButtonSize / 2.0f), round(NSMinY(b) + (NSHeight(b) - ECVPlayButtonSize) / 3.0f), ECVPlayButtonSize, ECVPlayButtonSize);

	GLfloat const c = _highlighted ? 0.67f : 1.0f;
	glColor4f(c, c, c, 1.0f);
	glBegin(GL_QUADS);
	glTexCoord2f(0.0f, ECVPlayButtonSize);
	glVertex2f(NSMinX(playButtonRect), NSMinY(playButtonRect));
	glTexCoord2f(0.0f, 0.0f);
	glVertex2f(NSMinX(playButtonRect), NSMaxY(playButtonRect));
	glTexCoord2f(ECVPlayButtonSize, 0.0f);
	glVertex2f(NSMaxX(playButtonRect), NSMaxY(playButtonRect));
	glTexCoord2f(ECVPlayButtonSize, ECVPlayButtonSize);
	glVertex2f(NSMaxX(playButtonRect), NSMinY(playButtonRect));
	glEnd();

	ECVglError(glDisable(GL_TEXTURE_RECTANGLE_EXT));
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
	if(NSNotFound != _currentDrawBufferIndex) [self _drawBuffer:_currentDrawBufferIndex];
	[_bufferPoolLock unlock];
	[self _drawPlayButton];
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
	_highlighted = YES;
	[self setNeedsDisplay:YES];
	NSEvent *latestEvent = nil;
	while((latestEvent = [[self window] nextEventMatchingMask:NSLeftMouseDraggedMask | NSLeftMouseUpMask untilDate:[NSDate distantFuture] inMode:NSEventTrackingRunLoopMode dequeue:YES]) && [latestEvent type] != NSLeftMouseUp) {
		_highlighted = [[[self window] contentView] hitTest:[latestEvent locationInWindow]] == self;
		[self setNeedsDisplay:YES];
	}
	[[self window] discardEventsMatchingMask:NSAnyEventMask beforeEvent:latestEvent];
	if(_highlighted) [NSApp sendAction:self.action to:self.target from:self];
	_highlighted = NO;
	[self setNeedsDisplay:YES];
}

#pragma mark -NSObject

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	ECVCVReturn(CVDisplayLinkStop(_displayLink));
	[[[_attachedFrames copy] autorelease] makeObjectsPerformSelector:@selector(invalidate)];

	ECVglError(glTextureRangeAPPLE(GL_TEXTURE_RECTANGLE_EXT, 0, NULL));
	ECVglError(glDeleteTextures(ECVRequiredBufferCount, [_textureNames bytes]));
	ECVglError(glDeleteTextures(1, &_playButtonTextureName));

	[_bufferPoolLock release];
	[_bufferData release];
	[_textureNames release];
	[_readyBufferIndexQueue release];
	[_attachedFrameLock release];
	[_attachedFrames release];
	[_attachedFrameIndexes release];
	CVDisplayLinkRelease(_displayLink);
	[_playButton release];
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
	_attachedFrames = [[NSMutableArray alloc] init];
	_attachedFrameIndexes = [[NSMutableIndexSet alloc] init];
	[self _generatePlayButton];
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
