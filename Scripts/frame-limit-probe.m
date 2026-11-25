// Frame-limit probe: where the 24-frame limit for cursors sits, and whether the window
// server plays longer animations (NOTES.md, "Frame limit").
//
// Without arguments it registers a test cursor under a made-up name, for this process's
// connection only (global = 0, instantly = 0), so the cursor on screen never changes:
// first through the public wrapper, then through the wrapper's internal IPC call. It reads
// back what the window server stored each time.
//
// With --play [frames] (default 48) it registers an arrow with that many frames globally,
// under the names the engine uses for the arrow, through the internal call. Each frame
// shows its number, 0.25 s per frame, so you can watch whether all of them play. This
// changes the arrow on screen until the next apply or reset, e.g.
// `mousecloak --apply <cape>` or `mousecloak --reset`.
//
// The internal call is found at offsets seen on macOS 15.8.3 (24H241); on any other
// build the probe stops.
//
//   cc -fobjc-arc Scripts/frame-limit-probe.m -o /tmp/frame-limit-probe \
//      -F/System/Library/PrivateFrameworks -framework SkyLight \
//      -framework CoreGraphics -framework AppKit
//   /tmp/frame-limit-probe [--play [frames]]

#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <dlfcn.h>
#import <string.h>
#import <sys/sysctl.h>

typedef int CGSConnectionID;
extern CGSConnectionID CGSMainConnectionID(void);
extern CGError CGSRegisterCursorWithImages(CGSConnectionID, const char *, bool, bool, CGSize, CGPoint,
                                           NSUInteger, CGFloat, CFArrayRef, int *);
extern CGError CGSCopyRegisteredCursorImages(CGSConnectionID, const char *, CGSize *, CGPoint *,
                                             NSUInteger *, CGFloat *, CFArrayRef *);
extern CGError CGSRemoveRegisteredCursor(CGSConnectionID, const char *, bool);
extern CGError CGSGetRegisteredCursorDataSize(CGSConnectionID, const char *, size_t *);

typedef mach_port_t (*ConnectionPortFunction)(CGSConnectionID);
// _CGSRegisterCursorImages as SLSRegisterCursorWithImages calls it on 24H241. The
// descriptors are four numbers per image: width and height in pixels, the offset of its
// pixels in `pixels`, and their count. Pixels are premultiplied BGRA (32-bit little endian).
typedef CGError (*RegisterIPCFunction)(mach_port_t, const char *, uint32_t global, uint32_t instantly,
                                       uint64_t frames, const int32_t *descriptors, uint32_t descriptorCount,
                                       const uint32_t *pixels, uint32_t pixelCount, int *seed,
                                       float width, float height, float hotX, float hotY, float duration);

static const int pointSize = 32;   // one frame, 32 x 32 points

static ConnectionPortFunction connectionPort;
static RegisterIPCFunction registerIPC;

// Target of the BL instruction at `site`, or NULL if it isn't a BL.
static void *branchTarget(const uint8_t *site) {
    uint32_t word; memcpy(&word, site, 4);
    if ((word & 0xfc000000) != 0x94000000) return NULL;
    int32_t displacement = word & 0x03ffffff;
    if (displacement & 0x02000000) displacement -= 0x04000000;
    return (void *)((uintptr_t)site + 4LL * displacement);
}

// Finds the internal calls from the wrapper's code, at the offsets seen on 24H241.
static BOOL findInternalCalls(void) {
    char build[32] = {0}; size_t length = sizeof build;
    sysctlbyname("kern.osversion", build, &length, NULL, 0);
    if (strcmp(build, "24H241") != 0) { printf("Build %s, not 24H241; stopping.\n", build); return NO; }
    uint8_t *wrapper = dlsym(RTLD_DEFAULT, "SLSRegisterCursorWithImages");
    if (!wrapper) return NO;
    connectionPort = branchTarget(wrapper + 712);
    registerIPC = branchTarget(wrapper + 772);
    void *expectedPort = dlsym(RTLD_DEFAULT, "CGSGetConnectionPortById");
    if (!connectionPort || !registerIPC || (expectedPort && expectedPort != (void *)connectionPort)) {
        printf("Unexpected wrapper layout; stopping.\n"); return NO;
    }
    return YES;
}

