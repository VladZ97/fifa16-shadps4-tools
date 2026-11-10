#import <Cocoa/Cocoa.h>
int main(void) { @autoreleasepool {
    CGDirectDisplayID d = CGMainDisplayID();
    CGDisplayModeRef cur = CGDisplayCopyDisplayMode(d);
    printf("current: %zux%zu px %zux%zu pt %.2f Hz id %d builtin %d\n", CGDisplayModeGetPixelWidth(cur), CGDisplayModeGetPixelHeight(cur), CGDisplayModeGetWidth(cur), CGDisplayModeGetHeight(cur), CGDisplayModeGetRefreshRate(cur), CGDisplayModeGetIODisplayModeID(cur), CGDisplayIsBuiltin(d));
    NSDictionary* opt = @{(__bridge NSString*)kCGDisplayShowDuplicateLowResolutionModes: @YES};
    CFArrayRef all = CGDisplayCopyAllDisplayModes(d, (__bridge CFDictionaryRef)opt);
    for (CFIndex i = 0; i < CFArrayGetCount(all); i++) { CGDisplayModeRef m = (CGDisplayModeRef)CFArrayGetValueAtIndex(all, i);
        if (CGDisplayModeGetPixelWidth(m) == CGDisplayModeGetPixelWidth(cur) && CGDisplayModeGetWidth(m) == CGDisplayModeGetWidth(cur))
            printf("  %zux%zu px %.2f Hz id %d usable %d\n", CGDisplayModeGetPixelWidth(m), CGDisplayModeGetPixelHeight(m), CGDisplayModeGetRefreshRate(m), CGDisplayModeGetIODisplayModeID(m), CGDisplayModeIsUsableForDesktopGUI(m)); }
    printf("screen max fps %ld min interval %.4f max interval %.4f\n", (long)[NSScreen mainScreen].maximumFramesPerSecond, [NSScreen mainScreen].minimumRefreshInterval, [NSScreen mainScreen].maximumRefreshInterval);
} return 0; }
