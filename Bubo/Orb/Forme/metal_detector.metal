#include "../OrbShading.h"

// Ricerca: a metal detector, a flat round coil at the foot of a long shaft with a control box and a grip; it sweeps left and right.
static float metal_detector(float3 p, float t) {
    p.x += 0.2;
    const float3 pivot = float3(0.45, 0.62, 0);
    float3 q = p - pivot;
    q.xy = q.xy * rot(0.18 * sin(t * 1.3));
    q += pivot;
    float coil = sdCylinder(q - float3(0, -0.75, 0), 0.38, 0.05);
    float shaft = sdSegment(q, float3(0.05, -0.7, 0), float3(0.45, 0.62, 0), 0.045);
    float grip = sdSegment(q, float3(0.45, 0.62, 0), float3(0.8, 0.62, 0), 0.06);
    float3 b = q - float3(0.33, 0.21, 0);
    b.xy = b.xy * rot(0.263);
    float box = sdRoundBox(b, float3(0.08, 0.12, 0.06), 0.02);
    return min(min(coil, shaft), min(grip, box));
}

ORB_FORMA(metal_detector)