// A vertical sprite sheet at the given pixel scale, frame 0 at the top. With `numbered`,
// each frame is a white arrow with its number (1, 2, …) in a black box beside it;
// otherwise each frame is a square in a different shade.
static CGImageRef makeSheet(int frames, int scale, BOOL numbered) {
    int side = pointSize * scale;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, side, side * frames, 8, 0, space,
                                                 kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGContextScaleCTM(context, scale, scale);
    NSGraphicsContext *graphics = [NSGraphicsContext graphicsContextWithCGContext:context flipped:NO];
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = graphics;
    for (int index = 0; index < frames; index++) {
        CGFloat bottom = (frames - 1 - index) * pointSize;   // CG's origin is at the bottom
        if (!numbered) {
            CGContextSetRGBFillColor(context, (index % 256) / 255.0, 0.2, 0.8, 1);
            CGContextFillRect(context, CGRectMake(4, bottom + 4, 24, 24));
            continue;
        }
        // The arrow: tip at the top left (the hot spot), 12 points tall.
        CGFloat top = bottom + pointSize;
        CGContextBeginPath(context);
        CGContextMoveToPoint(context, 1, top - 1);
        CGContextAddLineToPoint(context, 1, top - 13);
        CGContextAddLineToPoint(context, 9, top - 9);
        CGContextClosePath(context);
        CGContextSetRGBFillColor(context, 1, 1, 1, 1);
        CGContextSetRGBStrokeColor(context, 0, 0, 0, 1);
        CGContextSetLineWidth(context, 1);
        CGContextDrawPath(context, kCGPathFillStroke);
        // The number, in a box below and right of the tip.
        CGRect box = CGRectMake(6, bottom + 1, 25, 16);
        CGContextSetRGBFillColor(context, 0, 0, 0, 0.85);
        CGContextFillRect(context, box);
        NSString *number = [NSString stringWithFormat:@"%d", index + 1];
        NSDictionary *attributes = @{NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightBold],
                                     NSForegroundColorAttributeName: NSColor.yellowColor};
        NSSize textSize = [number sizeWithAttributes:attributes];
        [number drawAtPoint:NSMakePoint(CGRectGetMidX(box) - textSize.width / 2,
                                        CGRectGetMidY(box) - textSize.height / 2)
             withAttributes:attributes];
    }
    [NSGraphicsContext restoreGraphicsState];
    CGImageRef sheet = CGBitmapContextCreateImage(context);
    CGContextRelease(context); CGColorSpaceRelease(space);
    return sheet;
}

