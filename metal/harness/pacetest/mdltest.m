// CAMetalDisplayLink probe: a 60 Hz producer publishes frames, the display link callback shows the newest one.
// usage: mdltest <seconds> <full 0|1> <latency frames> <lock 0|1> [late_every late_ms]
#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import <pthread.h>
#import <stdatomic.h>
#define MAXF 4096
static double g_pub[MAXF], g_shown[MAXF], g_cb[MAXF], g_tgt[MAXF];
static pthread_mutex_t g_mu = PTHREAD_MUTEX_INITIALIZER;
static int g_latest = -1, g_last_taken = -1, g_dups, g_drops, g_cbs;
static double g_slew, g_margin = 0.003; static int g_lock;
static double g_ring[8]; static int g_rn, g_rat;
static double g_cbt[MAXF * 2]; static double g_cb_target[MAXF * 2];
static id<MTLDevice> g_dev; static id<MTLCommandQueue> g_q;
static double Now(void) { return CACurrentMediaTime(); }
@interface Link : NSObject <CAMetalDisplayLinkDelegate>
@end
@implementation Link
- (void)metalDisplayLink:(CAMetalDisplayLink*)link needsUpdate:(CAMetalDisplayLinkUpdate*)update {
    double now = Now();
    pthread_mutex_lock(&g_mu);
    int idx = g_latest; int fresh = idx != g_last_taken && idx >= 0;
    if (g_cbs < MAXF * 2) { g_cbt[g_cbs] = now; g_cb_target[g_cbs] = update.targetPresentationTimestamp; }
    g_cbs++;
    if (fresh) {
        if (g_last_taken >= 0 && idx - g_last_taken > 1) g_drops += idx - g_last_taken - 1;
        g_last_taken = idx; g_cb[idx] = now; g_tgt[idx] = update.targetPresentationTimestamp;
        double slack = now - g_pub[idx];
        g_ring[g_rat] = slack; g_rat = (g_rat + 1) % 8; if (g_rn < 8) g_rn++;
        if (g_lock && g_rn == 8) {
            double m = g_ring[0]; for (int i = 1; i < 8; i++) if (g_ring[i] < m) m = g_ring[i];
            double e = m - g_margin; double s = e * 0.08;   // too much slack: produce later
            if (s > 0.00025) s = 0.00025; if (s < -0.00025) s = -0.00025;
            g_slew = fabs(e) > 0.0004 ? s : 0;
        }
    } else { g_dups++; if (g_lock) { g_slew = -0.00025; g_rn = 0; } }
    pthread_mutex_unlock(&g_mu);
    id<CAMetalDrawable> d = update.drawable;
    MTLRenderPassDescriptor* rp = [MTLRenderPassDescriptor renderPassDescriptor];
    rp.colorAttachments[0].texture = d.texture; rp.colorAttachments[0].loadAction = MTLLoadActionClear;
    rp.colorAttachments[0].storeAction = MTLStoreActionStore;
    double c = (idx & 1) ? 0.2 : 0.25; rp.colorAttachments[0].clearColor = MTLClearColorMake(c, c, c, 1);
    id<MTLCommandBuffer> cmd = [g_q commandBuffer];
    [[cmd renderCommandEncoderWithDescriptor:rp] endEncoding];
    if (fresh) [d addPresentedHandler:^(id<MTLDrawable> dd) { if (idx < MAXF) g_shown[idx] = dd.presentedTime; }];
    [cmd presentDrawable:d];
    [cmd commit];
}
@end
int main(int argc, const char** argv) {
    @autoreleasepool {
        double secs = argc > 1 ? atof(argv[1]) : 6; int full = argc > 2 ? atoi(argv[2]) : 0;
        float lat = argc > 3 ? atof(argv[3]) : 1; g_lock = argc > 4 ? atoi(argv[4]) : 1;
        int late_every = argc > 5 ? atoi(argv[5]) : 0; double late_ms = argc > 6 ? atof(argv[6]) : 0;
        if (getenv("MARGIN")) g_margin = atof(getenv("MARGIN")) * 1e-3;
        [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        NSRect r = full ? [NSScreen mainScreen].frame : NSMakeRect(200, 200, 1280, 720);
        NSWindow* w = [[NSWindow alloc] initWithContentRect:r styleMask:full ? NSWindowStyleMaskBorderless : (NSWindowStyleMaskTitled | NSWindowStyleMaskResizable) backing:NSBackingStoreBuffered defer:NO];
        if (full) [w setLevel:NSMainMenuWindowLevel + 1];
        g_dev = MTLCreateSystemDefaultDevice(); g_q = [g_dev newCommandQueue];
        NSView* v = [[NSView alloc] initWithFrame:r]; CAMetalLayer* l = [CAMetalLayer layer];
        l.device = g_dev; l.pixelFormat = MTLPixelFormatBGRA8Unorm; l.framebufferOnly = YES;
        l.drawableSize = CGSizeMake(r.size.width * 2, r.size.height * 2);
        v.wantsLayer = YES; v.layer = l; [w setContentView:v]; [w makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
        Link* del = [Link new];
        CAMetalDisplayLink* link = [[CAMetalDisplayLink alloc] initWithMetalLayer:l];
        link.delegate = del; link.preferredFrameRateRange = CAFrameRateRangeMake(60, 60, 60); link.preferredFrameLatency = lat;
        NSThread* th = [[NSThread alloc] initWithBlock:^{
            [link addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
            [[NSRunLoop currentRunLoop] run];
        }];
        th.qualityOfService = NSQualityOfServiceUserInteractive; [th start];
        MTLTextureDescriptor* td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:1920 height:1080 mipmapped:NO];
        td.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead; id<MTLTexture> off = [g_dev newTextureWithDescriptor:td];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
            const double P = 1.0 / 60.0 * 1.0007; double next = Now() + 0.5; int n = (int)(secs * 60);
            for (int i = 0; i < n && i < MAXF; i++) {
                double t = Now(); if (next > t) { struct timespec ts = {0, (long)((next - t) * 1e9)}; nanosleep(&ts, 0); }
                pthread_mutex_lock(&g_mu); next += P + g_slew; pthread_mutex_unlock(&g_mu);
                if (late_every && i % late_every == late_every - 1) usleep((useconds_t)(late_ms * 1000));
                MTLRenderPassDescriptor* rp = [MTLRenderPassDescriptor renderPassDescriptor];
                rp.colorAttachments[0].texture = off; rp.colorAttachments[0].loadAction = MTLLoadActionClear; rp.colorAttachments[0].storeAction = MTLStoreActionStore;
                id<MTLCommandBuffer> cmd = [g_q commandBuffer]; [[cmd renderCommandEncoderWithDescriptor:rp] endEncoding];
                [cmd addCompletedHandler:^(id<MTLCommandBuffer> cb) { pthread_mutex_lock(&g_mu); g_pub[i] = Now(); g_latest = i; pthread_mutex_unlock(&g_mu); }];
                [cmd commit];
            }
            usleep(300000);
            int hist[16] = {0}; double sum = 0, mn = 1e9, mx = 0, tsum = 0, csum = 0; int cnt = 0; double prev = 0;
            for (int i = 60; i < n; i++) { if (g_shown[i] <= 0) continue; double wms = (g_shown[i] - g_pub[i]) * 1e3; sum += wms; if (wms < mn) mn = wms; if (wms > mx) mx = wms;
                tsum += (g_shown[i] - g_tgt[i]) * 1e3; csum += (g_cb[i] - g_pub[i]) * 1e3; cnt++;
                if (prev > 0) { int b = (int)((g_shown[i] - prev) * 1e3 / 4.1667 + 0.5); if (b > 15) b = 15; hist[b]++; } prev = g_shown[i]; }
            printf("mdl full=%d latency=%.0f lock=%d late=%d/%.0f: frames %d shown %d dups %d drops %d callbacks %d | published->shown mean %.1f min %.1f max %.1f | published->callback %.1f | shown-target %.1f | intervals:", full, lat, g_lock, late_every, late_ms, n, cnt, g_dups, g_drops, g_cbs, sum / cnt, mn, mx, csum / cnt, tsum / cnt);
            for (int b = 0; b < 16; b++) if (hist[b]) printf(" %.1f:%d", b * 4.1667, hist[b]);
            printf("\n");
            if (getenv("SEQ")) { printf("cb: "); for (int i = 200; i < 240 && i < g_cbs; i++) printf("%.1f/%.1f ", (g_cbt[i] - g_cbt[i - 1]) * 1e3, (g_cb_target[i] - g_cbt[i]) * 1e3); printf("\n"); }
            fflush(stdout); dispatch_async(dispatch_get_main_queue(), ^{ exit(0); });
        });
        [NSApp run];
    }
    return 0;
}
