#include "../OrbShading.h"

// Chat · frutta e verdura di stagione: a half-moon slice of watermelon, with its rind and a few seeds.
static float anguria(float3 p, float) {
    p.y -= 0.2;
    const float2 c = float2(0, 0.0);
    const float R = 0.74;
    float flesh = 9.0, rind = 9.0;
    for (int i = 0; i < 6; i++) {
        float a0 = -1.5708 + 0.5236 * float(i), a1 = a0 + 0.5236, am = 0.5 * (a0 + a1);
        float2 v0 = c + R * float2(sin(a0), -cos(a0));
        float2 v1 = c + R * float2(sin(a1), -cos(a1));
        float2 vm = c + R * float2(sin(am), -cos(am));
        flesh = min(flesh, sdQuad2(p.xy, c + float2(0, 0.001), v0, vm, v1));
        rind = min(rind, udSegment2(p.xy, v0, vm) - 0.07);
        rind = min(rind, udSegment2(p.xy, vm, v1) - 0.07);
    }
    float slice = extrude(min(flesh, rind), p.z, 0.07) - 0.03;
    float seeds = 9.0;
    const float2 s[5] = { float2(-0.35, -0.25), float2(0.0, -0.35), float2(0.35, -0.25), float2(-0.18, -0.52), float2(0.2, -0.55) };
    for (int i = 0; i < 5; i++) seeds = min(seeds, length(p - float3(s[i], 0.1)) - 0.045);
    return min(slice, seeds);
}

ORB_FORMA(anguria)
