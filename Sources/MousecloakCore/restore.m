//
//  restore.m
//  Mousecape
//
//  Created by Alex Zielenski on 2/1/14.
//  Copyright (c) 2014 Alex Zielenski. All rights reserved.
//

#import "MCDefs.h"
#import "backup.h"
#import "apply.h"
#import "MCPrefs.h"

NSString *restoreStringForIdentifier(NSString *identifier) {
    return [identifier substringFromIndex:28];
}

// Whether `ident` now carries the images described by `reference`: same point size, frame
// count and pixel sizes. Registering can report success and still change nothing, so every
// restore is checked against what it should have produced. The window server may add
// scaled copies of the images, so extra pixel sizes are fine.
static BOOL registrationMatches(NSString *ident, NSDictionary *reference) {
    NSDictionary *now = capeWithIdentifier(ident);
    if (!now || !reference)
        return NO;
    for (const NSString *key in @[MCCursorDictionaryPointsWideKey, MCCursorDictionaryPointsHighKey]) {
        if (fabs([now[key] doubleValue] - [reference[key] doubleValue]) > 0.01)
            return NO;
    }
    // A backup over the frame limit is applied reduced, so compare with that in mind.
    NSUInteger expectedFrames = [reference[MCCursorDictionaryFrameCountKey] unsignedIntegerValue];
    if (expectedFrames > MCMaxFrameCount) {
        NSUInteger step = (expectedFrames + MCMaxFrameCount - 1) / MCMaxFrameCount;
        expectedFrames = (expectedFrames + step - 1) / step;
    }
    if ([now[MCCursorDictionaryFrameCountKey] unsignedIntegerValue] != expectedFrames)
        return NO;
    NSMutableSet *sizesNow = [NSMutableSet set];
    for (id image in now[MCCursorDictionaryRepresentationsKey])
        [sizesNow addObject:@(CGImageGetWidth((CGImageRef)image))];
    for (id image in reference[MCCursorDictionaryRepresentationsKey]) {
        if (![sizesNow containsObject:@(CGImageGetWidth((CGImageRef)image))])
            return NO;
    }
    return YES;
}

// Puts a cursor back from its backup. Returns YES only when the backup was there and the
// cursor now matches it.
BOOL restoreCursorForIdentifier(NSString *ident) {
    bool registered = false;
    MCIsCursorRegistered(CGSMainConnectionID(), (char *)ident.UTF8String, &registered);

    NSString *restoreIdent = restoreStringForIdentifier(ident);
    NSDictionary *cape = capeWithIdentifier(ident);
    
    MMLog("Restoring cursor %s from %s", restoreIdent.UTF8String, ident.UTF8String);
    BOOL restored = NO;
    if (cape && registered) {
        restored = applyCapeForIdentifier(cape, restoreIdent, YES);
        if (restored && !registrationMatches(restoreIdent, cape)) {
            MMLog(BOLD RED "Restoring %s reported success but changed nothing" RESET, restoreIdent.UTF8String);
            restored = NO;
        }
    }

    CGSRemoveRegisteredCursor(CGSMainConnectionID(), (char *)ident.UTF8String, false);
    return restored;
}

