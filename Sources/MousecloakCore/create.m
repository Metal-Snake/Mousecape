//
//  create.m
//  Mousecape
//
//  Created by Alex Zielenski on 2/1/14.
//  Copyright (c) 2014 Alex Zielenski. All rights reserved.
//

#import "MCDefs.h"
#import "create.h"
#import "NSCursor_Private.h"
#import "NSBitmapImageRep+ColorSpace.h"

NSError *createCape(NSString *input, NSString *output, BOOL convert) {
    NSDictionary *cape;
    if (convert)
        cape = createCapeFromMightyMouse([NSDictionary dictionaryWithContentsOfFile:input], nil);
    else
        cape = createCapeFromDirectory(input);
    
    if (!cape) {
        if (convert)
            return [NSError errorWithDomain:MCErrorDomain code:MCErrorInvalidCapeCode userInfo:@{
                                                                                                 NSLocalizedDescriptionKey: NSLocalizedString(@"Failed to create cape file", nil),
                                                                                                 NSLocalizedFailureReasonErrorKey: NSLocalizedString(@"Unabled to create a cape from the file specified.", nil) }];
        else
            return [NSError errorWithDomain:MCErrorDomain code:MCErrorInvalidCapeCode userInfo:@{
                                                                                                 NSLocalizedDescriptionKey: NSLocalizedString(@"Failed to create cape file", nil),
                                                                                                 NSLocalizedFailureReasonErrorKey: NSLocalizedString(@"Unabled to create a cape from the directory specified.", nil) }];
    }
    
    if (![cape writeToFile:output atomically:NO]) {
        return [NSError errorWithDomain:MCErrorDomain code:MCErrorWriteFailCode userInfo:@{
                                                                                           NSLocalizedDescriptionKey: NSLocalizedString(@"Failed to create cape file", nil),
                                                                                           NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat: NSLocalizedString(@"The destination, %@, is not writable.", nil), output] }];
    }

    return nil;
}

