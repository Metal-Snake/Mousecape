//
//  longanim.m
//  Mousecape
//
//  Animations with more than MCMaxFrameCount frames. CGSRegisterCursorWithImages (in
//  SkyLight: SLSRegisterCursorWithImages, from macOS 26 on SLSRegisterCursorWithImages2)
//  refuses them before anything reaches the window server, which itself registers and
//  plays them (measured on macOS 15.8.3 and 27.2.1, NOTES.md "Frame limit"). After its
//  checks the wrapper turns the images into one pixel buffer and calls the unexported
//  _CGSRegisterCursorImages, which sends them to the window server. This file finds that
//  call among the wrapper's calls, by the name dladdr gives it, checks it with a test
//  registration, and calls it the way the wrapper does. Idea from CX330-YCH's fork of
//  Mousecape-swiftUI, which finds the call by code digests per macOS build instead.
//
//  Anything unexpected turns long animations off for the process, and apply reduces them
//  to MCMaxFrameCount frames as before.
//

#import "longanim.h"
#import <dlfcn.h>
#import <libunwind.h>
#import <string.h>

typedef mach_port_t (*MCConnectionPortFunction)(CGSConnectionID);
// _CGSRegisterCursorImages as the wrapper calls it on macOS 15.8.3 and 27.2.1. The
// descriptors hold four numbers per image: width and height in pixels, the offset of its
// pixels in `pixels`, and their count. The pixels are premultiplied BGRA, 32 bits little
// endian. The name is a 128-byte buffer.
typedef CGError (*MCRegisterImagesFunction)(mach_port_t port, const char *name, uint32_t global, uint32_t instantly,
                                            uint64_t frameCount, const int32_t *descriptors, uint32_t descriptorCount,
                                            const uint32_t *pixels, uint32_t pixelCount, int *seed,
                                            float width, float height, float hotSpotX, float hotSpotY,
                                            float frameDuration);

static MCConnectionPortFunction connectionPort = NULL;
static MCRegisterImagesFunction registerImages = NULL;

// The wrapper takes at most this many images (one per scale), as does this file.
enum { maximumImages = 64 };

// The target of the BL instruction at `site`, or NULL if it isn't a BL.
static uint8_t *branchTarget(const uint8_t *site) {
    uint32_t word;
    memcpy(&word, site, sizeof word);
    if ((word & 0xfc000000) != 0x94000000)
        return NULL;
    int32_t displacement = word & 0x03ffffff;
    if (displacement & 0x02000000)
        displacement -= 0x04000000;   // sign-extend the 26-bit word offset
    return (uint8_t *)site + 4LL * displacement;
}

// Whether the code at `address` is a stub that jumps into another library: an indirect
// branch (BR or BRAA) within its first four instructions.
static BOOL isStub(const uint8_t *address) {
    for (int index = 0; index < 4; index++) {
        uint32_t word;
        memcpy(&word, address + 4 * index, sizeof word);
        if ((word & 0xfffffc1f) == 0xd61f0000 || (word & 0xfffffc00) == 0xd71f0800)
            return YES;
    }
    return NO;
}

// The end of the function that starts at `start`, from its unwind information. Compact
// unwind entries cover runs of functions that unwind alike, so an entry may start before
// `start` and end after the function; capped at 4 KB. A range too long only adds calls to
// look at, and finding the wanted ones twice stops the search.
static BOOL functionEnd(const uint8_t *start, const uint8_t **end) {
    unw_context_t context;
    unw_cursor_t cursor;
    unw_proc_info_t info;
    if (unw_getcontext(&context) || unw_init_local(&cursor, &context) ||
        unw_set_reg(&cursor, UNW_REG_IP, (unw_word_t)start + 4) || unw_get_proc_info(&cursor, &info) ||
        info.start_ip > (unw_word_t)start || info.end_ip <= (unw_word_t)start + 4)
        return NO;
    *end = (const uint8_t *)MIN((uintptr_t)info.end_ip, (uintptr_t)start + 4096);
    return YES;
}

