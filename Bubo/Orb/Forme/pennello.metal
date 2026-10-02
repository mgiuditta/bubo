#include "../OrbShading.h"

// Creativo: a round paintbrush, tip down to the left, making a slow stroke.
static float pennello(float3 p, float t) {
    const float2 pivot = float2(0.45, 0.45);
    p.xy = (p.xy - pivot) * rot(0.12 * sin(t * 1.4)) + pivot;
    const float3 u = float3(0.7071, 0.7071, 0), tip = float3(-0.72, -0.72, 0);
    float belly = sdRoundCone(p, tip + u * 0.04, tip + u * 0.40, 0.025, 0.21);
    float shoulder = sdRoundCone(p, tip + u * 0.40, tip + u * 0.62, 0.21, 0.15);
    float ferrule = sdSegment(p, tip + u * 0.66, tip + u * 0.94, 0.155);
    float handle = sdRoundCone(p, tip + u * 0.98, tip + u * 1.92, 0.12, 0.065);
    return min(min(belly, shoulder), min(ferrule, handle));
}

ORB_FORMA(pennello)
