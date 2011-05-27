/* Copyright (c) 2011, Ben Trask
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
typedef struct {
	NSInteger numer;
	NSInteger denom;
} ECVRational;

extern NSInteger ECVIntegerGCD(NSInteger a, NSInteger b);
extern NSUInteger ECVIntegerLCM(NSInteger a, NSInteger b);
extern ECVRational ECVRationalGCD(ECVRational a, ECVRational b);
extern ECVRational ECVRationalLCM(ECVRational a, ECVRational b);
extern NSString *ECVRationalToString(ECVRational r);
ECVRational ECVRationalFromString(NSString *str);

static ECVRational ECVMakeRational(NSInteger numer, NSInteger denom)
{
	NSCParameterAssert(denom);
	NSInteger const gcd = ECVIntegerGCD(numer, denom);
	return (ECVRational){numer / gcd, denom / gcd};
}

static ECVRational ECVRationalInverse(ECVRational r)
{
	return (ECVRational){r.denom, r.numer};
}

static ECVRational ECVRationalAdd(ECVRational a, ECVRational b)
{
	NSInteger const denom = ECVIntegerLCM(a.denom, b.denom);
	NSInteger const aMul = denom / a.denom;
	NSInteger const bMul = denom / b.denom;
	return ECVMakeRational((a.numer * aMul) + (b.numer * bMul), denom);
}
static ECVRational ECVRationalSubtract(ECVRational a, ECVRational b)
{
	ECVRational const bNeg = (ECVRational){-b.numer, b.denom};
	return ECVRationalAdd(a, bNeg);
}
static ECVRational ECVRationalMultiply(ECVRational a, ECVRational b)
{
	return ECVMakeRational(a.numer * b.numer, a.denom * b.denom);
}
static ECVRational ECVRationalDivide(ECVRational a, ECVRational b)
{
	return ECVRationalMultiply(a, ECVRationalInverse(b));
}

static CGFloat ECVRationalToCGFloat(ECVRational r)
{
	return (CGFloat)r.numer / r.denom;
}
static NSInteger ECVRationalToNSInteger(ECVRational r)
{
	NSCParameterAssert(1 == r.denom);
	return r.numer;
}
