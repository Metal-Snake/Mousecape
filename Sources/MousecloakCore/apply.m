//
//  apply.m
//  Mousecape
//
//  Created by Alex Zielenski on 2/1/14.
//  Copyright (c) 2014 Alex Zielenski. All rights reserved.
//

#import "MCDefs.h"
#import "create.h"
#import "backup.h"
#import "restore.h"
#import "MCPrefs.h"
#import "NSBitmapImageRep+ColorSpace.h"

// Rebuilds each vertically stacked sheet from the frames at `indices` (in that order,
// repeats allowed), `count` frames in all.
static NSArray *sheetsWithFrames(NSArray *sheets, NSUInteger frameCount, const NSUInteger *indices, NSUInteger count) {
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:sheets.count];
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    for (id object in sheets) {
        CGImageRef sheet = (CGImageRef)object;
        size_t width = CGImageGetWidth(sheet);
        size_t frameHeight = CGImageGetHeight(sheet) / frameCount;
        CGContextRef ctx = CGBitmapContextCreate(NULL, width, frameHeight * count, 8, 0, space,
                                                 kCGImageAlphaPremultipliedLast);
        if (!ctx || frameHeight == 0) {
            if (ctx) CGContextRelease(ctx);
            result = nil;
            break;
        }
        for (NSUInteger k = 0; k < count; k++) {
            // Cropping counts from the top, drawing from the bottom.
            CGImageRef frame = CGImageCreateWithImageInRect(sheet, CGRectMake(0, indices[k] * frameHeight, width, frameHeight));
            CGContextDrawImage(ctx, CGRectMake(0, (count - 1 - k) * frameHeight, width, frameHeight), frame);
            CGImageRelease(frame);
        }
        CGImageRef image = CGBitmapContextCreateImage(ctx);
        CGContextRelease(ctx);
        [result addObject:(id)image];
        CGImageRelease(image);
    }
    CGColorSpaceRelease(space);
    return result;
}

static NSUInteger gcdOf(NSUInteger a, NSUInteger b) {
    return b == 0 ? a : gcdOf(b, a % b);
}

// For frames with their own durations: the frames to show (into `indices`, room for
// MCMaxFrameCount) and one duration for all, so the animation keeps its timing. Repeats
// each frame in units of the durations' common divisor when that fits (exact); otherwise
// samples the loop at MCMaxFrameCount evenly spaced moments, the middle of each slot.
// The same as FrameSelection.byTime in CapeKit. Returns the number of frames, 0 if the
// durations can't be used.
static NSUInteger framesByTime(NSArray *durations, NSUInteger *indices, CGFloat *duration) {
    NSUInteger n = durations.count;
    if (n == 0) return 0;
    double total = 0;
    for (NSNumber *d in durations) {
        if (![d isKindOfClass:[NSNumber class]] || d.doubleValue <= 0) return 0;
        total += d.doubleValue;
    }
    // Exactly, in the unit the durations came in: jiffies (Windows) or milliseconds.
    const double units[] = { 1.0 / 60, 0.001 };
    for (int u = 0; u < 2; u++) {
        BOOL whole = YES;
        NSUInteger divisor = 0, expanded = 0;
        for (NSNumber *d in durations) {
            double ticks = d.doubleValue / units[u];
            if (fabs(ticks - round(ticks)) >= 0.01 || round(ticks) < 1) { whole = NO; break; }
            divisor = gcdOf(divisor, (NSUInteger)round(ticks));
        }
        if (!whole) continue;
        for (NSNumber *d in durations) expanded += (NSUInteger)round(d.doubleValue / units[u]) / divisor;
        if (expanded <= MCMaxFrameCount) {
            NSUInteger k = 0;
            for (NSUInteger i = 0; i < n; i++) {
                NSUInteger repeats = (NSUInteger)round([durations[i] doubleValue] / units[u]) / divisor;
                for (NSUInteger r = 0; r < repeats; r++) indices[k++] = i;
            }
            *duration = divisor * units[u];
            return expanded;
        }
        break;
    }
    double slot = total / MCMaxFrameCount;
    for (NSUInteger k = 0; k < MCMaxFrameCount; k++) {
        double moment = (k + 0.5) * slot, end = 0;
        NSUInteger frame = n - 1;
        for (NSUInteger i = 0; i < n; i++) {
            end += [durations[i] doubleValue];
            if (moment < end) { frame = i; break; }
        }
        indices[k] = frame;
    }
    *duration = slot;
    return MCMaxFrameCount;
}

