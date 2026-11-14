//
//  listen.m
//  Mousecape
//
//  Created by Alex Zielenski on 2/1/14.
//  Copyright (c) 2014 Alex Zielenski. All rights reserved.
//

#import "MCDefs.h"
#import "listen.h"
#import "apply.h"
#import <SystemConfiguration/SystemConfiguration.h>
#import "MCPrefs.h"
#import "CGSInternal/CGSCursor.h"
#import <Cocoa/Cocoa.h>
#import "scale.h"

NSString *appliedCapePathForUser(NSString *user) {
    NSString *home = NSHomeDirectoryForUser(user);
    NSString *ident =     MCDefaultFor(@"MCAppliedCursor", user, (NSString *)kCFPreferencesCurrentHost);
    if (!MCIsSafeIdentifier(ident))
        return nil;
    NSString *appSupport = [home stringByAppendingPathComponent:@"Library/Application Support"];
    return [[[appSupport stringByAppendingPathComponent:@"Mousecape/capes"] stringByAppendingPathComponent:ident] stringByAppendingPathExtension:@"cape"];
}

// What the user set up: the applied cape, or with none, the macOS cursors (mirrored in
// left-handed mode; untouched otherwise).
static BOOL applySetupForUser(NSString *user) {
    NSString *path = appliedCapePathForUser(user);
    if (path)
        return applyCapeAtPath(path);
    if (MCFlag(MCPreferencesHandednessKey))
        return applyDefaultCursors();
    return YES;
}

static void UserSpaceChanged(SCDynamicStoreRef	store, CFArrayRef changedKeys, void *info) {
    CFStringRef currentConsoleUser = SCDynamicStoreCopyConsoleUser(store, NULL, NULL);
    
    MMLog("Current user is %s", [(__bridge NSString *)currentConsoleUser UTF8String]);
    
    if (!currentConsoleUser || CFEqual(currentConsoleUser, CFSTR("loginwindow"))) {
        if (currentConsoleUser)
            CFRelease(currentConsoleUser);
        return;
    }
    
    MMLog(BOLD GREEN "User Space Changed to %s, applying cape..." RESET, [(__bridge NSString *)currentConsoleUser UTF8String]);
    if (!applySetupForUser((__bridge NSString *)currentConsoleUser)) {
        MMLog(BOLD RED "Application of cape failed" RESET);
    }
    
    setCursorScale(preferredCursorScale());
    
    CFRelease(currentConsoleUser);
}

// Counts display reconfiguration callbacks, so that only the last of a burst applies.
static NSUInteger reconfigurationCount = 0;

// macOS calls this for every display, both before and after each change. Applying the whole
// cape each time decoded and registered it several times in a row. Calls before a change
// are skipped, and the cape is applied once, a moment after the last of the others.
void reconfigurationCallback(CGDirectDisplayID display,
    	CGDisplayChangeSummaryFlags flags,
    	void *userInfo) {
    if (flags & kCGDisplayBeginConfigurationFlag)
        return;
    NSUInteger count = ++reconfigurationCount;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (count != reconfigurationCount)
            return;     // a later callback follows
        MMLog("Reconfigure user space");
        applySetupForUser(NSUserName());
        // Restore the preferred scale instead of re-reading the current one: newer macOS
        // versions (seen on the macOS 27 beta) reset the scale to 1x on display changes.
        // Setting another value first makes the window server redraw the cursor.
        float scale = preferredCursorScale();
        CGSSetCursorScale(CGSMainConnectionID(), scale + .3);
        CGSSetCursorScale(CGSMainConnectionID(), scale);
    });
}


void listener(void) {
    SCDynamicStoreRef store = SCDynamicStoreCreate(NULL, CFSTR("com.apple.dts.ConsoleUser"), UserSpaceChanged, NULL);
    assert(store != NULL);
    
    CFStringRef key = SCDynamicStoreKeyCreateConsoleUser(NULL);
    assert(key != NULL);
    
    CFArrayRef keys = CFArrayCreate(NULL, (const void **)&key, 1, &kCFTypeArrayCallBacks);
    assert(keys != NULL);
    
    Boolean success = SCDynamicStoreSetNotificationKeys(store, keys, NULL);
    assert(success);
    
    NSApplicationLoad();
    CGDisplayRegisterReconfigurationCallback(reconfigurationCallback, NULL);
    MMLog(BOLD CYAN "Listening for Display changes" RESET);
    
    CFRunLoopSourceRef rls = SCDynamicStoreCreateRunLoopSource(NULL, store, 0);
    assert(rls != NULL);
    MMLog(BOLD CYAN "Listening for User changes" RESET);
    
    // Apply the cape for the user on load
    applySetupForUser(NSUserName());
    setCursorScale(preferredCursorScale());
    
    CFRunLoopAddSource(CFRunLoopGetCurrent(), rls, kCFRunLoopDefaultMode);
    CFRunLoopRun();

    // Cleanup
    CFRunLoopSourceInvalidate(rls);
    CFRelease(rls);
    CFRelease(keys);
    CFRelease(key);
    CFRelease(store);
}