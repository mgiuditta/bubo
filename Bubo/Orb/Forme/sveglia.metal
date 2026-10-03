#include "../OrbShading.h"

// Tempo: an alarm clock with two bells, a hammer, two feet and its hands; it trembles as if ringing.
static float sveglia(float3 p, float t) {
    float shake = 0.035 * sin(t * 32.0) * (0.6 + 0.4 * sin(t * 1.7));
    p.xy = p.xy * rot(shake);
    float3 q = float3(abs(p.x), p.y, p.z);
    float body = extrude(length(p.xy) - 0.40, p.z, 0.10) - 0.12;
    float bezel = sdTorusXY(p - float3(0, 0, 0.14), 0.44, 0.03);
    float bell = length(q - float3(0.42, 0.50, 0)) - 0.17;
    float hammer = sdSegment(p, float3(0, 0.55, 0), float3(0, 0.74, 0), 0.03);
    float foot = sdSegment(q, float3(0.30, -0.45, 0), float3(0.40, -0.80, 0), 0.05);
    float hands = min(sdSegment(p, float3(0, 0, 0.16), float3(0, 0.30, 0.16), 0.035),
                      sdSegment(p, float3(0, 0, 0.16), float3(0.20, -0.08, 0.16), 0.035));
    return min(min(body, bezel), min(min(bell, hammer), min(foot, hands)));
}

ORB_FORMA(sveglia)
