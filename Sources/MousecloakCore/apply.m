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

// Keeps every `step`-th frame of each vertically stacked sheet, `count` frames in all.
static NSArray *downsampledSheets(NSArray *sheets, NSUInteger frameCount, NSUInteger step, NSUInteger count) {
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
            CGImageRef frame = CGImageCreateWithImageInRect(sheet, CGRectMake(0, k * step * frameHeight, width, frameHeight));
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

BOOL applyCursorForIdentifier(NSUInteger frameCount, CGFloat frameDuration, CGPoint hotSpot, CGSize size, NSArray *images, NSString *ident, NSUInteger repeatCount) {
    if (frameCount > MCMaxFrameCount) {
        // Too many frames for the window server: keep every n-th frame and show each one
        // n times as long, so the animation still runs at the same speed.
        NSUInteger step = (frameCount + MCMaxFrameCount - 1) / MCMaxFrameCount;
        NSUInteger count = (frameCount + step - 1) / step;
        NSArray *sheets = downsampledSheets(images, frameCount, step, count);
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
    
    return (err == kCGErrorSuccess);
}

BOOL applyCapeForIdentifier(NSDictionary *cursor, NSString *identifier, BOOL restore) {
    if (!cursor || !identifier) {
        NSLog(@"bad seed");
        return NO;
    }

    BOOL lefty = MCFlag(MCPreferencesHandednessKey);
    BOOL pointer = MCCursorIsPointer(identifier);
    NSNumber *frameCount    = cursor[MCCursorDictionaryFrameCountKey];
    NSNumber *frameDuration = cursor[MCCursorDictionaryFrameDuratiomKey];
    //    NSNumber *repeatCount   = cursor[MCCursorDictionaryRepeatCountKey];
    
    CGPoint hotSpot         = CGPointMake([cursor[MCCursorDictionaryHotSpotXKey] doubleValue],
                                          [cursor[MCCursorDictionaryHotSpotYKey] doubleValue]);
    CGSize size             = CGSizeMake([cursor[MCCursorDictionaryPointsWideKey] doubleValue],
                                         [cursor[MCCursorDictionaryPointsHighKey] doubleValue]);
    NSArray *reps           = cursor[MCCursorDictionaryRepresentationsKey];
    NSMutableArray *images  = [NSMutableArray array];

    if (lefty && !restore && pointer) {
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

        if (!lefty || restore || !pointer) {
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
    
    return applyCursorForIdentifier(frameCount.unsignedIntegerValue, frameDuration.doubleValue, hotSpot, size, images, identifier, 0);
}

BOOL applyCape(NSDictionary *dictionary) {
    @autoreleasepool {
        NSDictionary *cursors = dictionary[MCCursorDictionaryCursorsKey];
        NSString *name = dictionary[MCCursorDictionaryCapeNameKey];
        NSNumber *version = dictionary[MCCursorDictionaryCapeVersionKey];
        
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
