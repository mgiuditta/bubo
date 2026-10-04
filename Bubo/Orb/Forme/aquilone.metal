#include "../OrbShading.h"

// Chat · tempo libero all'aria aperta: a diamond kite with crossed spars and a tail of bows, swaying in the wind.
static float aquilone(float3 p, float t) {
    p.y -= 0.05;
    p.xy -= float2(0, 0.15);
    p.xy = p.xy * rot(0.14 * sin(t * 1.3));
    p.xy += float2(0, 0.15);
    float2 q = p.xy;
    float sail = extrude(sdQuad2(q, float2(0, 0.72), float2(0.42, 0.15), float2(0, -0.42), float2(-0.42, 0.15)) - 0.03, p.z, 0.025) - 0.015;
    float spars = min(sdSegment(p, float3(0, 0.72, 0.05), float3(0, -0.42, 0.05), 0.025), sdSegment(p, float3(-0.42, 0.15, 0.05), float3(0.42, 0.15, 0.05), 0.025));
    float d = min(sail, spars);
    float2 a = float2(0, -0.42);
    for (int i = 0; i < 4; i++) {
        float f = float(i + 1);
        float2 b = float2(0.13 * sin(t * 2.0 + f * 1.7) * (0.5 + 0.2 * f), -0.42 - 0.13 * f);
        d = min(d, sdSegment(p, float3(a, 0), float3(b, 0), 0.025));
        d = min(d, min(length(p - float3(b + float2(0.07, 0), 0)) - 0.055, length(p - float3(b - float2(0.07, 0), 0)) - 0.055));
        a = b;
    }
    return d;
}

ORB_FORMA(aquilone)
