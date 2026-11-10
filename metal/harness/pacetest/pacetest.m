// Presentation timing probe: a 60 Hz producer on a CAMetalLayer, three present modes.
// usage: pacetest <plain|min|time> <seconds> <full 0|1> <gpu_ms> <late_every> <late_ms> [lead_ms]
#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#include <mach/mach_time.h>
#include <pthread.h>
#include <stdatomic.h>

#define MAXF 20000
static double g_commit[MAXF], g_end[MAXF], g_shown[MAXF], g_target[MAXF];
static atomic_int g_done;

static _Atomic double g_grid_phase; static int g_use_grid; static double g_grid_off;
static int g_snap; static double g_q = 1.0 / 240.0, g_eps = 0.0003, g_gs, g_gc; static int g_gn;
static dispatch_semaphore_t g_sem;
static atomic_int g_link_n;
static double g_link_ts[MAXF], g_link_target[MAXF];
static CALayer* g_dot; static int g_dotn;
@interface Beat : NSObject
- (void)beat:(CADisplayLink*)link;
@end
@implementation Beat
- (void)beat:(CADisplayLink*)link {
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    g_dot.backgroundColor = (g_dotn++ & 1) ? CGColorGetConstantColor(kCGColorBlack) : CGColorCreateGenericGray(0.02, 1);
    [CATransaction commit];
}
@end
@interface LinkTarget : NSObject
- (void)tick:(CADisplayLink*)link;
@end
@implementation LinkTarget
- (void)tick:(CADisplayLink*)link {
    int i = atomic_fetch_add(&g_link_n, 1);
    if (i < MAXF) { g_link_ts[i] = link.timestamp; g_link_target[i] = link.targetTimestamp; }
    g_grid_phase = link.targetTimestamp;
    dispatch_semaphore_signal(g_sem);
}
@end
// ---- pacing clock (the controller under test) ----
static pthread_mutex_t g_mu = PTHREAD_MUTEX_INITIALIZER;
static double c_prev_target, c_lead = 0.006, c_margin = 0.003, c_slew;
static double c_ring[8]; static int c_ring_n, c_ring_at, c_late_ring;
static int c_adapt = 1, c_calm, c_rebased[MAXF], c_misses, c_lates;
static double g_call[MAXF];
static double ClockTarget(int idx, double now) {
    const double P = 1.0 / 60.0;
    pthread_mutex_lock(&g_mu);
    double earliest = now + c_lead;
    double target = c_prev_target + P;
    double slack = target - earliest;
    int late = slack < 0;
    if (late) { target = earliest; c_lates++; }
    if (g_use_grid && g_grid_phase > 0) {
        // snap to the display link's grid: the first grid time at or after the wanted one
        double ph = g_grid_phase + g_grid_off;
        double k = ceil((target - 0.0005 - ph) / P);
        double snapped = ph + k * P;
        if (!late) slack = snapped - earliest;
        target = snapped;
    }
    if (g_snap && g_gn >= 8) {
        // snap to the grid of observed presentation instants, just after a boundary
        double g = atan2(g_gs, g_gc) / (2 * M_PI) * g_q + g_eps;
        double k = late ? ceil((target - g) / g_q) : round((target - g) / g_q);
        double snapped = g + k * g_q;
        if (!late) slack = snapped - earliest;
        target = snapped;
    }
    c_prev_target = target;
    c_rebased[idx] = late;
    g_call[idx] = now;
    g_target[idx] = target;
    c_late_ring = ((c_late_ring << 1) | late) & 0xff;
    c_ring[c_ring_at] = slack < -0.005 ? -0.005 : slack;
    c_ring_at = (c_ring_at + 1) & 7;
    if (c_ring_n < 8) c_ring_n++;
    double slew = 0;
    if (c_ring_n == 8) {
        double m = c_ring[0];
        for (int i = 1; i < 8; i++) if (c_ring[i] < m) m = c_ring[i];
        double e = m - c_margin;
        if (e > 0.0004 || e < -0.0004) slew = e * 0.08;
        if (slew > 0.00025) slew = 0.00025;
        if (slew < -0.00025) slew = -0.00025;
        if (slew < 0 && __builtin_popcount(c_late_ring) >= 3) slew = 0;
    }
    c_slew = slew;
    pthread_mutex_unlock(&g_mu);
    return target;
}
static void ClockShown(int idx, double shown) {
    pthread_mutex_lock(&g_mu);
    double err = shown - g_target[idx];
    { double a = fmod(shown, g_q) / g_q * 2 * M_PI; double w = g_gn < 8 ? 1.0 / (g_gn + 1) : 0.1;
      g_gs += (sin(a) - g_gs) * w; g_gc += (cos(a) - g_gc) * w; g_gn++; }
    if (c_adapt) {
        if (err > 0.006) { // shown a refresh after its slot: the lead is too short
            c_lead += 0.001; if (c_lead > 0.025) c_lead = 0.025;
            c_misses++; c_calm = 0;
        } else if (++c_calm >= 1800) {
            c_calm = 0; c_lead -= 0.00025; if (c_lead < 0.002) c_lead = 0.002;
        }
    }
    pthread_mutex_unlock(&g_mu);
}
static double Now(void) { return CACurrentMediaTime(); }
// slot lock: on a steady refresh grid, hold the frame's arrival at a fixed offset inside its refresh slot
static int s_on; static double s_off = 0.0055, s_floor = 1e9, s_ring[9], s_slewsum; static int s_rn, s_rat, s_n;
static double g_jit;
static int cmpd(const void* a, const void* b) { double x = *(const double*)a, y = *(const double*)b; return x < y ? -1 : x > y; }
// phase lock for plain presents on a fixed-rate display: hold the least recent wait at a target above the learned floor
static double g_drift = 1.0007; static int p_obs;
static int p_on; static double p_target = 0.006, p_margin = 0.003, p_prev, p_ring[8], p_lastmin; static int p_rn, p_rat, p_miss, p_bumps;
static double p_tlog[64]; static int p_tn; static int p_mi[64], p_mn; static double p_mw[64], p_mt[64], p_ml[64];
static void PLockNote(int idx, double shown) {
    const double P = 1.0 / 60.0;
    pthread_mutex_lock(&g_mu);
    double interval = p_prev > 0 ? shown - p_prev : P; p_prev = shown;
    double wait = shown - g_end[idx];
    static double p_pend = -1;
    if (interval > 1.3 * P) {
        p_miss++;
        p_pend = p_rn == 8 ? p_lastmin : -1;   // judged by the next frame: a lone late frame is the floor
        p_rn = 0; c_slew = 0;
    } else {
        if (p_pend >= 0) {
            if (interval > 0.75 * P && !getenv("NOBUMP") && p_pend + p_margin > p_target) { p_target = p_pend + p_margin; p_bumps++; if (p_tn < 64) p_tlog[p_tn++] = p_target; }
            p_pend = -1;
        }
        p_ring[p_rat] = wait; p_rat = (p_rat + 1) % 8; if (p_rn < 8) p_rn++;
        if (p_rn == 8) {
            double m = p_ring[0]; for (int i = 1; i < 8; i++) if (p_ring[i] < m) m = p_ring[i];
            p_lastmin = m; double e = m - p_target; double s = e * 0.08;
            if (s > 0.00025) s = 0.00025; if (s < -0.00025) s = -0.00025;
            c_slew = fabs(e) > 0.0004 ? s : 0;
        }
    }
    if (p_obs) c_slew = 0;
    if (s_on) {
        if (++s_n > 60 && wait > 0.001 && wait < s_floor) s_floor = wait;
        s_ring[s_rat] = wait; s_rat = (s_rat + 1) % 9; if (s_rn < 9) s_rn++;
        c_slew = 0;
        if (s_rn == 9 && s_n > 120) {
            double t[9]; memcpy(t, s_ring, sizeof t); qsort(t, 9, sizeof(double), cmpd);
            double e = t[4] - (s_floor + s_off); double sl = e * 0.05;
            if (sl > 0.00015) sl = 0.00015; if (sl < -0.00015) sl = -0.00015;
            c_slew = fabs(e) > 0.0005 ? sl : 0; s_slewsum += c_slew;
        }
    }
    pthread_mutex_unlock(&g_mu);
}
static void SleepUntil(double t) {
    static mach_timebase_info_data_t tb;
    if (!tb.denom) mach_timebase_info(&tb);
    mach_wait_until((uint64_t)(t * 1e9 * tb.denom / tb.numer));
}

