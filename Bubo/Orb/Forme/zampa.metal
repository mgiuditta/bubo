#include "../OrbShading.h"

// Salute · animali di casa: a paw print, a large pad and four toe pads, puffed like cushions.
static float zampa(float3 p, float) {
    p.y -= 0.1;
    float2 q = p.xy;
    float pad = min(min(length(q - float2(0, -0.32)) - 0.3, length(q - float2(-0.3, -0.22)) - 0.2),
                    min(length(q - float2(0.3, -0.22)) - 0.2, length(q - float2(0, -0.58)) - 0.22));
    float toes = min(min(length(q - float2(-0.58, 0.12)) - 0.18, length(q - float2(-0.2, 0.46)) - 0.18),
                     min(length(q - float2(0.2, 0.46)) - 0.18, length(q - float2(0.58, 0.12)) - 0.18));
    return extrude(min(pad, toes), p.z, 0.04) - 0.07;
}

ORB_FORMA(zampa)
