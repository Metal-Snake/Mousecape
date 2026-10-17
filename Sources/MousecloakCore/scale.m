//
//  scale.m
//  Mousecape
//
//  Created by Alex Zielenski on 2/2/14.
//  Copyright (c) 2014 Alex Zielenski. All rights reserved.
//

#import "MCDefs.h"
#import "scale.h"
#import "MCPrefs.h"

float cursorScale() {
    float value;
    CGSGetCursorScale(CGSMainConnectionID(), &value);
    return value;
}

float defaultCursorScale() {
    float scale = [MCDefault(MCPreferencesCursorScaleKey) floatValue];
    if (scale < .5 || scale > 16)
        scale = 1;
    return scale;
}

// The scale to keep: the one saved in Mousecape's settings, or else the one set right now
// (e.g. the Accessibility pointer size), so an unset preference never forces 1x.
float preferredCursorScale() {
    return MCDefault(MCPreferencesCursorScaleKey) != nil ? defaultCursorScale() : cursorScale();
}

BOOL setCursorScale(float dbl) {
    if (dbl > 32) {
        MMLog("Not a good idea...");
        return NO;
    } else if (CGSSetCursorScale(CGSMainConnectionID(), dbl) == noErr) {
        MMLog("Successfully set cursor scale!");
        return YES;
    } else {
        MMLog("Somehow failed to set cursor scale!");
        return NO;
    }
}
