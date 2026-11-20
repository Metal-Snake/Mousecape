//
//  create.h
//  Mousecape
//
//  Created by Alex Zielenski on 2/1/14.
//  Copyright (c) 2014 Alex Zielenski. All rights reserved.
//

#ifndef Mousecape_create_h
#define Mousecape_create_h

#import "MCDefs.h"
// Converts a MightyMouse file into a cape file; asks for the cape's details on stdin.
extern NSError *convertMightyMouseFile(NSString *input, NSString *output);

extern NSDictionary *processedCapeWithIdentifier(NSString *identifier);
extern BOOL dumpCursorsToFile(NSString *path, BOOL (^progress)(NSUInteger current, NSUInteger total));
extern BOOL dumpCursorsToFolder(NSString *path, BOOL (^progress)(NSUInteger current, NSUInteger total));

extern NSDictionary *createCapeFromMightyMouse(NSDictionary *mightyMouse, NSDictionary *metadata);

extern void exportCape(NSDictionary *cape, NSString *destination);

#endif