BOOL applyCursorForIdentifier(NSUInteger frameCount, CGFloat frameDuration, CGPoint hotSpot, CGSize size, NSArray *images, NSString *ident, NSUInteger repeatCount) {
    if (frameCount > MCMaxFrameCount) {
        // Too many frames for the window server: keep every n-th frame and show each one
        // n times as long, so the animation still runs at the same speed.
        NSUInteger step = (frameCount + MCMaxFrameCount - 1) / MCMaxFrameCount;
        NSUInteger count = (frameCount + step - 1) / step;
        NSUInteger indices[MCMaxFrameCount];
        for (NSUInteger k = 0; k < count; k++) indices[k] = k * step;
        NSArray *sheets = sheetsWithFrames(images, frameCount, indices, count);
        if (sheets) {
            MMLog("Reducing %s from %lu to %lu frames", ident.UTF8String, (unsigned long)frameCount, (unsigned long)count);
            images = sheets;
            frameDuration *= step;
            frameCount = count;
        }
    }
    if (frameCount > MCMaxFrameCount || frameCount < 1) {
        MMLog(BOLD RED "Frame count of %s out of range [1...24]", ident.UTF8String);
        return NO;
    }

    char *idenfifier = (char *)ident.UTF8String;
    int seed = 0;
    CGError err = CGSRegisterCursorWithImages(CGSMainConnectionID(),
                                              idenfifier,
                                              true,
                                              true,
                                              size,
                                              hotSpot,
                                              frameCount,
                                              frameDuration,
                                              (__bridge CFArrayRef)images,
                                              &seed);
    
    if (err != kCGErrorSuccess)
        MMLog(BOLD RED "Registering %s failed (error %d)" RESET, ident.UTF8String, err);
    return (err == kCGErrorSuccess);
}