// Looks for exactly one call to the port lookup and one to _CGSRegisterCursorImages in
// the wrapper.
static BOOL findInternalCalls(void) {
    const char *wrapperName = "SLSRegisterCursorWithImages2";
    const uint8_t *wrapper = dlsym(RTLD_DEFAULT, wrapperName);
    if (!wrapper) {
        wrapperName = "SLSRegisterCursorWithImages";
        wrapper = dlsym(RTLD_DEFAULT, wrapperName);
    }
    const uint8_t *end = NULL;
    Dl_info wrapperImage;
    if (!wrapper || !functionEnd(wrapper, &end) || !dladdr(wrapper, &wrapperImage)) {
        MMLog("Long animations: %s not found", wrapperName);
        return NO;
    }
    NSUInteger portCalls = 0, registerCalls = 0;
    for (const uint8_t *site = wrapper; site < end; site += 4) {
        uint8_t *target = branchTarget(site);
        if (!target || isStub(target))
            continue;
        Dl_info targetInfo;
        if (!dladdr(target, &targetInfo) || targetInfo.dli_fbase != wrapperImage.dli_fbase ||
            targetInfo.dli_saddr != target || !targetInfo.dli_sname)
            continue;
        if (!strcmp(targetInfo.dli_sname, "CGSGetConnectionPortById") ||
            !strcmp(targetInfo.dli_sname, "SLSGetConnectionPortById")) {
            portCalls++;
            connectionPort = (MCConnectionPortFunction)target;
        } else if (!strcmp(targetInfo.dli_sname, "_CGSRegisterCursorImages")) {
            registerCalls++;
            registerImages = (MCRegisterImagesFunction)target;
        }
    }
    if (portCalls != 1 || registerCalls != 1) {
        MMLog("Long animations: %s calls the port lookup %lu times and _CGSRegisterCursorImages %lu times",
              wrapperName, (unsigned long)portCalls, (unsigned long)registerCalls);
        connectionPort = NULL;
        registerImages = NULL;
        return NO;
    }
    return YES;
}

// Registers through the internal call. `global` registers for all processes and shows the
// cursor at once, as the engine does everywhere; otherwise only for this connection.
static CGError registerDirectly(CGSConnectionID cid, const char *name, BOOL global, CGSize size, CGPoint hotSpot,
                                NSUInteger frameCount, CGFloat frameDuration, NSArray *images) {
    // The wrapper's own checks, except the frame limit.
    if (!name || strlen(name) >= 128 || frameCount < 1 || images.count < 1 || images.count > maximumImages ||
        !(size.width > 0) || !(size.height > 0) || !(frameDuration >= 0) ||
        hotSpot.x < 0 || hotSpot.x >= size.width || hotSpot.y < 0 || hotSpot.y >= size.height)
        return kCGErrorIllegalArgument;

    int32_t descriptors[maximumImages * 4];
    NSUInteger totalPixels = 0;
    for (NSUInteger index = 0; index < images.count; index++) {
        CGImageRef image = (CGImageRef)images[index];
        size_t width = CGImageGetWidth(image), height = CGImageGetHeight(image);
        if (width == 0 || height == 0 || height % frameCount != 0 ||
            totalPixels + width * height > MCMaxLongAnimationPixels)
            return kCGErrorIllegalArgument;
        descriptors[index * 4] = (int32_t)width;
        descriptors[index * 4 + 1] = (int32_t)height;
        descriptors[index * 4 + 2] = (int32_t)totalPixels;
        descriptors[index * 4 + 3] = (int32_t)(width * height);
        totalPixels += width * height;
    }

    uint32_t *pixels = calloc(totalPixels, sizeof *pixels);
    if (!pixels)
        return kCGErrorCannotComplete;
    // Drawn as the wrapper draws them: device RGB, BGRA, copied rather than blended.
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    BOOL drawn = YES;
    for (NSUInteger index = 0; index < images.count && drawn; index++) {
        int32_t *descriptor = descriptors + index * 4;
        CGContextRef context = CGBitmapContextCreate(pixels + descriptor[2], descriptor[0], descriptor[1], 8,
                                                     descriptor[0] * sizeof *pixels, space,
                                                     kCGBitmapByteOrder32Little | (CGBitmapInfo)kCGImageAlphaPremultipliedFirst);
        if (!context) {
            drawn = NO;
            break;
        }
        CGContextSetBlendMode(context, kCGBlendModeCopy);
        CGContextDrawImage(context, CGRectMake(0, 0, descriptor[0], descriptor[1]), (CGImageRef)images[index]);
        CGContextRelease(context);
    }
    CGColorSpaceRelease(space);
    if (!drawn) {
        free(pixels);
        return kCGErrorCannotComplete;
    }

    char paddedName[128] = {0};
    strlcpy(paddedName, name, sizeof paddedName);
    mach_port_t port = connectionPort(cid);
    if (port == MACH_PORT_NULL) {
        free(pixels);
        return kCGErrorInvalidConnection;
    }
    int seed = 0;
    CGError error = registerImages(port, paddedName, global, global, frameCount,
                                   descriptors, (uint32_t)(images.count * 4), pixels, (uint32_t)totalPixels, &seed,
                                   size.width, size.height, hotSpot.x, hotSpot.y, frameDuration);
    free(pixels);
    return error;
}

