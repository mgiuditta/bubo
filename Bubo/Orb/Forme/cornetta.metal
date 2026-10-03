#include "../OrbShading.h"

// Chat: a telephone handset, an arch with a fat earpiece and mouthpiece, tilted; it shakes now and then as if ringing.
static float cornetta(float3 p, float t) {
    float ring = pulse(fract(t / 2.6), 0.5, 0.4);       // t = 0 is between rings
    p.xy = p.xy * rot(-0.7 + 0.09 * sin(t * 26.0) * ring);
    float2 q = p.xy;
    float d = udSegment2(q, float2(-0.5, 0.22), float2(0.5, 0.22)) - 0.11;
    d = min(d, udSegment2(q, float2(-0.52, 0.22), float2(-0.52, -0.22)) - 0.17);
    d = min(d, udSegment2(q, float2(0.52, 0.22), float2(0.52, -0.22)) - 0.17);
    return extrude(d, p.z, 0.05) - 0.04;
}

ORB_FORMA(cornetta)
