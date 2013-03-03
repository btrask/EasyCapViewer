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
#import "ECVOverlayController.h"
#import "ECVCaptureController.h"
#import "ECVVideoView.h"
#import "ECVDebug.h"

enum {
	ECVDisplayFullScreen = 0,
	ECVDisplayTopLeft = 1,
	ECVDisplayTopRight = 2,
	ECVDisplayBottomLeft = 3,
	ECVDisplayBottomRight = 4,
};
static NSRect ECVFrameFromPosition(NSInteger const x)
{
	switch(x) {
		case ECVDisplayFullScreen: return NSMakeRect(0, 0, 1, 1);
		case ECVDisplayTopLeft: return NSMakeRect(0, 0, 0.5, 0.5);
		case ECVDisplayTopRight: return NSMakeRect(0.5, 0, 0.5, 0.5);
		case ECVDisplayBottomLeft: return NSMakeRect(0, 0.5, 0.5, 0.5);
		case ECVDisplayBottomRight: return NSMakeRect(0.5, 0.5, 0.5, 0.5);
	}
	ECVCAssertNotReached(@"Invalid position");
	return NSZeroRect;
}

@interface ECVOverlayController(Private)

- (void)_update;
- (NSInteger)_unoccupiedCorner;

@end

@implementation ECVOverlayController

#pragma mark +ECVOverlayController

+ (id)sharedOverlayController
{
	static ECVOverlayController *c;
	if(!c) c = [[self alloc] init];
	return [[c retain] autorelease];
}

#pragma mark -ECVOverlayController

- (IBAction)addOverlay:(id)sender
{
	NSOpenPanel *const p = [NSOpenPanel openPanel];
	if(NSOKButton == [p runModal]) {
		ECVVideoView *const v = [[self captureController] videoView];
		ECVOverlay *const o = [[[ECVOverlay alloc] initWithOpenGLContext:[v openGLContext]] autorelease];
		NSInteger const corner = [self _unoccupiedCorner];
		[o setFrame:ECVFrameFromPosition(corner)];
		[o setTag:corner];
		[o setImage:[[[NSImage alloc] initWithContentsOfURL:[p URL]] autorelease]];
		[o setName:[[[p URL] path] lastPathComponent]];
		[o setOpacity:[opacitySlider doubleValue]];
		[v addOverlay:o];
		[self _update];
		[overlayPopup selectItemAtIndex:[[overlayPopup menu] indexOfItemWithRepresentedObject:o]];
		[self changeOverlay:nil];
	}
}
- (IBAction)removeOverlay:(id)sender
{
	ECVCaptureController *const c = [self captureController];
	ECVVideoView *const v = [c videoView];
	ECVOverlay *const o = [[overlayPopup selectedItem] representedObject];
	[v removeOverlay:o];
	[self _update];
}
- (IBAction)changeOverlay:(id)sender
{
	ECVOverlay *const o = [[overlayPopup selectedItem] representedObject];
	[displayPopup selectItemWithTag:[o tag]];
	[opacitySlider setDoubleValue:o ? [o opacity] : 0.5];
}
- (IBAction)changeOverlayFrame:(id)sender
{
	ECVOverlay *const o = [[overlayPopup selectedItem] representedObject];
	NSRect f = ECVFrameFromPosition([sender selectedTag]);
	[o setFrame:f];
	[o setTag:[sender selectedTag]];
	ECVCaptureController *const c = [self captureController];
	ECVVideoView *const v = [c videoView];
	[v setNeedsDisplay:YES];
}
- (IBAction)changeOpacity:(id)sender
{
	ECVOverlay *const o = [[overlayPopup selectedItem] representedObject];
	[o setOpacity:[sender doubleValue]];
	ECVCaptureController *const c = [self captureController];
	ECVVideoView *const v = [c videoView];
	[v setNeedsDisplay:YES];
}

#pragma mark -

- (ECVCaptureController *)captureController
{
	return _captureController;
}
- (void)setCaptureController:(ECVCaptureController *const)c
{
	_captureController = c;
	[self _update];
}

#pragma mark -ECVOverlayController(Private)

- (void)_update
{
	ECVCaptureController *const c = [self captureController];
	ECVVideoView *const v = [c videoView];

	[overlayPopup removeAllItems];
	for(ECVOverlay *const o in [v overlays]) {
		NSMenuItem *const i = [[[NSMenuItem alloc] initWithTitle:[o name] action:NULL keyEquivalent:@""] autorelease];
		[i setRepresentedObject:o];
		[[overlayPopup menu] addItem:i];
	}

	[self changeOverlay:nil];

	[addButton setEnabled:!!v];

	BOOL const hasSelection = v && [overlayPopup selectedItem];
	[overlayPopup setEnabled:hasSelection];
	[removeButton setEnabled:hasSelection];
	[displayPopup setEnabled:hasSelection];
	[opacitySlider setEnabled:hasSelection];
}
- (NSInteger)_unoccupiedCorner
{
	NSMutableIndexSet *const corners = [[[NSMutableIndexSet alloc] initWithIndexesInRange:NSMakeRange(1, 4)] autorelease];
	for(ECVOverlay *const o in [[[self captureController] videoView] overlays]) if([o opacity] > 0.001) [corners removeIndex:[o tag]];
	NSInteger const r = [corners firstIndex];
	return NSNotFound == r ? ECVDisplayTopLeft : r;
}

#pragma mark -NSWindowController

- (void)windowDidLoad
{
	[super windowDidLoad];
	NSPanel *const w = (NSPanel *)[self window];
	[w setBecomesKeyOnlyIfNeeded:YES];
	[w setCollectionBehavior:NSWindowCollectionBehaviorFullScreenAuxiliary];
	[self _update];
}

#pragma mark -NSObject

- (id)init
{
	return [self initWithWindowNibName:@"ECVOverlay"];
}

@end
