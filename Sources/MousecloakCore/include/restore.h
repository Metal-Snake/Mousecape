//
//  restore.h
//  Mousecape
//
//  Created by Alex Zielenski on 2/1/14.
//  Copyright (c) 2014 Alex Zielenski. All rights reserved.
//

#ifndef Mousecape_restore_h
#define Mousecape_restore_h

#import "MCDefs.h"

extern NSString *restoreStringForIdentifier(NSString *identifier);
extern BOOL restoreCursorForIdentifier(NSString *ident);
// Returns NO when some cursor could not be put back (the log says which).
extern BOOL resetAllCursors(void);

#endif
