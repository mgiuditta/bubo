#include "../OrbShading.h"

// The 2D half disc of radius r above y = 0, its flat side down.
static float barbecueDome(float2 p, float r) {
    if (p.y >= 0.0) return max(length(p) - r, -p.y);
    return length(float2(p.x - clamp(p.x, -r, r), p.y));
}

// Chat · grigliata: a domed barbecue on three legs, with a thread of smoke rising from the knob.
static float barbecue(float3 p, float t) {
    const float2 rim = float2(0, -0.10);
    float dome = barbecueDome(p.xy - rim, 0.62);
    float lip = sdRoundBox2(p.xy - rim, float2(0.68, 0.035), 0.03);
    float d = extrude(min(dome, lip), p.z, 0.10) - 0.04;
    d = min(d, length(p - float3(0, 0.56, 0)) - 0.06);
    float3 q = float3(abs(p.x), p.y, p.z);
    d = min(d, sdSegment(q, float3(0.40, -0.12, 0), float3(0.58, -0.92, 0), 0.05));
    d = min(d, sdSegment(p, float3(0, -0.12, 0), float3(0, -0.92, 0), 0.04));
    for (int i = 0; i < 3; i++) {
        float ph = fract(t * 0.25 + float(i) / 3.0);
        float2 c = float2(0.05 + 0.08 * sin(ph * 6.0 + float(i) * 2.0), 0.70 + ph * 0.30);
        d = min(d, length(p - float3(c, 0)) - 0.06 * (1.0 - 0.5 * ph));
    }
    return d;
}

ORB_FORMA(barbecue)
