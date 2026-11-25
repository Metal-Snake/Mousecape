// Frame-limit probe: shows that the 24-frame limit for cursors sits in SkyLight's client
// wrapper, not in the window server (NOTES.md, "Frame limit").
//
// It registers a test cursor under a made-up name, for this process's connection only
// (global = 0, instantly = 0), so the cursor on screen never changes, first through the
// public wrapper and then through the wrapper's internal IPC call, and reads back what the
// window server stored. The internal call is found at offsets seen on macOS 15.8.3
// (24H241); on any other build the probe stops.
//
//   cc -fobjc-arc Scripts/frame-limit-probe.m -o /tmp/frame-limit-probe \
//      -F/System/Library/PrivateFrameworks -framework SkyLight \
//      -framework CoreGraphics -framework Foundation
//   /tmp/frame-limit-probe
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <dlfcn.h>
#import <string.h>

typedef int CGSConnectionID;
extern CGSConnectionID CGSMainConnectionID(void);
extern CGError CGSRegisterCursorWithImages(CGSConnectionID, const char *, bool, bool, CGSize, CGPoint,
                                           NSUInteger, CGFloat, CFArrayRef, int *);
extern CGError CGSCopyRegisteredCursorImages(CGSConnectionID, const char *, CGSize *, CGPoint *,
                                             NSUInteger *, CGFloat *, CFArrayRef *);
extern CGError CGSRemoveRegisteredCursor(CGSConnectionID, const char *, bool);

typedef mach_port_t (*ConnectionPortFunction)(CGSConnectionID);
typedef CGError (*RegisterIPCFunction)(mach_port_t, const char *, uint32_t global, uint32_t instantly,
                                       uint64_t frames, const int32_t *descriptors, uint32_t descriptorCount,
                                       const uint32_t *pixels, uint32_t pixelCount, int *seed,
                                       float width, float height, float hotX, float hotY, float duration);

static const int framePixels = 32;   // one frame, 32 x 32 pixels at 1x

// Target of the BL instruction at `site`, or NULL if it isn't a BL.
static void *branchTarget(const uint8_t *site) {
    uint32_t word; memcpy(&word, site, 4);
    if ((word & 0xfc000000) != 0x94000000) return NULL;
    int32_t displacement = word & 0x03ffffff;
    if (displacement & 0x02000000) displacement -= 0x04000000;
    return (void *)((uintptr_t)site + 4LL * displacement);
}

// A vertical sprite sheet; each frame a different shade, so frames can be told apart.
static CGImageRef makeSheet(int frames) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, framePixels, framePixels * frames, 8, 0, space,
                                                 kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    for (int index = 0; index < frames; index++) {
        CGContextSetRGBFillColor(context, (index % 256) / 255.0, 0.2, 0.8, 1);
        CGContextFillRect(context, CGRectMake(4, (frames - 1 - index) * framePixels + 4, 24, 24));
    }
    CGImageRef sheet = CGBitmapContextCreateImage(context);
    CGContextRelease(context); CGColorSpaceRelease(space);
    return sheet;
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

int main(void) {
    @autoreleasepool {
        CGSConnectionID connection = CGSMainConnectionID();
        const char *name = "org.mousecape.test.frame-limit";
        int counts[] = {24, 25, 48, 100};

        printf("Public wrapper CGSRegisterCursorWithImages:\n");
        for (int i = 0; i < 4; i++) {
            CGImageRef sheet = makeSheet(counts[i]);
            NSArray *images = @[(__bridge id)sheet];
            int seed = 0;
            CGError error = CGSRegisterCursorWithImages(connection, name, false, false,
                                                        CGSizeMake(framePixels, framePixels), CGPointMake(2, 2),
                                                        counts[i], 0.05, (__bridge CFArrayRef)images, &seed);
            printf("  %3d frames: error %d\n", counts[i], error);
            if (!error) readBack(connection, name, counts[i]);
            CGSRemoveRegisteredCursor(connection, name, false);
            CGImageRelease(sheet);
        }

        // Find the internal calls from the wrapper's code, at the offsets seen on 24H241.
        uint8_t *wrapper = dlsym(RTLD_DEFAULT, "SLSRegisterCursorWithImages");
        ConnectionPortFunction connectionPort = branchTarget(wrapper + 712);
        RegisterIPCFunction registerIPC = branchTarget(wrapper + 772);
        void *expectedPort = dlsym(RTLD_DEFAULT, "CGSGetConnectionPortById");
        if (!connectionPort || !registerIPC || (expectedPort && expectedPort != (void *)connectionPort)) {
            printf("Unexpected wrapper layout; stopping.\n"); return 1;
        }
        printf("Internal IPC call _CGSRegisterCursorImages at %p:\n", registerIPC);
        mach_port_t port = connectionPort(connection);
        for (int i = 0; i < 4; i++) {
            int frames = counts[i];
            int width = framePixels, height = framePixels * frames;
            uint32_t *pixels = calloc((size_t)width * height, 4);
            CGImageRef sheet = makeSheet(frames);
            CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
            CGContextRef context = CGBitmapContextCreate(pixels, width, height, 8, width * 4, space,
                                                         kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
            CGContextDrawImage(context, CGRectMake(0, 0, width, height), sheet);
            CGContextRelease(context); CGColorSpaceRelease(space); CGImageRelease(sheet);
            int32_t descriptors[4] = {width, height, 0, width * height};
            char paddedName[128] = {0}; strlcpy(paddedName, name, sizeof paddedName);
            int seed = 0;
            CGError error = registerIPC(port, paddedName, 0, 0, frames, descriptors, 4, pixels,
                                        (uint32_t)(width * height), &seed,
                                        framePixels, framePixels, 2, 2, 0.05f);
            printf("  %3d frames: error %d\n", frames, error);
            if (!error) readBack(connection, name, frames);
            CGSRemoveRegisteredCursor(connection, name, false);
            free(pixels);
        }
    }
    return 0;
}
