#include "../OrbShading.h"

// Meteo: an open umbrella with a hooked handle, leaning a little from side to side.
static float ombrello(float3 p, float t) {
    p.xy = p.xy * rot(-0.10 * sin(t * 1.3));
    const float2 c = float2(0, -0.10);
    const float R = 0.90;
    float dome = 9.0;
    for (int i = 0; i < 3; i++) {                      // a half polygon, three kites around the centre
        float a0 = 3.1415927 - 1.0471976 * float(i);
        float2 v1 = c + R * float2(cos(a0), sin(a0));
        float2 v2 = c + R * float2(cos(a0 - 0.5235988), sin(a0 - 0.5235988));
        float2 v3 = c + R * float2(cos(a0 - 1.0471976), sin(a0 - 1.0471976));
        dome = min(dome, sdQuad2(p.xy, c, v1, v2, v3));
    }
    float canopy = extrude(dome, p.z, 0.10) - 0.04;
    float shaft = sdSegment(p, float3(0, 0.86, 0), float3(0, -0.70, 0), 0.04);
    float2 h = p.xy - float2(-0.14, -0.70);
    float hook = extrude(min(udQuarterArc(h, float2(0), 0.14, float2(1, -1)),
                             udQuarterArc(h, float2(0), 0.14, float2(-1, -1))) - 0.02, p.z, 0.01) - 0.02;
    float tip = sdSegment(p, float3(-0.28, -0.70, 0), float3(-0.28, -0.60, 0), 0.04);
    return min(min(canopy, shaft), min(hook, tip));
}

ORB_FORMA(ombrello)