// Registers MCMaxFrameCount + 1 frames for this connection only, under a made-up name, and
// reads them back: proof that the call found is the right one, called the right way. The
// cursor on screen doesn't change.
static BOOL testRegistration(void) {
    const NSUInteger frames = MCMaxFrameCount + 1, side = 4;
    const char *name = "local.mousecape.frame-limit-check";
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(NULL, side, side * frames, 8, 0, space,
                                                 (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!context)
        return NO;
    CGContextSetRGBFillColor(context, 0, 0, 0, 1);
    CGContextFillRect(context, CGRectMake(0, 0, side, side * frames));
    CGImageRef sheet = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    if (!sheet)
        return NO;

    CGSConnectionID cid = CGSMainConnectionID();
    CGError error = registerDirectly(cid, name, NO, CGSizeMake(side, side), CGPointZero, frames, 0.1,
                                     @[(id)sheet]);
    CGImageRelease(sheet);
    BOOL matches = NO;
    if (error == kCGErrorSuccess) {
        CGSize size = CGSizeZero;
        CGPoint hotSpot = CGPointZero;
        NSUInteger frameCount = 0;
        CGFloat duration = 0;
        CFArrayRef images = NULL;
        if (CGSCopyRegisteredCursorImages(cid, (char *)name, &size, &hotSpot, &frameCount, &duration, &images) ==
            kCGErrorSuccess && images) {
            CGImageRef first = CFArrayGetCount(images) > 0 ? (CGImageRef)CFArrayGetValueAtIndex(images, 0) : NULL;
            matches = frameCount == frames && first && CGImageGetHeight(first) == side * frames;
        }
        if (images)
            CFRelease(images);
        CGSRemoveRegisteredCursor(cid, (char *)name, false);
    }
    MMLog("Long animations: test registration %s (error %d)", matches ? "read back right" : "failed", error);
    return matches;
}

BOOL MCLongAnimationsAvailable(void) {
    static BOOL available = NO;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        const char *off = getenv("MOUSECAPE_SHORT_ANIMATIONS");
        if (off && !strcmp(off, "1")) {
            MMLog("Long animations: turned off by MOUSECAPE_SHORT_ANIMATIONS");
            return;
        }
        available = findInternalCalls() && testRegistration();
    });
    return available;
}

NSUInteger MCFrameLimit(NSUInteger pixelsPerFrame, BOOL longAnimations) {
    if (!longAnimations)
        return MCMaxFrameCount;
    NSUInteger fitting = pixelsPerFrame > 0 ? MCMaxLongAnimationPixels / pixelsPerFrame : MCMaxLongFrameCount;
    return MAX((NSUInteger)MCMaxFrameCount, MIN((NSUInteger)MCMaxLongFrameCount, fitting));
}

NSUInteger MCPixelsPerFrame(NSArray *images, NSUInteger frameCount) {
    if (frameCount == 0)
        return 0;
    NSUInteger pixels = 0;
    for (id image in images)
        pixels += CGImageGetWidth((CGImageRef)image) * (CGImageGetHeight((CGImageRef)image) / frameCount);
    return pixels;
}

CGError MCRegisterLongCursor(CGSConnectionID cid, const char *name, CGSize size, CGPoint hotSpot,
                             NSUInteger frameCount, CGFloat frameDuration, NSArray *images) {
    if (!MCLongAnimationsAvailable())
        return kCGErrorNotImplemented;
    return registerDirectly(cid, name, YES, size, hotSpot, frameCount, frameDuration, images);
}
