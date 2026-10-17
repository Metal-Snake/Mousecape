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

// Returns whether a backup was there to restore from.
BOOL restoreCursorForIdentifier(NSString *ident) {
    bool registered = false;
    MCIsCursorRegistered(CGSMainConnectionID(), (char *)ident.UTF8String, &registered);

    NSString *restoreIdent = restoreStringForIdentifier(ident);
    NSDictionary *cape = capeWithIdentifier(ident);
    
    MMLog("Restoring cursor %s from %s", restoreIdent.UTF8String, ident.UTF8String);
    BOOL restored = NO;
    if (cape && registered) {
        restored = applyCapeForIdentifier(cape, restoreIdent, YES);
    }

    CGSRemoveRegisteredCursor(CGSMainConnectionID(), (char *)ident.UTF8String, false);
    return restored;
}

// Restores an extra cursor from its backup, or unregisters it when the system never had it.
static void removeExtraCursor(NSString *ident) {
    bool hasBackup = false;
    MCIsCursorRegistered(CGSMainConnectionID(), (char *)backupStringForIdentifier(ident).UTF8String, &hasBackup);
    if (hasBackup && restoreCursorForIdentifier(backupStringForIdentifier(ident))) {
        MMLog("Restored %s from its backup", ident.UTF8String);
        return;
    }
    bool registered = false;
    MCIsCursorRegistered(CGSMainConnectionID(), (char *)ident.UTF8String, &registered);
    if (!registered)
        return;

    // The window server only lets the process that registered a cursor remove it, and
    // that process is usually gone. A variant like ArrowS then gets the restored
    // standard cursor instead, so it looks like the default wherever macOS uses it.
    // A removal that reports success is checked too: it must actually be gone.
    CGError removal = CGSRemoveRegisteredCursor(CGSMainConnectionID(), (char *)ident.UTF8String, false);
    MCIsCursorRegistered(CGSMainConnectionID(), (char *)ident.UTF8String, &registered);
    if (!registered) {
        MMLog("Removed %s", ident.UTF8String);
        return;
    }
    MMLog("Could not remove %s (error %d)", ident.UTF8String, removal);
    NSString *base = MCBaseCursorForExtra(ident);
    NSDictionary *standard = base ? capeWithIdentifier(base) : nil;
    if (standard) {
        MMLog("Resetting %s to the default %s", ident.UTF8String, base.UTF8String);
        applyCapeForIdentifier(standard, ident, YES);
    } else {
        MMLog(BOLD YELLOW "Could not reset %s" RESET, ident.UTF8String);
    }
}

void resetAllCursors() {
    MMLog("Restoring cursors...");
    
    // Backup main cursors first
    NSUInteger i = 0;
    NSString *key = nil;
    BOOL waitRestored = YES;
    while ((key = defaultCursors[i]) != nil) {
        BOOL restored = restoreCursorForIdentifier(backupStringForIdentifier(key));
        if ([key isEqualToString:@"com.apple.coregraphics.Wait"])
            waitRestored = restored;
        i++;
    }

    // Cursors outside the standard set: put back what the system had, remove the rest.
    NSMutableSet *extras = [NSMutableSet setWithArray:MCDefault(MCPreferencesAppliedExtraCursorsKey) ?: @[]];
    for (i = 0; extraCursors[i] != nil; i++) {
        [extras addObject:extraCursors[i]];
    }
    for (NSString *extra in extras) {
        removeExtraCursor(extra);
    }
    MCSetDefault(NULL, MCPreferencesAppliedExtraCursorsKey);

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
                applyCapeForIdentifier(busy, @"com.apple.coregraphics.Wait", YES);
            }
        }
        
        MMLog(BOLD GREEN "Successfully restored all cursors." RESET);
    } else
        MMLog(BOLD RED "Received an error while restoring core cursors." RESET);
}