int main(int argc, const char** argv) {
    @autoreleasepool {
        const char* mode = argc > 1 ? argv[1] : "plain";
        double seconds = argc > 2 ? atof(argv[2]) : 8;
        int full = argc > 3 ? atoi(argv[3]) : 0;
        double gpu_ms = argc > 4 ? atof(argv[4]) : 0;
        int late_every = argc > 5 ? atoi(argv[5]) : 0;
        double late_ms = argc > 6 ? atof(argv[6]) : 0;
        double lead_ms = argc > 7 ? atof(argv[7]) : 0;
        int use_link = argc > 8 ? atoi(argv[8]) : 0; // 1: 60 Hz display link as a rate hint, 2: also drives the producer
        double sync_delay_ms = argc > 9 ? atof(argv[9]) : 0;
        if (getenv("MODE60")) {
            CGDirectDisplayID d = CGMainDisplayID(); CGDisplayModeRef cur = CGDisplayCopyDisplayMode(d);
            NSDictionary* opt = @{(__bridge NSString*)kCGDisplayShowDuplicateLowResolutionModes: @YES};
            CFArrayRef all = CGDisplayCopyAllDisplayModes(d, (__bridge CFDictionaryRef)opt);
            for (CFIndex i = 0; i < CFArrayGetCount(all); i++) { CGDisplayModeRef m = (CGDisplayModeRef)CFArrayGetValueAtIndex(all, i);
                if (CGDisplayModeGetPixelWidth(m) == CGDisplayModeGetPixelWidth(cur) && CGDisplayModeGetPixelHeight(m) == CGDisplayModeGetPixelHeight(cur) &&
                    CGDisplayModeGetWidth(m) == CGDisplayModeGetWidth(cur) && fabs(CGDisplayModeGetRefreshRate(m) - 60.0) < 0.01) {
                    CGError e = CGDisplaySetDisplayMode(d, m, NULL); fprintf(stderr, "60 Hz mode set: error %d\n", e); usleep(1500000); break; } }
        }
        g_sem = dispatch_semaphore_create(0);
        g_use_grid = use_link != 0 && !strcmp(mode, "clock");
        if (getenv("GRIDOFF")) g_grid_off = atof(getenv("GRIDOFF")) * 1e-3;
        if (getenv("PLOCK")) { p_on = 1; p_target = atof(getenv("PLOCK")) * 1e-3; }
        if (getenv("DRIFT")) g_drift = atof(getenv("DRIFT"));
        if (getenv("POBS")) { p_on = 1; p_obs = 1; p_target = 0; }
        if (getenv("SLOT")) { p_on = 1; s_on = 1; p_target = 0; s_off = atof(getenv("SLOT")) * 1e-3; setenv("NOBUMP", "1", 1); }
        if (getenv("JIT")) g_jit = atof(getenv("JIT")) * 1e-3;
        if (getenv("PMARGIN")) p_margin = atof(getenv("PMARGIN")) * 1e-3;
        if (getenv("SNAP")) g_snap = atoi(getenv("SNAP"));
        if (getenv("EPS")) g_eps = atof(getenv("EPS")) * 1e-3;
        if (getenv("QHZ")) g_q = 1.0 / atof(getenv("QHZ"));
        if (getenv("LEAD")) c_lead = atof(getenv("LEAD")) * 1e-3;
        if (getenv("MARGIN")) c_margin = atof(getenv("MARGIN")) * 1e-3;
        if (getenv("ADAPT")) c_adapt = atoi(getenv("ADAPT"));
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        NSScreen* screen = [NSScreen mainScreen];
        NSRect rect = full ? screen.frame : NSMakeRect(200, 200, 1280, 720);
        NSWindow* win = [[NSWindow alloc] initWithContentRect:rect
                                                    styleMask:full ? NSWindowStyleMaskBorderless : NSWindowStyleMaskTitled
                                                      backing:NSBackingStoreBuffered defer:NO];
        if (full) [win setLevel:NSMainMenuWindowLevel + 1];
        id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
        CAMetalLayer* layer = [CAMetalLayer layer];
        layer.device = dev;
        layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        layer.maximumDrawableCount = 3;
        layer.displaySyncEnabled = YES;
        layer.framebufferOnly = YES;
        CGFloat scale = screen.backingScaleFactor;
        layer.drawableSize = CGSizeMake(rect.size.width * scale, rect.size.height * scale);
        NSView* view = [[NSView alloc] initWithFrame:rect];
        view.wantsLayer = YES;
        view.layer = layer;
        win.contentView = view;
        { int comp = getenv("COMP") ? atoi(getenv("COMP")) : 0;
          if (comp == 1) layer.opaque = NO;
          if (comp == 2) { CALayer* dot = [CALayer layer]; dot.frame = CGRectMake(0, 0, 2, 2); dot.backgroundColor = CGColorCreateGenericRGB(0, 0, 0, 0.02); dot.zPosition = 10; [layer addSublayer:dot]; }
          if (comp == 3) { win.opaque = NO; win.backgroundColor = [NSColor clearColor]; layer.opaque = NO; }
          if (comp == 5) { win.opaque = NO; win.backgroundColor = [NSColor clearColor]; }
          if (comp == 6) { win.opaque = NO; }
          if (comp == 7) { win.alphaValue = 0.999; }
          if (comp == 8) { g_dot = [CALayer layer]; g_dot.frame = CGRectMake(0, 0, 1, 1); g_dot.zPosition = 10; g_dot.backgroundColor = CGColorGetConstantColor(kCGColorBlack); [layer addSublayer:g_dot];
              static Beat* beat; beat = [Beat new]; CADisplayLink* bl = [view displayLinkWithTarget:beat selector:@selector(beat:)];
              bl.preferredFrameRateRange = CAFrameRateRangeMake(120, 120, 120); [bl addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes]; }
          if (comp == 9) { g_dot = [CALayer layer]; g_dot.frame = CGRectMake(0, 0, 1, 1); g_dot.zPosition = 10; g_dot.backgroundColor = CGColorGetConstantColor(kCGColorBlack); [layer addSublayer:g_dot];
              CGColorRef dark = CGColorCreateGenericGray(0.02, 1);
              dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{ for (;;) { usleep(7000); [CATransaction begin]; [CATransaction setDisableActions:YES];
                  g_dot.backgroundColor = (g_dotn++ & 1) ? CGColorGetConstantColor(kCGColorBlack) : dark; [CATransaction commit]; [CATransaction flush]; } }); }
          if (comp == 4) { NSView* top = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 2, 2)]; top.wantsLayer = YES; top.layer.backgroundColor = CGColorCreateGenericRGB(0, 0, 0, 0.02); [view addSubview:top]; } }
        [win makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];
        LinkTarget* lt = [LinkTarget new];
        if (use_link) {
            CADisplayLink* link = [view displayLinkWithTarget:lt selector:@selector(tick:)];
            link.preferredFrameRateRange = CAFrameRateRangeMake(60, 60, 60);
            [link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        }
        id<MTLCommandQueue> queue = [dev newCommandQueue];
        // GPU load: a compute-free way is many full-screen blended triangles; here a big blur-free
        // overdraw with a trivial shader.
        NSError* err = nil;
        id<MTLLibrary> lib = [dev newLibraryWithSource:
            @"#include <metal_stdlib>\nusing namespace metal;\n"
             "struct V{float4 p [[position]];};\n"
             "vertex V vs(uint vid [[vertex_id]]){V o; float2 p=float2((vid<<1)&2, vid&2); o.p=float4(p*2-1,0,1); return o;}\n"
             "fragment float4 fs(V i [[stage_in]], constant float& c [[buffer(0)]]){ float a=0; for(int k=0;k<24;k++){a+=sin(i.p.x*0.01*k+c);} return float4(a*0.001+c,0.2,0.3,0.02);}\n"
            options:nil error:&err];
        if (!lib) { NSLog(@"%@", err); exit(1); }
        MTLRenderPipelineDescriptor* pd = [MTLRenderPipelineDescriptor new];
        pd.vertexFunction = [lib newFunctionWithName:@"vs"];
        pd.fragmentFunction = [lib newFunctionWithName:@"fs"];
        pd.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
        pd.colorAttachments[0].blendingEnabled = YES;
        pd.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
        pd.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        id<MTLRenderPipelineState> pso = [dev newRenderPipelineStateWithDescriptor:pd error:&err];
        int passes = (int)(gpu_ms * 6); // calibrated roughly below by the printed GPU time

        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
          const double P = 1.0 / 60.0;
          double next = Now() + 0.5;
          double last_target = 0;
          int n = 0;
          double end_at = next + seconds;
          while (Now() < end_at && n < MAXF) {
              double due = next;
              if (late_every && n % late_every == late_every - 1) due += late_ms * 1e-3;
              if (g_jit > 0) due += g_jit * (double)arc4random_uniform(1000) / 1000.0;
              if (use_link == 2) {
                  dispatch_semaphore_wait(g_sem, dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC));
                  double extra = sync_delay_ms * 1e-3 + (due - next);
                  if (extra > 0) SleepUntil(Now() + extra);
              } else {
                  SleepUntil(due);
              }
              next += P * g_drift; // the producer's clock is not the display's
              if (!strcmp(mode, "clock") || p_on) { pthread_mutex_lock(&g_mu); next += c_slew; pthread_mutex_unlock(&g_mu); }
              @autoreleasepool {
                  id<CAMetalDrawable> d = [layer nextDrawable];
                  if (!d) continue;
                  id<MTLCommandBuffer> cmd = [queue commandBuffer];
                  MTLRenderPassDescriptor* rp = [MTLRenderPassDescriptor new];
                  rp.colorAttachments[0].texture = d.texture;
                  rp.colorAttachments[0].loadAction = MTLLoadActionClear;
                  rp.colorAttachments[0].clearColor = MTLClearColorMake((n % 60) / 60.0, 0.1, 0.1, 1);
                  rp.colorAttachments[0].storeAction = MTLStoreActionStore;
                  id<MTLRenderCommandEncoder> enc = [cmd renderCommandEncoderWithDescriptor:rp];
                  [enc setRenderPipelineState:pso];
                  float c = (n % 60) / 60.0f;
                  [enc setFragmentBytes:&c length:4 atIndex:0];
                  for (int k = 0; k < passes; k++) [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
                  [enc endEncoding];
                  const int idx = n;
                  const int is_clock = !strcmp(mode, "clock");
                  [d addPresentedHandler:^(id<MTLDrawable> shown) { g_shown[idx] = shown.presentedTime; if (is_clock) ClockShown(idx, shown.presentedTime); if (p_on) PLockNote(idx, shown.presentedTime); }];
                  [cmd addCompletedHandler:^(id<MTLCommandBuffer> done) {
                      g_end[idx] = done.GPUEndTime;
                      if (is_clock) [d presentAtTime:ClockTarget(idx, Now())];
                  }];
                  double now = Now();
                  if (!strcmp(mode, "min")) {
                      [cmd presentDrawable:d afterMinimumDuration:(getenv("MINF") ? atof(getenv("MINF")) : 0.97) * P];
                  } else if (!strcmp(mode, "time")) {
                      double target = last_target + P;
                      if (target < now + lead_ms * 1e-3) target = now + lead_ms * 1e-3;
                      last_target = target;
                      g_target[idx] = target;
                      [cmd presentDrawable:d atTime:target];
                  } else if (!is_clock) {
                      [cmd presentDrawable:d];
                  }
                  g_commit[idx] = now;
                  [cmd commit];
              }
              n++;
          }
          usleep(300000);
          // report
          double wsum = 0, wmin = 1e9, wmax = 0, lsum = 0, gsum = 0; int wn = 0;
          int hist[64] = {0}; int shown_n = 0, dropped = 0;
          double prev = 0;
          for (int i = 30; i < n; i++) {
              if (g_shown[i] <= 0) { dropped++; continue; }
              if (g_end[i] > 0) { double w = (g_shown[i] - g_end[i]) * 1e3; wsum += w; wn++; if (w < wmin) wmin = w; if (w > wmax) wmax = w; gsum += (g_end[i] - g_commit[i]) * 1e3; }
              lsum += (g_shown[i] - g_commit[i]) * 1e3;
              if (prev > 0) { int b = (int)((g_shown[i] - prev) * 1e3 / 4.1667 + 0.5); if (b > 63) b = 63; if (b < 0) b = 0; hist[b]++; }
              prev = g_shown[i]; shown_n++;
          }
          printf("%s full=%d gpu=%.0f late=%d/%.0f lead=%.0f link=%d/%.0f: frames %d shown %d dropped %d | commit->GPU end %.1f ms | GPU end->shown mean %.1f min %.1f max %.1f | commit->shown %.1f | intervals:",
                 mode, full, gpu_ms, late_every, late_ms, lead_ms, use_link, sync_delay_ms, n, shown_n, dropped, gsum / (wn ? wn : 1), wsum / (wn ? wn : 1), wmin, wmax, lsum / (shown_n ? shown_n : 1));
          for (int b = 0; b < 64; b++) if (hist[b]) printf(" %.1f:%d", b * 4.1667, hist[b]);
          if (s_on) printf(" | slot lock: floor %.1f ms, offset %.1f, net slew %.1f ms", s_floor * 1e3, s_off * 1e3, s_slewsum * 1e3);
          if (p_on && !s_on) { printf(" | lock: target %.1f ms, misses %d, bumps %d (", p_target * 1e3, p_miss, p_bumps); for (int i = 0; i < p_tn; i++) printf("%.1f ", p_tlog[i] * 1e3); printf(")\nmisses (frame:would-be wait/target/ring min):"); for (int i = 0; i < p_mn; i++) printf(" %d:%.1f/%.1f/%.1f", p_mi[i], p_mw[i] * 1e3, p_mt[i] * 1e3, p_ml[i] * 1e3); }
          if (p_on && getenv("MISSDUMP")) { for (int k = 1; k < p_mn && k < 4; k++) { printf("\nmiss %d (commit gap/GPU end-commit/wait/shown gap):", p_mi[k]);
              for (int i = p_mi[k] - 10; i <= p_mi[k] + 3; i++) printf(" %.1f/%.1f/%.1f/%.1f", (g_commit[i] - g_commit[i - 1]) * 1e3, (g_end[i] - g_commit[i]) * 1e3, (g_shown[i] - g_end[i]) * 1e3, (g_shown[i] - g_shown[i - 1]) * 1e3); } }
          if (!strcmp(mode, "clock")) {
              int reb = 0; double es = 0; int en = 0; double emax = 0;
              for (int i = 30; i < n; i++) { reb += c_rebased[i]; if (g_shown[i] > 0) { double e = (g_shown[i] - g_target[i]) * 1e3; es += e; en++; if (e > emax) emax = e; } }
              printf(" | clock: lead %.2f ms, late at call %d, misses %d, shown-target mean %.1f max %.1f", c_lead * 1e3, reb, c_misses, es / (en ? en : 1), emax);
          }
          if (getenv("SEQ")) {
              if (getenv("WAITS")) { printf("\nwait every 8th frame:"); for (int i = 64; i < n; i += 8) printf(" %.0f", (g_shown[i] - g_end[i]) * 1e3); }
              printf("\nseq (interval/wait):");
              for (int i = 100; i < 160 && i < n; i++) printf(" %.1f/%.1f/%.1f", (g_shown[i] - g_shown[i-1]) * 1e3, (g_shown[i] - g_end[i]) * 1e3, g_target[i] > 0 ? (g_shown[i] - g_target[i]) * 1e3 : 0.0);
              printf("\ncommit intervals:");
              for (int i = 100; i < 130 && i < n; i++) printf(" %.1f", (g_commit[i] - g_commit[i-1]) * 1e3);
          }
          int ln = atomic_load(&g_link_n); if (ln > MAXF) ln = MAXF;
          if (ln > 40) {
              double a = 0, mn = 1e9, mx = 0; for (int i = 31; i < ln; i++) { double d = (g_link_ts[i] - g_link_ts[i-1]) * 1e3; a += d; if (d < mn) mn = d; if (d > mx) mx = d; }
              printf(" | link %d callbacks, period mean %.2f min %.2f max %.2f ms, target-timestamp %.1f ms", ln, a / (ln - 31), mn, mx, (g_link_target[ln-1] - g_link_ts[ln-1]) * 1e3);
          }
          printf("\n");
          fflush(stdout);
          atomic_store(&g_done, 1);
          dispatch_async(dispatch_get_main_queue(), ^{ exit(0); });
        });
        [NSApp run];
    }
    return 0;
}