BOOL applyCapeForIdentifier(NSDictionary *cursor, NSString *identifier, BOOL restore) {
    if (!cursor || !identifier) {
        NSLog(@"bad seed");
        return NO;
    }

    BOOL lefty = MCFlag(MCPreferencesHandednessKey) && !restore;
    // Left-handed mode: the cursor's own left-handed images if it has them; otherwise
    // mirrored when the cape says so, or, without a say, when it is a pointer.
    NSArray *leftReps = cursor[MCCursorDictionaryLeftHandedRepresentationsKey];
    BOOL ownImages = lefty && [leftReps isKindOfClass:[NSArray class]] && leftReps.count > 0;
    NSNumber *mirrorFlag = cursor[MCCursorDictionaryMirrorForLeftHandedKey];
    BOOL mirror = lefty && !ownImages
        && ([mirrorFlag isKindOfClass:[NSNumber class]] ? mirrorFlag.boolValue : MCCursorIsPointer(identifier));
    NSNumber *frameCount    = cursor[MCCursorDictionaryFrameCountKey];
    NSNumber *frameDuration = cursor[MCCursorDictionaryFrameDuratiomKey];
    //    NSNumber *repeatCount   = cursor[MCCursorDictionaryRepeatCountKey];
    
    CGPoint hotSpot         = CGPointMake([cursor[MCCursorDictionaryHotSpotXKey] doubleValue],
                                          [cursor[MCCursorDictionaryHotSpotYKey] doubleValue]);
    CGSize size             = CGSizeMake([cursor[MCCursorDictionaryPointsWideKey] doubleValue],
                                         [cursor[MCCursorDictionaryPointsHighKey] doubleValue]);
    NSArray *reps           = ownImages ? leftReps : cursor[MCCursorDictionaryRepresentationsKey];
    NSMutableArray *images  = [NSMutableArray array];

    if (ownImages) {
        MMLog("Left-handed images for %s", identifier.UTF8String);
        NSNumber *x = cursor[MCCursorDictionaryLeftHandedHotSpotXKey], *y = cursor[MCCursorDictionaryLeftHandedHotSpotYKey];
        hotSpot = (x && y) ? CGPointMake(x.doubleValue, y.doubleValue) : CGPointMake(size.width - hotSpot.x - 1, hotSpot.y);
    } else if (mirror) {
        MMLog("Lefty mode for %s", identifier.UTF8String);
        hotSpot.x = size.width - hotSpot.x - 1;
    }

    for (id object in reps) {
        CFTypeID type = CFGetTypeID((__bridge CFTypeRef)object);
        NSBitmapImageRep *rep;
        if (type == CGImageGetTypeID()) {
            rep = [[[NSBitmapImageRep alloc] initWithCGImage:(__bridge CGImageRef)object] autorelease];
        } else {
            rep = [[[NSBitmapImageRep alloc] initWithData:object] autorelease];
        }
        rep = rep.retaggedSRGBSpace;

        if (!mirror) {
            // special case if array has a type of CGImage already there is no need to convert it
            if (type == CGImageGetTypeID()) {
                images[images.count] = object;
                continue;
            }
            
            images[images.count] = (__bridge id)[rep CGImage];
            
        } else {
            NSBitmapImageRep *newRep = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                               pixelsWide:rep.pixelsWide
                                                                               pixelsHigh:rep.pixelsHigh
                                                                            bitsPerSample:8
                                                                          samplesPerPixel:4
                                                                                 hasAlpha:YES
                                                                                 isPlanar:NO
                                                                           colorSpaceName:NSCalibratedRGBColorSpace
                                                                              bytesPerRow:4 * rep.pixelsWide
                                                                             bitsPerPixel:32] autorelease];
            NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:newRep];
            [NSGraphicsContext saveGraphicsState];
            [NSGraphicsContext setCurrentContext:ctx];
            NSAffineTransform *transform = [NSAffineTransform transform];
            [transform translateXBy:rep.pixelsWide yBy:0];
            [transform scaleXBy:-1 yBy:1];
            [transform concat];

            [rep drawInRect:NSMakeRect(0, 0, rep.pixelsWide, rep.pixelsHigh)
                   fromRect:NSZeroRect
                  operation:NSCompositingOperationSourceOver
                   fraction:1.0
             respectFlipped:NO
                      hints:nil];
            [NSGraphicsContext restoreGraphicsState];
            images[images.count] = (__bridge id)[newRep CGImage];
        }
    }
    
    NSArray *sheets = images;
    NSUInteger count = frameCount.unsignedIntegerValue;
    CGFloat duration = frameDuration.doubleValue;
    // Frames with their own durations: the window server takes one duration for all, so
    // pick the frames by time instead of keeping every n-th one at the average.
    NSArray *durations = cursor[MCCursorDictionaryFrameDurationsKey];
    if (!restore && [durations isKindOfClass:[NSArray class]] && durations.count == count && count > 1) {
        NSUInteger indices[MCMaxFrameCount];
        CGFloat timed = duration;
        NSUInteger timedCount = framesByTime(durations, indices, &timed);
        NSArray *timedSheets = timedCount > 0 ? sheetsWithFrames(images, count, indices, timedCount) : nil;
        if (timedSheets) {
            MMLog("Timing %s by its frame durations: %lu frames of %.3f s", identifier.UTF8String,
                  (unsigned long)timedCount, timed);
            sheets = timedSheets;
            count = timedCount;
            duration = timed;
        }
    }

    return applyCursorForIdentifier(count, duration, hotSpot, size, sheets, identifier, 0);
}

