#include "../OrbShading.h"

// Musica · piano: a grand piano in profile, its lid propped open, a keyboard strip on the right and three legs.
static float pianoforte(float3 p, float) {
    float body = sdRoundBox(p - float3(0, -0.15, 0), float3(0.80, 0.16, 0.30), 0.04);
    float keys = sdRoundBox(p - float3(0.62, 0.03, 0), float3(0.18, 0.03, 0.26), 0.015);
    const float2 hinge = float2(-0.60, 0.02);
    float3 l = float3((p.xy - hinge) * rot(-0.5), p.z);
    float lid = sdRoundBox(l - float3(0.55, 0, 0), float3(0.55, 0.03, 0.28), 0.02);
    float prop = sdSegment(p, float3(0.55, 0.0, 0), float3(0.22, 0.42, 0), 0.025);
    float3 q = float3(abs(p.x), p.y, p.z);
    float leg = sdSegment(q, float3(0.65, -0.30, 0), float3(0.65, -0.80, 0), 0.06);
    return min(min(body, keys), min(min(lid, prop), leg));
}

ORB_FORMA(pianoforte)
