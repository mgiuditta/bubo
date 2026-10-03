#include "../OrbShading.h"

// Meteo · inverno: a snowman, two spheres with a top hat, twig arms and a carrot nose.
static float pupazzo_di_neve(float3 p, float) {
    float d = length(p - float3(0, -0.45, 0)) - 0.45;
    d = min(d, length(p - float3(0, 0.20, 0)) - 0.30);
    d = min(d, sdCylinder(p - float3(0, 0.46, 0), 0.34, 0.03));
    d = min(d, sdCylinder(p - float3(0, 0.62, 0), 0.20, 0.18));
    float3 q = float3(abs(p.x), p.y, p.z);
    d = min(d, sdSegment(q, float3(0.40, -0.30, 0), float3(0.80, -0.05, 0), 0.035));
    return min(d, sdRoundCone(p, float3(0, 0.18, 0.2), float3(0, 0.14, 0.55), 0.06, 0.02));
}

ORB_FORMA(pupazzo_di_neve)
