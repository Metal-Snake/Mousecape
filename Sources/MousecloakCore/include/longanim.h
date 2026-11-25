//
//  longanim.h
//  Mousecape
//
//  Animations with more than MCMaxFrameCount frames, registered through the call that
//  CGSRegisterCursorWithImages wraps (NOTES.md, "Frame limit").
//

#ifndef Mousecape_longanim_h
#define Mousecape_longanim_h

#import "MCDefs.h"

// Whether this process can register cursors with more than MCMaxFrameCount frames: the
// internal call was found and a test registration of MCMaxFrameCount + 1 frames read back
// right. Checked once per process. The environment variable MOUSECAPE_SHORT_ANIMATIONS=1
// turns it off, to test the fallback.
extern BOOL MCLongAnimationsAvailable(void);

// The most frames a cursor may have when applied, given the pixels of one frame in all its
// images together: MCMaxFrameCount without long animations, otherwise as many as fit
// MCMaxLongAnimationPixels, at least MCMaxFrameCount and at most MCMaxLongFrameCount.
// The same as CapeCursor.frameLimit(pixelsPerFrame:longAnimations:) in CapeKit.
extern NSUInteger MCFrameLimit(NSUInteger pixelsPerFrame, BOOL longAnimations);

// The pixels of one frame in all of `images` (vertical sheets of `frameCount` frames).
extern NSUInteger MCPixelsPerFrame(NSArray *images, NSUInteger frameCount);

// Registers a cursor as CGSRegisterCursorWithImages does (globally, at once), without its
// frame limit. Fails with kCGErrorNotImplemented when long animations aren't available.
extern CGError MCRegisterLongCursor(CGSConnectionID cid, const char *name, CGSize size, CGPoint hotSpot,
                                    NSUInteger frameCount, CGFloat frameDuration, NSArray *images);

#endif