NSDictionary *createCapeFromDirectory(NSString *path) {
    NSFileManager *manager = [NSFileManager defaultManager];
    
    BOOL isDir;
    BOOL exists = [manager fileExistsAtPath:path isDirectory:&isDir];
    
    if (!exists || !isDir)
        return nil;
    
    NSArray *contents = [manager contentsOfDirectoryAtPath:path error:nil];
    
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    [dictionary setObject:@(MCCursorCreatorVersion) forKey:MCCursorDictionaryVersionKey];
    [dictionary setObject:@(MCCursorParserVersion) forKey:MCCursorDictionaryMinimumVersionKey];
    
    CGFloat version = 0.0;
    
    MMLog(BOLD "Enter metadata for cape:" RESET);
    NSString *author = MMGet(@"Author");
    NSString *identifier = MMGet(@"Identifier");
    NSString *name = MMGet(@"Cape Name");
    MMLog("Cape Version: ");
    scanf("%lf", &version);
    NSString *hidpi = MMGet(@"HiDPI? (y/n)");
    
    MMLog("");
    
    BOOL HiDPI = [hidpi isEqualToString:@"y"];
    
    [dictionary setObject:author forKey:MCCursorDictionaryAuthorKey];
    [dictionary setObject:identifier forKey:MCCursorDictionaryIdentifierKey];
    [dictionary setObject:name forKey:MCCursorDictionaryCapeNameKey];
    [dictionary setObject:@(version) forKey:MCCursorDictionaryCapeVersionKey];
    [dictionary setObject:@NO forKey:MCCursorDictionaryCloudKey];
    [dictionary setObject:@(HiDPI) forKey:MCCursorDictionaryHiDPIKey];
    
    NSMutableDictionary *cursors = [NSMutableDictionary dictionary];
    
    for (NSString *subpath in contents) {
        NSString *fullPath = [path stringByAppendingPathComponent:subpath];
        
        [manager fileExistsAtPath:fullPath isDirectory:&isDir];
        
        if (!isDir)
            continue;
        
        NSString *ident = subpath;
        NSMutableDictionary *data = [NSMutableDictionary dictionary];
        
        NSUInteger fC;
        CGFloat hotX, hotY, pW, pH, fD;
        printf(BOLD "Need metadata for %s." RESET, [ident cStringUsingEncoding:NSUTF8StringEncoding]);
        printf("X Hotspot: ");
        scanf("%lf", &hotX);
        printf("Y Hotspot: ");
        scanf("%lf", &hotY);
        printf("Points Wide: ");
        scanf("%lf", &pW);
        printf("Points High: ");
        scanf("%lf", &pH);
        printf("Frame Count: ");
        scanf("%lu", &fC);
        printf("Frame Duration: ");
        scanf("%lf", &fD);
        
        NSMutableArray *representations = [NSMutableArray array];
        NSArray *repNames = [manager contentsOfDirectoryAtPath:fullPath error:nil];
        for (NSString *rep in repNames) {
            NSString *repPath = [fullPath stringByAppendingPathComponent:rep];
            
            [manager fileExistsAtPath:repPath isDirectory:&isDir];
            if (isDir || [rep isEqualToString:@".DS_Store"])
                continue;
            
            NSBitmapImageRep *image = [NSBitmapImageRep imageRepWithData:[NSData dataWithContentsOfFile:repPath]];
            if (image) {
                NSData *pngData = [image.ensuredSRGBSpace TIFFRepresentationUsingCompression:NSTIFFCompressionLZW factor:1.0];
                [representations addObject:pngData];
            }
            
        }
        
        [data setObject:@(hotX) forKey:MCCursorDictionaryHotSpotXKey];
        [data setObject:@(hotY) forKey:MCCursorDictionaryHotSpotYKey];
        [data setObject:@(pW) forKey:MCCursorDictionaryPointsWideKey];
        [data setObject:@(pH) forKey:MCCursorDictionaryPointsHighKey];
        [data setObject:@(fC) forKey:MCCursorDictionaryFrameCountKey];
        [data setObject:@(fD) forKey:MCCursorDictionaryFrameDuratiomKey];
        
        [data setObject:representations forKey:MCCursorDictionaryRepresentationsKey];
        [cursors setObject:data forKey:identifier];
    }
    
    if (cursors.count == 0)
        return nil;
    
    [dictionary setObject:cursors forKey:MCCursorDictionaryCursorsKey];
    
    return dictionary;
}

// The value if it is a whole number in [min, max], otherwise -1. MightyMouse files are
// untrusted input, so every value from one is checked for its type and range.
static NSInteger mightyMouseInteger(id value, NSInteger min, NSInteger max) {
    if (![value isKindOfClass:[NSNumber class]])
        return -1;
    double number = [value doubleValue];
    if (number != floor(number) || number < min || number > max)
        return -1;
    return (NSInteger)number;
}

// The images of one MightyMouse cursor as TIFF data, or nil when its description is
// broken. The bitmap is read straight from the file's bytes, so the data has to cover
// every row the header claims; without this check a broken or hostile file made the engine
// read past the end of the buffer.
static NSData *mightyMouseImages(NSDictionary *data) {
    NSData *rawData = data[@"CursorData"];
    NSInteger wide   = mightyMouseInteger(data[@"PixelsWide"], 1, MCMaximumImagePixels);
    NSInteger high   = mightyMouseInteger(data[@"PixelsHigh"], 1, MCMaximumImagePixels);
    NSInteger frames = mightyMouseInteger(data[@"FrameCount"], 1, MCMaximumImagePixels);
    NSInteger bps    = mightyMouseInteger(data[@"BitsPerSample"], 1, 32);
    NSInteger spp    = mightyMouseInteger(data[@"SamplesPerPixel"], 1, 5);
    NSInteger bpp    = mightyMouseInteger(data[@"BitsPerPixel"], 1, 160);
    NSInteger bpr    = mightyMouseInteger(data[@"BytesPerRow"], 1, NSIntegerMax / 2);
    if (![rawData isKindOfClass:[NSData class]] || wide < 0 || high < 0 || frames < 0
        || bps < 0 || spp < 0 || bpp < 0 || bpr < 0)
        return nil;

    // All frames together within the image size limit, without overflowing on the way.
    NSInteger maximum = (NSInteger)MCMaximumImagePixels;
    if (high > maximum / wide || frames > maximum / (wide * high))
        return nil;
    NSInteger rows = high * frames;
    if (bpr < (wide * bpp + 7) / 8 || bpr > (NSInteger)rawData.length / rows)
        return nil;

    unsigned char *bytes = (unsigned char *)rawData.bytes;
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:&bytes
                                                                    pixelsWide:wide
                                                                    pixelsHigh:rows
                                                                 bitsPerSample:bps
                                                               samplesPerPixel:spp
                                                                      hasAlpha:YES
                                                                      isPlanar:NO
                                                                colorSpaceName:NSCalibratedRGBColorSpace
                                                                  bitmapFormat:NSBitmapFormatAlphaFirst | kCGBitmapByteOrder32Big
                                                                   bytesPerRow:bpr
                                                                  bitsPerPixel:bpp];
    // The rep refuses combinations it can't read (it returns nil then).
    NSData *tiff = [rep.ensuredSRGBSpace TIFFRepresentationUsingCompression:NSTIFFCompressionLZW factor:1.0];
    [rep release];
    return tiff;
}