// Restores an extra cursor from its backup, or unregisters it when the system never had
// it. Returns NO if it is still showing something it shouldn't.
static BOOL removeExtraCursor(NSString *ident) {
    bool hasBackup = false;
    MCIsCursorRegistered(CGSMainConnectionID(), (char *)backupStringForIdentifier(ident).UTF8String, &hasBackup);
    if (hasBackup && restoreCursorForIdentifier(backupStringForIdentifier(ident))) {
        MMLog("Restored %s from its backup", ident.UTF8String);
        return YES;
    }
    bool registered = false;
    MCIsCursorRegistered(CGSMainConnectionID(), (char *)ident.UTF8String, &registered);
    if (!registered)
        return YES;

    // The window server only lets the process that registered a cursor remove it, and
    // that process is usually gone. A variant like ArrowS then gets the restored
    // standard cursor instead, so it looks like the default wherever macOS uses it.
    // A removal that reports success is checked too: it must actually be gone.
    CGError removal = CGSRemoveRegisteredCursor(CGSMainConnectionID(), (char *)ident.UTF8String, false);
    MCIsCursorRegistered(CGSMainConnectionID(), (char *)ident.UTF8String, &registered);
    if (!registered) {
        MMLog("Removed %s", ident.UTF8String);
        return YES;
    }
    MMLog("Could not remove %s (error %d)", ident.UTF8String, removal);
    // The default comes from the base cursor's backup. On macOS 27 a registered variant
    // shadows its base, even when reading it: asking for Arrow returns ArrowS. So the
    // base itself would hand back the cape's image, and the variant would be "reset" to
    // what it already shows.
    NSString *base = MCBaseCursorForExtra(ident);
    NSDictionary *standard = nil;
    if (base) {
        bool baseBackedUp = false;
        MCIsCursorRegistered(CGSMainConnectionID(), (char *)backupStringForIdentifier(base).UTF8String, &baseBackedUp);
        standard = baseBackedUp ? capeWithIdentifier(backupStringForIdentifier(base)) : capeWithIdentifier(base);
    }
    if (standard) {
        MMLog("Resetting %s to the default %s", ident.UTF8String, base.UTF8String);
        if (applyCapeForIdentifier(standard, ident, YES) && registrationMatches(ident, standard))
            return YES;
        MMLog(BOLD RED "Resetting %s had no effect" RESET, ident.UTF8String);
        return NO;
    }
    MMLog(BOLD YELLOW "Could not reset %s" RESET, ident.UTF8String);
    return NO;
}

BOOL resetAllCursors() {
    MMLog("Restoring cursors...");
    NSMutableArray *failed = [NSMutableArray array];
    
    // Cursors outside the standard set first: put back what the system had, remove the rest.
    // On macOS 27 a variant like ArrowS shadows its base, so Arrow can only be restored
    // and checked once ArrowS shows the default again.
    NSMutableSet *extras = [NSMutableSet setWithArray:MCDefault(MCPreferencesAppliedExtraCursorsKey) ?: @[]];
    for (NSUInteger i = 0; extraCursors[i] != nil; i++) {
        [extras addObject:extraCursors[i]];
    }
    for (NSString *extra in extras) {
        if (!removeExtraCursor(extra))
            [failed addObject:extra];
    }
    MCSetDefault(NULL, MCPreferencesAppliedExtraCursorsKey);

    // Then the standard cursors, from their backups
    NSUInteger i = 0;
    NSString *key = nil;
    BOOL waitRestored = YES;
    while ((key = defaultCursors[i]) != nil) {
        bool hasBackup = false;
        MCIsCursorRegistered(CGSMainConnectionID(), (char *)backupStringForIdentifier(key).UTF8String, &hasBackup);
        BOOL restored = restoreCursorForIdentifier(backupStringForIdentifier(key));
        if ([key isEqualToString:@"com.apple.coregraphics.Wait"])
            waitRestored = restored;
        else if (hasBackup && !restored)
            [failed addObject:key];
        i++;
    }

    // Backup auxiliary cursors
    MMLog("Restoring core cursors...");
    if (CoreCursorUnregisterAll(CGSMainConnectionID()) == 0) {
        MCSetDefault(NULL, MCPreferencesAppliedCursorKey);
        
        for (int x = 0; x < 45; x++) {
            CoreCursorSet(CGSMainConnectionID(), x);
        }

        // Without a backup of Wait (older versions could not back up its long animation),
        // take the system's busy cursor, which the core cursors just brought back.
        if (!waitRestored) {
            NSDictionary *busy = capeWithIdentifier(@"com.apple.cursor.4");
            if (busy) {
                MMLog("Resetting Wait to the system busy cursor");
                if (!applyCapeForIdentifier(busy, @"com.apple.coregraphics.Wait", YES)
                    || !registrationMatches(@"com.apple.coregraphics.Wait", busy))
                    [failed addObject:@"com.apple.coregraphics.Wait"];
            }
        }
    } else {
        MMLog(BOLD RED "Received an error while restoring core cursors." RESET);
        [failed addObject:@"core cursors"];
    }

    if (failed.count) {
        MMLog(BOLD RED "Could not reset: %s" RESET, [failed componentsJoinedByString:@", "].UTF8String);
        return NO;
    }
    MMLog(BOLD GREEN "Successfully restored all cursors." RESET);
    return YES;
}
