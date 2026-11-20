//
//  backup.m
//  Mousecape
//
//  Created by Alex Zielenski on 2/1/14.
//  Copyright (c) 2014 Alex Zielenski. All rights reserved.
//

#import "MCDefs.h"
#import "backup.h"
#import "apply.h"
#import "MCPrefs.h"

NSString *backupStringForIdentifier(NSString *identifier) {
    return [NSString stringWithFormat:@"com.alexzielenski.mousecape.%@", identifier];
}

void backupCursorForIdentifier(NSString *ident) {
    bool registered = false;
    MCIsCursorRegistered(CGSMainConnectionID(), (char *)ident.UTF8String, &registered);
    
//     dont try to backup a nonexistant cursor
    if (!registered)
        return;
    
    NSString *backupIdent = backupStringForIdentifier(ident);
    MCIsCursorRegistered(CGSMainConnectionID(), (char *)backupIdent.UTF8String, &registered);
    
//     don't re-back it up
    if (registered)
        return;
    
    NSDictionary *cape = capeWithIdentifier(ident);
    (void)applyCapeForIdentifier(cape, backupIdent, YES);
    
}

// Backs up what is on screen, so a reset can bring it back. A cursor that has a backup
// already keeps it (backupCursorForIdentifier skips it).
//
// A backup of the arrow means something was applied in this login session (by this engine
// or the original Mousecape, which use the same backup names), so the standard cursors on
// screen may be a cape's: those are left alone then. Variants like ArrowS are checked one by
// one instead. The original Mousecape doesn't know them, so a variant without a backup still
// shows the system's cursor, unless Mousecape itself registered it (MCAppliedExtraCursors).
// Skipping them all, as before, left ArrowS and IBeamS without a backup on macOS 27 once the
// original Mousecape had backed up the arrow.
void backupAllCursors() {
    bool arrowBackedUp = false;
    MCIsCursorRegistered(CGSMainConnectionID(), (char *)backupStringForIdentifier(@"com.apple.coregraphics.Arrow").UTF8String, &arrowBackedUp);

    NSArray *registeredByMousecape = @[];
    if (arrowBackedUp) {
        MMLog("The standard cursors are backed up already");
        registeredByMousecape = MCDefault(MCPreferencesAppliedExtraCursorsKey) ?: @[];
    } else {
        // Nothing applied in this session yet (or a reset removed the backups), so the
        // cursors are the system's. A list of variants left from an earlier session is stale.
        MCSetDefault(NULL, MCPreferencesAppliedExtraCursorsKey);
        for (NSUInteger i = 0; defaultCursors[i] != nil; i++) {
            backupCursorForIdentifier(defaultCursors[i]);
        }
    }

    // Variants are backed up only when they are registered, which on macOS 15 means a cape
    // put them there: those are in the list and skipped, and a reset removes them.
    for (NSUInteger i = 0; extraCursors[i] != nil; i++) {
        if (![registeredByMousecape containsObject:extraCursors[i]])
            backupCursorForIdentifier(extraCursors[i]);
    }
    // no need to backup core cursors
}