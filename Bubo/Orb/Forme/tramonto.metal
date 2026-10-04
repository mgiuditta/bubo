#include "../OrbShading.h"

// Meteo: half a sun with its rays over the horizon line and a reflection below; the sun sinks and rises.
static float tramonto(float3 p, float t) {
    p.y += 0.17;
    float2 c = float2(0, -0.1 + 0.12 * sin(t * 0.8));
    float d = 9.0;
    for (int i = 0; i < 8; i++) {
        float a = float(i) * M_PI_F / 8.0;
        float2 v0 = c + 0.42 * float2(cos(a), sin(a));
        float2 v1 = c + 0.42 * float2(cos(a + M_PI_F / 16.0), sin(a + M_PI_F / 16.0));
        float2 v2 = c + 0.42 * float2(cos(a + M_PI_F / 8.0), sin(a + M_PI_F / 8.0));
        d = min(d, extrude(sdQuad2(p.xy, c, v0, v1, v2), p.z, 0.08) - 0.04);
    }
    for (int i = 0; i <= 8; i++) {
        float a = float(i) * M_PI_F / 8.0;
        float2 dir = float2(cos(a), sin(a));
        d = min(d, sdSegment(p, float3(c + 0.56 * dir, 0), float3(c + 0.78 * dir, 0), 0.04));
    }
    d = min(d, sdSegment(p, float3(-0.9, -0.12, 0), float3(0.9, -0.12, 0), 0.06));
    d = min(d, sdSegment(p, float3(-0.5, -0.3, 0), float3(0.5, -0.3, 0), 0.05));
    return d;
}

ORB_FORMA(tramonto)
