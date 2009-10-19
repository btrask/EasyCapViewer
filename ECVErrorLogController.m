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
#import "ECVErrorLogController.h"

static NSString *const ECVClearLogItemIdentifier = @"ECVClearLogItem";
static ECVErrorLogController *ECVSharedErrorLogController;

@interface ECVErrorLogController(Private)
- (void)_mainThread_logAttributedString:(NSAttributedString *)string;
@end

@implementation ECVErrorLogController

#pragma mark +ECVErrorLogController

+ (id)sharedErrorLogController
{
	return ECVSharedErrorLogController;
}

#pragma mark +NSObject

+ (void)initialize
{
	if(!ECVSharedErrorLogController) ECVSharedErrorLogController = [[self alloc] init];
}

#pragma mark -ECVErrorLogController

- (IBAction)clearLog:(id)sender
{
	[_errorLog deleteCharactersInRange:NSMakeRange(0, [_errorLog length])];
	[[errorLogTextView textStorage] deleteCharactersInRange:NSMakeRange(0, [[errorLogTextView textStorage] length])];
}

#pragma mark -

- (void)logLevel:(ECVErrorLevel)level message:(NSString *)message
{
	NSColor *color = nil;
	switch(level) {
		case ECVError: color = [NSColor blackColor]; break;
		case ECVCritical: color = [NSColor redColor]; break;
		default: color = [NSColor grayColor]; break;
	}
	NSString *const string = [NSString stringWithFormat:@"%@: %@\n", [[NSDate date] description], [message stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
	NSDictionary *const attributes = [NSDictionary dictionaryWithObjectsAndKeys:
		[NSFont systemFontOfSize:[NSFont systemFontSize]], NSFontAttributeName,
		color, NSForegroundColorAttributeName,
		nil];
	[self performSelectorOnMainThread:@selector(_mainThread_logAttributedString:) withObject:[[[NSAttributedString alloc] initWithString:string attributes:attributes] autorelease] waitUntilDone:NO];
}
- (void)logLevel:(ECVErrorLevel)level format:(NSString *)format arguments:(va_list)arguments
{
	NSLog(@"format: %@", format);
	[self logLevel:level message:[[[NSString alloc] initWithFormat:format arguments:arguments] autorelease]];
}
- (void)logLevel:(ECVErrorLevel)level format:(NSString *)format, ...
{
	va_list arguments;
	va_start(arguments, format);
	[self logLevel:level format:format arguments:arguments];
	va_end(arguments);
}

#pragma mark -ECVErrorLogController(Private)

- (void)_mainThread_logAttributedString:(NSAttributedString *)string
{
	[_errorLog appendAttributedString:string];
	[[errorLogTextView textStorage] appendAttributedString:string];
	[errorLogTextView moveToEndOfDocument:self];
}

#pragma mark -NSWindowController

- (void)windowDidLoad
{
	[super windowDidLoad];
	[[errorLogTextView textStorage] setAttributedString:_errorLog];

	NSToolbar *const toolbar = [[[NSToolbar alloc] initWithIdentifier:@"ECVErrorLogControllerToolbar1"] autorelease];
	[toolbar setDelegate:self];
	[toolbar setDisplayMode:NSToolbarDisplayModeIconAndLabel];
	[toolbar setSizeMode:NSToolbarSizeModeSmall];
	[[self window] setToolbar:toolbar];
}

#pragma mark -NSObject

- (id)init
{
	if((self = [super initWithWindowNibName:@"ECVErrorLog"])) {
		_errorLog = [[NSMutableAttributedString alloc] init];
	}
	return self;
}
- (void)dealloc
{
	[_errorLog release];
	[super dealloc];
}

#pragma mark -NSObject(NSToolbarItemValidation)

- (BOOL)validateToolbarItem:(NSToolbarItem *)anItem
{
	SEL const action = [anItem action];
	if(@selector(clearLog:) == action) return !![_errorLog length];
	return [self respondsToSelector:@selector(action)];
}

#pragma mark -<NSToolbarDelegate>

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)ident willBeInsertedIntoToolbar:(BOOL)flag
{
	NSParameterAssert([ident isEqualToString:ECVClearLogItemIdentifier]);
	NSToolbarItem *const item = [[[NSToolbarItem alloc] initWithItemIdentifier:ident] autorelease];
	[item setImage:[NSImage imageNamed:@"Log-Clear"]];
	[item setLabel:NSLocalizedString(@"Clear Log", nil)];
	[item setAction:@selector(clearLog:)];
	return item;
}
- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar*)toolbar
{
	return [NSArray arrayWithObjects:ECVClearLogItemIdentifier, nil];
}
- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar*)toolbar
{
	return [self toolbarDefaultItemIdentifiers:toolbar];
}

@end