NSDictionary *createCapeFromMightyMouse(NSDictionary *mightyMouse, NSDictionary *metadata) {
    if (![mightyMouse isKindOfClass:[NSDictionary class]])
        return nil;

    NSDictionary *cursors    = mightyMouse[@"Cursors"];
    NSDictionary *global     = [cursors isKindOfClass:[NSDictionary class]] ? cursors[@"Global"] : nil;
    NSDictionary *cursorData = [cursors isKindOfClass:[NSDictionary class]] ? cursors[@"Cursor Data"] : nil;
    NSDictionary *identifiers = [global isKindOfClass:[NSDictionary class]] ? global[@"Identifiers"] : nil;

    if (![identifiers isKindOfClass:[NSDictionary class]] || ![cursorData isKindOfClass:[NSDictionary class]]) {
        MMLog(BOLD RED "Mighty Mouse format either invalid or unrecognized." RESET);
        return nil;
    }

    NSMutableDictionary *convertedCursors = [NSMutableDictionary dictionary];

    for (NSString *key in identifiers) {
        if (![key isKindOfClass:[NSString class]])
            continue;
        MMLog("Converting cursor: %s", key.UTF8String);

        NSMutableDictionary *currentCursor = [NSMutableDictionary dictionary];

        NSDictionary *info = identifiers[key];
        NSString *customKey = [info isKindOfClass:[NSDictionary class]] ? info[@"Custom Key"] : nil;
        NSDictionary *data = [customKey isKindOfClass:[NSString class]] ? cursorData[customKey] : nil;
        if (![data isKindOfClass:[NSDictionary class]]) {
            MMLog(BOLD RED "Skipping cursor %s: it has no image data." RESET, key.UTF8String);
            continue;
        }

        NSNumber *fc    = data[@"FrameCount"];
        NSNumber *fd    = data[@"FrameDuration"];
        NSNumber *hotX  = data[@"HotspotX"];
        NSNumber *hotY  = data[@"HotspotY"];
        NSNumber *wide  = data[@"PixelsWide"];
        NSNumber *high  = data[@"PixelsHigh"];

        NSData *images = mightyMouseImages(data);
        if (!images || ![fd isKindOfClass:[NSNumber class]] || ![hotX isKindOfClass:[NSNumber class]]
            || ![hotY isKindOfClass:[NSNumber class]]) {
            MMLog(BOLD RED "Skipping cursor %s: its image data is malformed." RESET, key.UTF8String);
            continue;
        }

        currentCursor[MCCursorDictionaryRepresentationsKey] = @[ images ];
        currentCursor[MCCursorDictionaryPointsWideKey]      = wide;
        currentCursor[MCCursorDictionaryPointsHighKey]      = high;
        currentCursor[MCCursorDictionaryHotSpotXKey]        = hotX;
        currentCursor[MCCursorDictionaryHotSpotYKey]        = hotY;
        currentCursor[MCCursorDictionaryFrameCountKey]      = fc;
        currentCursor[MCCursorDictionaryFrameDuratiomKey]   = fd;
        
        convertedCursors[key] = currentCursor;
    }
    
    if (convertedCursors.count == 0) {
        MMLog(BOLD RED "No cursors to convert in file." RESET);
        return nil;
    }
    
    NSMutableDictionary *totalDict = [NSMutableDictionary dictionary];
    
    totalDict[MCCursorDictionaryCursorsKey]        = convertedCursors;
    totalDict[MCCursorDictionaryVersionKey]        = @(MCCursorCreatorVersion);
    totalDict[MCCursorDictionaryMinimumVersionKey] = @(MCCursorParserVersion);
    totalDict[MCCursorDictionaryHiDPIKey]          = @NO;
    totalDict[MCCursorDictionaryCloudKey]          = @NO;
    
    CGFloat version = 0.0;
    
    MMLog(BOLD "Enter metadata for cape:" RESET);
    NSString *author = metadata[@"author"] ?: MMGet(@"Author");
    NSString *identifier = metadata[@"identifier"] ?: MMGet(@"Identifier");
    NSString *name = metadata[@"name"] ?: MMGet(@"Cape Name");
    
    if (metadata[@"version"])
        version = [metadata[@"version"] doubleValue];
    else {
        MMLog("Cape Version: ");
        scanf("%lf", &version);
    }
    
    totalDict[MCCursorDictionaryAuthorKey]      = author;
    totalDict[MCCursorDictionaryCapeNameKey]    = name;
    totalDict[MCCursorDictionaryCapeVersionKey] = @(version);
    totalDict[MCCursorDictionaryIdentifierKey]  = identifier;
    
    return totalDict;
}

