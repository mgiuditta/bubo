#include "../OrbShading.h"

// Chat · spezie: a curved chilli pepper from the green cap down to its tip.
static float peperoncino(float3 p, float) {
    float d = sdRoundCone(p, float3(-0.35, 0.62, 0), float3(-0.2, 0.2, 0), 0.17, 0.17);
    d = min(d, sdRoundCone(p, float3(-0.2, 0.2, 0), float3(0.05, -0.2, 0), 0.17, 0.14));
    d = min(d, sdRoundCone(p, float3(0.05, -0.2, 0), float3(0.4, -0.55, 0), 0.14, 0.09));
    d = min(d, sdRoundCone(p, float3(0.4, -0.55, 0), float3(0.72, -0.66, 0), 0.09, 0.02));
    float cap = length(p - float3(-0.37, 0.7, 0)) - 0.15;
    float stem = sdSegment(p, float3(-0.38, 0.75, 0), float3(-0.52, 0.95, 0), 0.05);
    return min(d, min(cap, stem));
}

ORB_FORMA(peperoncino)
