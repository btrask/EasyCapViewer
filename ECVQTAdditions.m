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
#import "ECVQTAdditions.h"

// Other Sources
#import "ECVDebug.h"

static QTTimeRange ECVMakeTimeRangeScaled(QTTimeRange r, long s)
{
	return QTMakeTimeRange(QTMakeTimeScaled(r.time, s), QTMakeTimeScaled(r.duration, s));
}

@implementation QTMedia(ECVQTAdditions)

- (void)ECV_beginEdits
{
	ECVOSStatus(BeginMediaEdits([self quickTimeMedia]));
}
- (void)ECV_endEdits
{
	ECVOSStatus(EndMediaEdits([self quickTimeMedia]));
}
- (QTTimeRange)ECV_timeRange
{
	Media const m = [self quickTimeMedia];
	long const s = [[[self mediaAttributes] objectForKey:QTMediaTimeScaleAttribute] longValue];
	return QTMakeTimeRange(QTMakeTime(GetMediaDisplayStartTime(m), s), QTMakeTime(GetMediaDisplayDuration(m), s));
}

@end

@implementation QTTrack(ECVQTAdditions)

- (void)ECV_insertMediaInRange:(QTTimeRange)srcRange intoTrackInRange:(QTTimeRange)dstRange
{
	long scale = [[[[self media] mediaAttributes] objectForKey:QTMediaTimeScaleAttribute] longValue];
	QTTimeRange const s = ECVMakeTimeRangeScaled(srcRange, scale);
	QTTimeRange const d = ECVMakeTimeRangeScaled(dstRange, scale);
	ECVOSStatus(InsertMediaIntoTrack([self quickTimeTrack], d.time.timeValue, s.time.timeValue, s.duration.timeValue, X2Fix((double)s.duration.timeValue / d.duration.timeValue)));
}
- (void)ECV_insertMediaInRange:(QTTimeRange)range atTime:(QTTime)time
{
	[self ECV_insertMediaInRange:range intoTrackInRange:QTMakeTimeRange(time, range.duration)];
}
- (void)ECV_insertMediaAtTime:(QTTime)time
{
	[self ECV_insertMediaInRange:[[self media] ECV_timeRange] atTime:time];
}

@end
