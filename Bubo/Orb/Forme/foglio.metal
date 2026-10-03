#include "../OrbShading.h"

// Codice · scrittura: a sheet with the top right corner folded over and three lines of text raised on it.
static float foglio(float3 p, float) {
    float low = extrude(sdQuad2(p.xy, float2(-0.5, -0.72), float2(0.5, -0.72), float2(0.5, 0.3), float2(-0.5, 0.3)), p.z, 0.05) - 0.03;
    float up = extrude(sdQuad2(p.xy, float2(-0.5, 0.3), float2(0.5, 0.3), float2(0.1, 0.72), float2(-0.5, 0.72)), p.z, 0.05) - 0.03;
    float flap = extrude(sdQuad2(p.xy, float2(0.1, 0.72), float2(0.5, 0.3), float2(0.1, 0.3), float2(0.02, 0.5)), p.z - 0.08, 0.025) - 0.015;
    float d = min(min(low, up), flap);
    for (int i = 0; i < 3; i++) {
        float y = 0.0 - 0.22 * float(i);
        d = min(d, sdSegment(p, float3(-0.3, y, 0.08), float3(i == 2 ? 0.0 : 0.3, y, 0.08), 0.035));
    }
    return d;
}

ORB_FORMA(foglio)
