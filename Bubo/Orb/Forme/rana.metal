#include "../OrbShading.h"

// Chat · natura: a frog sitting seen from the front, big eyes, folded hind legs; it hops on the spot.
static float rana(float3 p, float t) {
    p.y -= 0.12 * max(0.0, sin(t * 3.0));
    float body = sdRoundCone(p, float3(0, -0.3, 0), float3(0, 0.12, 0), 0.42, 0.34);
    float3 q = float3(abs(p.x), p.y, p.z);
    float eyes = length(q - float3(0.2, 0.5, 0)) - 0.14;
    float hind = sdSegment(q, float3(0.38, -0.25, 0), float3(0.55, -0.6, 0), 0.12);
    float toes = sdSegment(q, float3(0.55, -0.64, 0), float3(0.78, -0.66, 0), 0.08);
    float arms = sdSegment(q, float3(0.18, -0.5, 0.1), float3(0.25, -0.68, 0.1), 0.07);
    return min(min(body, eyes), min(min(hind, toes), arms));
}

ORB_FORMA(rana)
