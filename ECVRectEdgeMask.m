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
#import "ECVRectEdgeMask.h"

NSPoint ECVRectPoint(NSRect r, ECVRectEdgeMask mask)
{
	NSPoint p = NSZeroPoint;
	switch(ECVRectHorz & mask) {
		case ECVMinXMask: p.x = NSMinX(r); break;
		case ECVRectMidX: p.x = NSMidX(r); break;
		case ECVMaxXMask: p.x = NSMaxX(r); break;
	}
	switch(ECVRectVert & mask) {
		case ECVMinYMask: p.y = NSMinY(r); break;
		case ECVRectMidY: p.y = NSMidY(r); break;
		case ECVMaxYMask: p.y = NSMaxY(r); break;
	}
	return p;
}
ECVRectEdgeMask ECVRectEdgeOpposite(ECVRectEdgeMask mask)
{
	ECVRectEdgeMask p = ECVRectCenter;
	switch(ECVRectHorz & mask) {
		case ECVMinXMask: p |= ECVMaxXMask; break;
		case ECVMaxXMask: p |= ECVMinXMask; break;
	}
	switch(ECVRectVert & mask) {
		case ECVMinYMask: p |= ECVMaxYMask; break;
		case ECVMaxYMask: p |= ECVMinYMask; break;
	}
	return p;
}
NSRect ECVRectWithSizeFromEdge(NSRect rect, NSSize size, ECVRectEdgeMask mask)
{
	NSRect r = (NSRect){rect.origin, size};
	if(ECVMinXMask & mask) r.origin.x = NSMaxX(rect) - size.width;
	if(ECVMinYMask & mask) r.origin.y = NSMaxY(rect) - size.height;
	return r;
}
NSRect ECVRectByAddingSizeFromEdge(NSRect rect, NSSize size, ECVRectEdgeMask mask)
{
	return ECVRectWithSizeFromEdge(rect, NSMakeSize(NSWidth(rect) + size.width, NSHeight(rect) + size.height), mask);
}
NSRect ECVRectByScalingEdgeToPoint(NSRect rect, ECVRectEdgeMask mask, NSPoint p, NSSize minSize, NSRect maxRect)
{
	NSPoint const p1 = ECVRectPoint(rect, mask);
	NSPoint const p2 = ECVRectPoint(rect, ECVRectEdgeOpposite(mask));
	NSSize const d = NSMakeSize(p1.x - p2.x, p1.y - p2.y);
	CGFloat const length = hypot(d.width, d.height);
	CGFloat u = ((p.x - p1.x) * d.width + (p.y - p1.y) * d.height) / pow(length, 2.0f);
	if(ECVRectHorz & mask) {
		u = MAX(u, (minSize.width - NSWidth(rect)) / ABS(d.width));
		u = MIN(u, (ECVRectPoint(maxRect, mask).x - p1.x) / d.width);
	}
	if(ECVRectVert & mask) {
		u = MAX(u, (minSize.height - NSHeight(rect)) / ABS(d.height));
		u = MIN(u, (ECVRectPoint(maxRect, mask).y - p1.y) / d.height);
	}
	return ECVRectByAddingSizeFromEdge(rect, NSMakeSize(u * ABS(d.width), u * ABS(d.height)), mask);
}