NSDictionary *processedCapeWithIdentifier(NSString *identifier) {
    NSMutableDictionary *dict = capeWithIdentifier(identifier).mutableCopy;
    if (!dict)
        return nil;
    
    NSDictionary *cursors = dict[MCCursorDictionaryRepresentationsKey];
    NSMutableArray *reps = [NSMutableArray array];
    
    for (id image in cursors) {
        CGImageRef im = (__bridge CGImageRef)image;
        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:im];
    
        reps[reps.count] = pngDataForImage(rep.ensuredSRGBSpace);
    }
    
    dict[MCCursorDictionaryRepresentationsKey] = reps;
    return dict;
}

BOOL dumpCursorsToFile(NSString *path, BOOL (^progress)(NSUInteger current, NSUInteger total)) {
    MMLog("Dumping cursors...");
        
    float originalScale;
    CGSGetCursorScale(CGSMainConnectionID(), &originalScale);
    
    CGSSetCursorScale(CGSMainConnectionID(), 16.0);
    CGSHideCursor(CGSMainConnectionID());

    NSInteger total = 9 + 45;
    NSInteger current = 0;

    NSMutableDictionary *cursors = [NSMutableDictionary dictionary];
    NSUInteger i = 0;
    NSString *key = nil;
    while ((key = defaultCursors[i]) != nil) {
        if (progress) {
            current = i;

            if (!progress(current, total)) {
                return NO;
            }
        }
        MMLog("Gathering data for %s", key.UTF8String);
        cursors[key] = processedCapeWithIdentifier(key);
        i++;
    }
    
    for (int x = 0; x < 45; x++) {
        if (progress) {
            current = i + x;

            if (!progress(current, total)) {
                return NO;
            }
        }
        NSString *key = [@"com.apple.cursor." stringByAppendingFormat:@"%d", x];
        CoreCursorSet(CGSMainConnectionID(), x);

        NSDictionary *cape = processedCapeWithIdentifier(key);
        if (!cape)
            continue;
        
        MMLog("Gathering data for %s", key.UTF8String);
        
        cursors[key] = cape;
    }

    if (progress) {
        progress(total, total);
    }

    NSMutableDictionary *cape = [NSMutableDictionary dictionary];
    cape[MCCursorDictionaryAuthorKey] = @"Apple, Inc.";
    cape[MCCursorDictionaryCapeNameKey] = @"Cursor Dump";
    cape[MCCursorDictionaryCapeVersionKey] = @1.0;
    cape[MCCursorDictionaryCloudKey] = @NO;
    cape[MCCursorDictionaryCursorsKey] = cursors;
    cape[MCCursorDictionaryHiDPIKey] = @YES;
    cape[MCCursorDictionaryIdentifierKey] = [NSString stringWithFormat:@"com.alexzielenski.mousecape.dump"];
    cape[MCCursorDictionaryVersionKey] = @(MCCursorCreatorVersion);
    cape[MCCursorDictionaryMinimumVersionKey] = @(MCCursorParserVersion);
    
    CGSSetCursorScale(CGSMainConnectionID(), originalScale);
    CGSShowCursor(CGSMainConnectionID());
    
    return [cape writeToFile:path atomically:NO];
}