BOOL applyCape(NSDictionary *dictionary) {
    @autoreleasepool {
        NSDictionary *cursors = dictionary[MCCursorDictionaryCursorsKey];
        NSString *name = dictionary[MCCursorDictionaryCapeNameKey];
        NSNumber *version = dictionary[MCCursorDictionaryCapeVersionKey];

        // The identifier is stored and later becomes a path (the agent reads
        // capes/<identifier>.cape at login), so it has to be a plain file name.
        if (!MCIsSafeIdentifier(dictionary[MCCursorDictionaryIdentifierKey])) {
            MMLog(BOLD RED "The cape's identifier can't be used as a file name" RESET);
            return NO;
        }
        
        resetAllCursors();
        backupAllCursors();
        
        MMLog("Applying cape: %s %.02f", name.UTF8String, version.floatValue);
        
        // Remember cursors outside the standard set before registering them, so a reset
        // can take them away again even if this apply stops halfway.
        NSMutableSet *extras = [NSMutableSet setWithArray:MCDefault(MCPreferencesAppliedExtraCursorsKey) ?: @[]];
        for (NSString *key in cursors) {
            if (!MCCursorIsStandard(key))
                [extras addObject:key];
        }
        MCSetDefault(extras.allObjects, MCPreferencesAppliedExtraCursorsKey);

        // A cursor that fails is skipped; one bad cursor should not leave the cape half applied.
        NSUInteger failed = 0;
        for (NSString *key in cursors) {
            NSDictionary *cape = cursors[key];
            // A variant such as IBeamS with an entry of its own takes its base's mirror
            // setting unless it has its own, so IBeam and IBeamS look alike in left-handed
            // mode. (Not the base's left-handed images: they may not fit. A variant without
            // an entry gets the base's whole entry anyway, below.)
            NSString *base = MCBaseCursorForExtra(key);
            NSDictionary *baseCape = base ? cursors[base] : nil;
            if (baseCape && !cape[MCCursorDictionaryMirrorForLeftHandedKey] && !cape[MCCursorDictionaryLeftHandedRepresentationsKey]) {
                NSMutableDictionary *inherited = [[cape mutableCopy] autorelease];
                if (baseCape[MCCursorDictionaryMirrorForLeftHandedKey])
                    inherited[MCCursorDictionaryMirrorForLeftHandedKey] = baseCape[MCCursorDictionaryMirrorForLeftHandedKey];
                cape = inherited;
            }
            MMLog("Hooking for %s", key.UTF8String);
            
            BOOL success = applyCapeForIdentifier(cape, key, NO);
            if (!success) {
                MMLog(BOLD RED "Failed to hook identifier %s, skipping it" RESET, key.UTF8String);
                failed++;
            }
        }

        // A variant like ArrowS left over from an earlier cape would hide this cape's Arrow
        // where macOS uses the variant; give it this cape's cursor too.
        for (NSUInteger i = 0; extraCursors[i] != nil; i++) {
            NSString *extra = extraCursors[i];
            NSString *base = MCBaseCursorForExtra(extra);
            bool registered = false;
            MCIsCursorRegistered(CGSMainConnectionID(), (char *)extra.UTF8String, &registered);
            if (registered && !cursors[extra] && base && cursors[base]) {
                MMLog("Using %s for %s", base.UTF8String, extra.UTF8String);
                applyCapeForIdentifier(cursors[base], extra, NO);
            }
        }

        if (failed == cursors.count && failed > 0) {
            MMLog(BOLD RED "Could not apply any cursor of %s" RESET, name.UTF8String);
            resetAllCursors();
            return NO;
        }
        
        MCSetDefault(dictionary[MCCursorDictionaryIdentifierKey], MCPreferencesAppliedCursorKey);
        
        if (failed > 0) {
            MMLog(BOLD YELLOW "Applied %s, but %lu cursors failed" RESET, name.UTF8String, (unsigned long)failed);
            return NO;
        }
        MMLog(BOLD GREEN "Applied %s successfully!" RESET, name.UTF8String);
        
        return YES;
    }
}

BOOL applyCapeAtPath(NSString *path) {
    NSDictionary *cape = [NSDictionary dictionaryWithContentsOfFile:path];
    if (cape)
        return applyCape(cape);
    MMLog(BOLD RED "Could not find valid file at %s to apply" RESET, path.UTF8String);
    return NO;
}

BOOL applyDefaultCursors(void) {
    BOOL reset = resetAllCursors();
    if (!MCFlag(MCPreferencesHandednessKey))
        return reset;

    // Left-handed: register mirrored copies of the system's pointers, taken from what the
    // reset just put back. The backups keep the unmirrored ones for the next reset.
    backupAllCursors();
    NSMutableArray *identifiers = [MCPointerCursorIdentifiers() mutableCopy];
    for (NSUInteger i = 0; extraCursors[i] != nil; i++) {
        bool registered = false;
        MCIsCursorRegistered(CGSMainConnectionID(), (char *)extraCursors[i].UTF8String, &registered);
        if (registered && MCCursorIsPointer(extraCursors[i]))
            [identifiers addObject:extraCursors[i]];
    }
    NSUInteger failed = 0;
    for (NSString *identifier in identifiers) {
        NSDictionary *cursor = capeWithIdentifier(identifier);
        if (!cursor)
            continue;
        MMLog("Mirroring %s", identifier.UTF8String);
        if (!applyCapeForIdentifier(cursor, identifier, NO))
            failed++;
    }
    if (failed)
        MMLog(BOLD RED "Could not mirror %lu cursors" RESET, (unsigned long)failed);
    return reset && failed == 0;
}
