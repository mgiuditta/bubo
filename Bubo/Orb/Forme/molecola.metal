#include "../OrbShading.h"

// Chat · natura: a molecule, a large sphere joined by two bars to two smaller ones below it.
static float molecola(float3 p, float) {
    float3 q = float3(abs(p.x), p.y, p.z);
    float core = length(p - float3(0, 0.25, 0)) - 0.28;
    float atom = length(q - float3(0.62, -0.3, 0)) - 0.2;
    float bond = sdSegment(q, float3(0, 0.25, 0), float3(0.62, -0.3, 0), 0.06);
    return min(min(core, atom), bond);
}

ORB_FORMA(molecola)
