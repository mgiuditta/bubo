#include "../OrbShading.h"

// Finanza · accordo: a handshake, two forearms in cuffs meeting in a clasp; the hands shake once in a while.
static float stretta_di_mano(float3 p, float t) {
    float ph = fract(t / 4.0);
    p.xy = p.xy * rot(0.22 * (pulse(ph, 0.06, 0.06) - pulse(ph, 0.18, 0.06)));
    float d = length(p) - 0.24;
    d = min(d, sdSegment(p, float3(-0.75, 0.05, 0), float3(0, 0, 0), 0.15));
    d = min(d, sdSegment(p, float3(0.75, -0.05, 0), float3(0, 0, 0), 0.15));
    d = min(d, extrude(sdRoundBox2(float2(abs(p.x) - 0.88, p.y - 0.06 * sign(p.x)), float2(0.10, 0.26), 0.04), p.z, 0.10) - 0.04);
    for (int i = 0; i < 4; i++) d = min(d, length(p - float3(-0.18 + 0.12 * float(i), -0.24, 0)) - 0.08);
    return min(d, sdSegment(p, float3(-0.10, 0.20, 0), float3(0.12, 0.13, 0), 0.07));
}

ORB_FORMA(stretta_di_mano)
