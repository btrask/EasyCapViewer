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
#import "ECVOpenGLAdditions.h"

void ECVGLDrawTexture(NSRect frame, NSRect bounds)
{
	glBegin(GL_QUADS);
	glTexCoord2f(NSMinX(bounds), NSMinY(bounds)); glVertex2f(NSMinX(frame), NSMinY(frame));
	glTexCoord2f(NSMinX(bounds), NSMaxY(bounds)); glVertex2f(NSMinX(frame), NSMaxY(frame));
	glTexCoord2f(NSMaxX(bounds), NSMaxY(bounds)); glVertex2f(NSMaxX(frame), NSMaxY(frame));
	glTexCoord2f(NSMaxX(bounds), NSMinY(bounds)); glVertex2f(NSMaxX(frame), NSMinY(frame));
	glEnd();
}
void ECVGLDrawBorder(NSRect inner, NSRect outer)
{
	glBegin(GL_TRIANGLE_STRIP);
	glVertex2f(NSMinX(inner), NSMinY(inner)); glVertex2f(NSMinX(outer), NSMinY(outer));
	glVertex2f(NSMinX(inner), NSMaxY(inner)); glVertex2f(NSMinX(outer), NSMaxY(outer));
	glVertex2f(NSMaxX(inner), NSMaxY(inner)); glVertex2f(NSMaxX(outer), NSMaxY(outer));
	glVertex2f(NSMaxX(inner), NSMinY(inner)); glVertex2f(NSMaxX(outer), NSMinY(outer));
	glVertex2f(NSMinX(inner), NSMinY(inner)); glVertex2f(NSMinX(outer), NSMinY(outer));
	glEnd();
}
