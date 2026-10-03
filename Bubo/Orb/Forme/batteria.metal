#include "../OrbShading.h"

// Musica · groove: a drum kit seen from the front, bass drum, two toms and a cymbal that shivers on its stand.
static float batteria(float3 p, float t) {
    float bass = extrude(length(p.xy - float2(0, -0.4)) - 0.4, p.z, 0.12) - 0.03;
    float3 m = float3(abs(p.x), p.y, p.z);
    float toms = extrude(length(m.xy - float2(0.3, 0.22)) - 0.19, p.z, 0.08) - 0.03;
    float legs = min(sdSegment(m, float3(0.26, -0.05, 0), float3(0.5, -0.9, 0), 0.04), 9.0);
    float stand = sdSegment(p, float3(0.72, 0.55, 0), float3(0.72, -0.9, 0), 0.04);
    float3 c = p - float3(0.72, 0.55, 0);
    c.xy = c.xy * rot(-0.12 + 0.07 * sin(t * 17.0));
    float cymbal = sdSegment(c, float3(-0.3, 0, 0), float3(0.3, 0.06, 0), 0.05);
    float foot = sdSegment(p, float3(-0.62, -0.9, 0), float3(0.62, -0.9, 0), 0.04);
    return min(min(bass, toms), min(min(legs, stand), min(cymbal, foot)));
}

ORB_FORMA(batteria)
