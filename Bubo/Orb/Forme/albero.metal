#include "../OrbShading.h"

// Chat · natura: a tree, a round crown of four lobes on a tapering trunk; the crown sways.
static float albero(float3 p, float t) {
    float trunk = sdRoundCone(p, float3(0, -0.80, 0), float3(0, 0.0, 0), 0.16, 0.09);
    float3 c = p - float3(0.05 * sin(t * 1.3), 0, 0);
    float crown = min(length(c - float3(0, 0.35, 0)) - 0.42, length(c - float3(0, 0.72, 0)) - 0.22);
    float3 q = float3(abs(c.x), c.y, c.z);
    crown = min(crown, length(q - float3(0.38, 0.10, 0)) - 0.30);
    return min(trunk, crown);
}

ORB_FORMA(albero)