// Registers through the internal IPC call: what SLSRegisterCursorWithImages does after its
// checks. `sheets` holds one sprite sheet per scale.
static CGError registerDirectly(CGSConnectionID connection, const char *name, BOOL global,
                                int frames, NSArray *sheets, CGPoint hotSpot, float duration) {
    int32_t descriptors[64 * 4] = {0};
    size_t totalPixels = 0;
    for (NSUInteger i = 0; i < sheets.count; i++) {
        CGImageRef sheet = (__bridge CGImageRef)sheets[i];
        size_t width = CGImageGetWidth(sheet), height = CGImageGetHeight(sheet);
        descriptors[i * 4] = (int32_t)width;
        descriptors[i * 4 + 1] = (int32_t)height;
        descriptors[i * 4 + 2] = (int32_t)totalPixels;
        descriptors[i * 4 + 3] = (int32_t)(width * height);
        totalPixels += width * height;
    }
    uint32_t *pixels = calloc(totalPixels, 4);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    for (NSUInteger i = 0; i < sheets.count; i++) {
        int32_t *descriptor = descriptors + i * 4;
        CGContextRef context = CGBitmapContextCreate(pixels + descriptor[2], descriptor[0], descriptor[1], 8,
                                                     descriptor[0] * 4, space,
                                                     kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
        CGContextSetBlendMode(context, kCGBlendModeCopy);
        CGContextDrawImage(context, CGRectMake(0, 0, descriptor[0], descriptor[1]), (__bridge CGImageRef)sheets[i]);
        CGContextRelease(context);
    }
    CGColorSpaceRelease(space);
    char paddedName[128] = {0}; strlcpy(paddedName, name, sizeof paddedName);
    int seed = 0;
    CGError error = registerIPC(connectionPort(connection), paddedName, global, global, frames,
                                descriptors, (uint32_t)sheets.count * 4, pixels, (uint32_t)totalPixels, &seed,
                                pointSize, pointSize, hotSpot.x, hotSpot.y, duration);
    free(pixels);
    return error;
}

static void readBack(CGSConnectionID connection, const char *name, int expectedFrames) {
    CGSize size; CGPoint hotSpot; NSUInteger frames = 0; CGFloat duration = 0; CFArrayRef images = NULL;
    CGError error = CGSCopyRegisteredCursorImages(connection, name, &size, &hotSpot, &frames, &duration, &images);
    if (error) { printf("    readback: error %d\n", error); return; }
    CGImageRef first = images && CFArrayGetCount(images) ? (CGImageRef)CFArrayGetValueAtIndex(images, 0) : NULL;
    printf("    readback: frames %lu (expected %d), duration %.4f, size %.0fx%.0f, image %zux%zu\n",
           (unsigned long)frames, expectedFrames, duration, size.width, size.height,
           first ? CGImageGetWidth(first) : 0, first ? CGImageGetHeight(first) : 0);
    if (images) CFRelease(images);
}

// Compares the public wrapper with the internal call, for this connection only.
static int compareCalls(CGSConnectionID connection) {
    const char *name = "org.mousecape.test.frame-limit";
    int counts[] = {24, 25, 48, 100};

    printf("Public wrapper CGSRegisterCursorWithImages:\n");
    for (int i = 0; i < 4; i++) {
        CGImageRef sheet = makeSheet(counts[i], 1, NO);
        int seed = 0;
        CGError error = CGSRegisterCursorWithImages(connection, name, false, false,
                                                    CGSizeMake(pointSize, pointSize), CGPointMake(2, 2),
                                                    counts[i], 0.05, (__bridge CFArrayRef)@[(__bridge id)sheet], &seed);
        printf("  %3d frames: error %d\n", counts[i], error);
        if (!error) readBack(connection, name, counts[i]);
        CGSRemoveRegisteredCursor(connection, name, false);
        CGImageRelease(sheet);
    }

    printf("Internal IPC call _CGSRegisterCursorImages at %p:\n", registerIPC);
    for (int i = 0; i < 4; i++) {
        CGImageRef sheet = makeSheet(counts[i], 1, NO);
        CGError error = registerDirectly(connection, name, NO, counts[i], @[(__bridge id)sheet],
                                         CGPointMake(2, 2), 0.05f);
        printf("  %3d frames: error %d\n", counts[i], error);
        if (!error) readBack(connection, name, counts[i]);
        CGSRemoveRegisteredCursor(connection, name, false);
        CGImageRelease(sheet);
    }
    return 0;
}

// Registers a numbered arrow globally, under the names the engine uses for the arrow.
static int play(CGSConnectionID connection, int frames) {
    CGImageRef sheet1x = makeSheet(frames, 1, YES), sheet2x = makeSheet(frames, 2, YES);
    NSArray *sheets = @[(__bridge id)sheet1x, (__bridge id)sheet2x];
    // ArrowS only if it is registered already: macOS uses it then instead of Arrow.
    NSMutableArray *names = [@[@"com.apple.coregraphics.Arrow", @"com.apple.cursor.0"] mutableCopy];
    size_t dataSize = 0;   // the engine's way to ask whether a cursor is registered
    if (!CGSGetRegisteredCursorDataSize(connection, "com.apple.coregraphics.ArrowS", &dataSize) && dataSize > 0)
        [names addObject:@"com.apple.coregraphics.ArrowS"];
    int failures = 0;
    for (NSString *name in names) {
        CGError error = registerDirectly(connection, name.UTF8String, YES, frames, sheets, CGPointMake(1, 1), 0.25f);
        printf("%s: %d frames, error %d\n", name.UTF8String, frames, error);
        if (error) failures++; else readBack(connection, name.UTF8String, frames);
    }
    CGImageRelease(sheet1x); CGImageRelease(sheet2x);
    printf("Move the pointer: the arrow should count 1 to %d, 0.25 s each (%.0f s a round).\n"
           "Restore with `mousecloak --apply <cape>` or `mousecloak --reset`.\n", frames, frames * 0.25);
    return failures ? 1 : 0;
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        if (!findInternalCalls()) return 1;
        CGSConnectionID connection = CGSMainConnectionID();
        if (argc > 1 && strcmp(argv[1], "--play") == 0) {
            int frames = argc > 2 ? atoi(argv[2]) : 48;
            if (frames < 1 || frames > 512) { printf("Frames must be 1 to 512.\n"); return 1; }
            return play(connection, frames);
        }
        return compareCalls(connection);
    }
}
