#include "../OrbShading.h"

// Mail · fuori ufficio: a door-hanger card with the hole at the top, two lines of text; it swings gently.
static float appendiporta(float3 p, float t) {
    const float2 pivot = float2(0, 0.9);
    float3 q = p;
    q.xy = (p.xy - pivot) * rot(0.18 * sin(t * 1.6)) + pivot;
    float d = sdRoundBox2(q.xy - float2(0, -0.275), float2(0.4, 0.575), 0.04);           // below the hole
    d = min(d, sdRoundBox2(q.xy - float2(0, 0.665), float2(0.4, 0.085), 0.04));          // above the hole
    d = min(d, sdRoundBox2(q.xy - float2(0.285, 0.44), float2(0.115, 0.14), 0.0));       // beside the hole
    d = min(d, sdRoundBox2(q.xy - float2(-0.285, 0.44), float2(0.115, 0.14), 0.0));
    float card = extrude(d, q.z, 0.04) - 0.02;
    float text = min(sdSegment(q, float3(-0.2, -0.15, 0.06), float3(0.2, -0.15, 0.06), 0.035),
                     sdSegment(q, float3(-0.2, -0.4, 0.06), float3(0.1, -0.4, 0.06), 0.035));
    return min(card, text);
}

ORB_FORMA(appendiporta)
