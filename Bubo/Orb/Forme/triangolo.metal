#include "../OrbShading.h"

// Musica: a musical triangle hung from a string, open at one corner, with its beater; it trembles.
static float triangolo(float3 p, float t) {
    float beater = min(length(p - float3(0.75, 0.55, 0.1)) - 0.06, sdSegment(p, float3(0.1, 0.05, 0.1), float3(0.75, 0.55, 0.1), 0.03));
    const float3 pivot = float3(0, 0.55, 0);
    float3 q = p - pivot;
    q.xy = q.xy * rot(0.03 * sin(t * 25.0));
    q += pivot;
    const float r = 0.06;
    float d = sdSegment(q, float3(0, 0.55, 0), float3(-0.6, -0.45, 0), r);
    d = min(d, sdSegment(q, float3(-0.6, -0.45, 0), float3(0.6, -0.45, 0), r));
    d = min(d, sdSegment(q, float3(0.6, -0.45, 0), float3(0.18, 0.25, 0), r));
    d = min(d, sdSegment(q, float3(0, 0.55, 0), float3(0, 0.85, 0), 0.02));
    return min(d, beater);
}

ORB_FORMA(triangolo)
