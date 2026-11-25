//
//  apply.h
//  Mousecape
//
//  Created by Alex Zielenski on 2/1/14.
//  Copyright (c) 2014 Alex Zielenski. All rights reserved.
//

#ifndef Mousecape_apply_h
#define Mousecape_apply_h

#import "MCDefs.h"

extern BOOL applyCursorForIdentifier(NSUInteger frameCount, CGFloat frameDuration, CGPoint hotSpot, CGSize size, NSArray *images, NSString *ident, NSUInteger repeatCount);
extern BOOL applyCapeForIdentifier(NSDictionary *cursor, NSString *identifier, BOOL restore);
extern BOOL applyCape(NSDictionary *dictionary);
extern BOOL applyCapeAtPath(NSString *path);
// Back to the macOS cursors; in left-handed mode, mirrored. Returns NO if some cursor
// could not be reset or mirrored.
extern BOOL applyDefaultCursors(void);
// Frames picked by time for frames with their own durations, at most `limit` (see
// apply.m); exposed so a test can check it against CapeKit's FrameSelection.byTime.
// `indices` needs room for `limit` entries. Returns the number of frames, 0 if the
// durations can't be used.
extern NSUInteger MCFramesByTime(NSArray *durations, NSUInteger *indices, CGFloat *duration, NSUInteger limit);
// The most frames a cursor with these images (sheets of `frameCount` frames) keeps when
// applied: MCMaxFrameCount, or more when long animations are available (longanim.h).
extern NSUInteger MCAppliedFrameLimit(NSArray *images, NSUInteger frameCount);

#endif
