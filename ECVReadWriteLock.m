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
#import "ECVReadWriteLock.h"
#import <pthread.h>

// Other Sources
#import "ECVDebug.h"

@interface ECVReadWriteLock(Private)

- (BOOL)_tryLockResult:(int)error;

@end

@implementation ECVReadWriteLock

#pragma mark -ECVReadWriteLock

- (void)readLock
{
	ECVErrno(pthread_rwlock_rdlock(&_lock));
}
- (void)writeLock
{
	ECVErrno(pthread_rwlock_wrlock(&_lock));
}
- (BOOL)tryReadLock
{
	return [self _tryLockResult:pthread_rwlock_tryrdlock(&_lock)];
}
- (BOOL)tryWriteLock
{
	return [self _tryLockResult:pthread_rwlock_trywrlock(&_lock)];
}

#pragma mark -ECVReadWriteLock(Private)

- (BOOL)_tryLockResult:(int)error
{
	if(!error) return YES;
	if(EBUSY != error) ECVErrno(error);
	return NO;
}

#pragma mark -NSObject

- (id)init
{
	if((self = [super init])) {
		ECVErrno(pthread_rwlock_init(&_lock, NULL));
	}
	return self;
}
- (void)dealloc
{
	ECVErrno(pthread_rwlock_destroy(&_lock));
	[super dealloc];
}

#pragma mark -<NSLocking>

- (void)lock
{
	ECVAssertNotReached(@"-[ECVReadWriteLock lock] is ambiguous. Use -readLock or -writeLock instead.");
}
- (void)unlock
{
	ECVErrno(pthread_rwlock_unlock(&_lock));
}

@end
