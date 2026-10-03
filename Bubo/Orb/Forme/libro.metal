#include "../OrbShading.h"

// Chat: an open book facing the viewer, two pages sloping down to the spine; a page turns over around the spine now and then.
static float libro(float3 p, float t) {
    float2 a = float2(0.05, -0.50), b = float2(0.85, -0.35), c = float2(0.85, 0.55), e = float2(0.05, 0.40);
    float d = extrude(sdQuad2(float2(abs(p.x), p.y), a, b, c, e), p.z, 0.04) - 0.02;
    float turn = M_PI_F * smoothstep(0.0, 1.0, fract(t / 3.5));
    float3 q = p - float3(0, 0, 0.07);
    q.xz = q.xz * rot(-turn);
    float leaf = extrude(sdQuad2(q.xy, float2(0.06, -0.44), float2(0.78, -0.30), float2(0.78, 0.50), float2(0.06, 0.35)), q.z, 0.012) - 0.01;
    return min(d, leaf);
}

ORB_FORMA(libro)
