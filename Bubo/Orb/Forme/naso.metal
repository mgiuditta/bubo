#include "../OrbShading.h"

// Salute: a nose in profile, a long bridge sloping down to a rounded tip, a wing and the underside.
static float naso(float3 p, float) {
    float bridge = sdRoundCone(p, float3(-0.30, 0.75, 0), float3(0.30, -0.20, 0), 0.10, 0.24);
    float wing = length(p - float3(-0.05, -0.30, 0)) - 0.20;
    float under = sdSegment(p, float3(0.28, -0.40, 0), float3(-0.10, -0.50, 0), 0.10);
    return min(bridge, min(wing, under));
}

ORB_FORMA(naso)
