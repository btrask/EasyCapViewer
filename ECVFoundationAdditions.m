/* Copyright (c) 2007-2009, Ben Trask
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
#import "ECVFoundationAdditions.h"
#import <objc/runtime.h>

static NSString *const ECVMainSuiteNameKey = @"ECVMainSuiteName";

@implementation NSBundle(ECVFoundationAdditions)

- (NSString *)ECV_mainSuiteName
{
	return [[self infoDictionary] objectForKey:ECVMainSuiteNameKey];
}

@end

@implementation NSDate(ECVFoundationAdditions)

+ (NSTimeInterval)ECV_timeIntervalSinceReferenceDate
{
	return (NSTimeInterval)UnsignedWideToUInt64(AbsoluteToNanoseconds(UpTime())) * 1e-9f;
}

@end

@implementation NSObject(ECVFoundationAdditions)

#pragma mark +NSObject(ECVFoundationAdditions)

+ (void *)ECV_useInstance:(BOOL)instance implementationFromClass:(Class)class forSelector:(SEL)aSel
{
	if(!instance) self = objc_getMetaClass(class_getName(self));
	Method const newMethod = instance ? class_getInstanceMethod(class, aSel) : class_getClassMethod(class, aSel);
	if(!newMethod) return NULL;
	IMP const originalImplementation = class_getMethodImplementation(self, aSel); // Make sure the IMP we return is gotten using the normal method lookup mechanism.
	(void)class_replaceMethod(self, aSel, method_getImplementation(newMethod), method_getTypeEncoding(newMethod)); // If this specific class doesn't provide its own implementation of aSel--even if a superclass does--class_replaceMethod() adds the method without replacing anything and returns NULL. This behavior is good because it prevents our change from spreading to a superclass, but it means the return value is worthless.
	return originalImplementation;
}

#pragma mark -NSObject(ECVFoundationAdditions)

- (void)ECV_addObserver:(id)observer selector:(SEL)aSelector name:(NSString *)aName
{
	[[NSNotificationCenter defaultCenter] addObserver:observer selector:aSelector name:aName object:self];
}
- (void)ECV_removeObserver:(id)observer name:(NSString *)aName
{
	[[NSNotificationCenter defaultCenter] removeObserver:observer name:aName object:self];
}

@end
