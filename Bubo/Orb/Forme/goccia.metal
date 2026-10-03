#include "../OrbShading.h"

// Meteo · pioggia: a water drop, a round belly drawn up to a point, with a small highlight.
static float goccia(float3 p, float) {
    float drop = sdRoundCone(p, float3(0, -0.25, 0), float3(0, 0.70, 0), 0.45, 0.02);
    float shine = length(p - float3(-0.18, -0.20, 0.41)) - 0.05;
    return min(drop, shine);
}

ORB_FORMA(goccia)