BOOL dumpCursorsToFolder(NSString *path, BOOL (^progress)(NSUInteger current, NSUInteger total)) {
    [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    
    MMLog("Dumping cursors...");
    
    float originalScale;
    CGSGetCursorScale(CGSMainConnectionID(), &originalScale);
    
    CGSSetCursorScale(CGSMainConnectionID(), 16.0);
    CGSHideCursor(CGSMainConnectionID());

    NSInteger total = 9 + 45;
    NSInteger current = 0;

    NSUInteger i = 0;
    NSString *key = nil;
    while ((key = defaultCursors[i]) != nil) {
        current = i;
        if (progress) {
            if (!progress(current, total)) {
                return NO;
            }
        }
        MMLog("Gathering data for %s", key.UTF8String);
        NSDictionary *cape = processedCapeWithIdentifier(key);
        
        [MCPNGDataFromImageData([cape[MCCursorDictionaryRepresentationsKey] lastObject]) writeToFile:[[path stringByAppendingPathComponent:key] stringByAppendingPathExtension:@"png"] atomically: NO];
        i++;
    }
    
    for (int x = 0; x < 45; x++) {
        current = i + x;
        if (progress) {
            if (!progress(current, total)) {
                return NO;
            }
        }
        NSString *key = [@"com.apple.cursor." stringByAppendingFormat:@"%d", x];
        CoreCursorSet(CGSMainConnectionID(), x);
        
        NSDictionary *cape = processedCapeWithIdentifier(key);
        if (!cape)
            continue;
        
        MMLog("Gathering data for %s", key.UTF8String);
        
        [MCPNGDataFromImageData([cape[MCCursorDictionaryRepresentationsKey] lastObject]) writeToFile:[[path stringByAppendingPathComponent:key] stringByAppendingPathExtension:@"png"] atomically:NO];
    }
    
    if (progress) {
        progress(total, total);
    }

    CGSSetCursorScale(CGSMainConnectionID(), originalScale);
    CGSShowCursor(CGSMainConnectionID());

    return YES;
}

extern void exportCape(NSDictionary *cape, NSString *destination) {
    NSFileManager *manager = [NSFileManager defaultManager];
    [manager createDirectoryAtPath:destination withIntermediateDirectories:YES attributes:nil error:nil];

    NSDictionary *cursors = cape[MCCursorDictionaryCursorsKey];
    for (NSString *key in cursors) {
        // Keys become file names; one like "../x" would write outside the destination.
        if (!MCIsSafeIdentifier(key)) {
            MMLog(BOLD RED "Skipping cursor %s: not usable as a file name" RESET, key.description.UTF8String);
            continue;
        }
        // Capes store PNG or TIFF; the files are named .png, so they have to be PNG.
        NSArray *reps = cursors[key][MCCursorDictionaryRepresentationsKey];
        for (NSUInteger idx = 0; idx < reps.count; idx++) {
            NSData *png = MCPNGDataFromImageData(reps[idx]);
            if (!png) {
                MMLog(BOLD RED "Skipping image %lu of %s: not a readable image" RESET, (unsigned long)idx, key.UTF8String);
                continue;
            }
            [png writeToFile:[destination stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_%lu.png", key, (unsigned long)idx]] atomically:NO];
        }
    }
}
