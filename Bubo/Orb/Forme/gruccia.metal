#include "../OrbShading.h"

// Creativo: a clothes hanger, a hook, a neck and two sloping shoulders over a bar; it swings from the hook.
static float gruccia(float3 p, float t) {
    const float2 pivot = float2(0, 0.78), c = float2(0, 0.64);
    float3 q = p;
    q.xy = pivot + (p.xy - pivot) * rot(0.16 * sin(t * 1.7));
    float2 f = float2(abs(q.x), q.y);
    float d2 = udSegment2(q.xy, float2(0, 0.5), float2(0, 0.3));
    d2 = min(d2, min(udQuarterArc(q.xy, c, 0.14, float2(1, 1)), udQuarterArc(q.xy, c, 0.14, float2(-1, 1))));
    d2 = min(d2, udQuarterArc(q.xy, c, 0.14, float2(1, -1)));
    d2 = min(d2, udSegment2(f, float2(0, 0.3), float2(0.8, -0.25)));
    d2 = min(d2, udSegment2(f, float2(0, -0.25), float2(0.8, -0.25)));
    return extrude(d2 - 0.045, q.z, 0.04);
}

ORB_FORMA(gruccia)
