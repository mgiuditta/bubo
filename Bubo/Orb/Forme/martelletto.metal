#include "../OrbShading.h"

// Chat · conversazione: a judge's gavel over its round block; it is raised now and then and comes down once.
static float martelletto(float3 p, float t) {
    const float2 pivot = float2(0.6, 0.45), head = float2(-0.15, -0.30), axis = float2(0.226, -0.226);
    float lift = 0.5 * pulse(fract(t / 3.0), 0.3, 0.2);
    float3 q = p;
    q.xy = pivot + (p.xy - pivot) * rot(lift);
    float d = sdSegment(q, float3(pivot, 0), float3(head, 0), 0.07);
    d = min(d, sdSegment(q, float3(head - axis, 0), float3(head + axis, 0), 0.17));
    return min(d, sdCylinder(p - float3(-0.1, -0.8, 0), 0.55, 0.07));
}

ORB_FORMA(martelletto)
