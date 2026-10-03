#include "../OrbShading.h"

// Salute: a molar with two cusps on the crown and two tapering roots.
static float dente(float3 p, float) {
    p.y -= 0.12;
    float3 q = float3(abs(p.x), p.y, p.z);
    float crown = sdRoundBox(p - float3(0, 0.30, 0), float3(0.40, 0.22, 0.32), 0.15);
    float cusps = length(q - float3(0.28, 0.52, 0)) - 0.17;
    float roots = sdRoundCone(q, float3(0.20, 0.10, 0), float3(0.27, -0.85, 0), 0.17, 0.05);
    return min(crown, min(cusps, roots));
}

ORB_FORMA(dente)
