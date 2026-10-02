#include "../OrbShading.h"

// Meteo: a cloud. Three puffs on a flat-bottomed base; the puffs bob slowly, out of step.
static float nuvola(float3 p, float t) {
    p.y += 0.09;
    float base = sdRoundBox(p - float3(0, -0.24, 0), float3(0.62, 0.24, 0.27), 0.24);
    float left = length(p - float3(-0.40, 0.04 + 0.02 * sin(t * 0.9), 0)) - 0.36;
    float top = length(p - float3(0.06, 0.22 + 0.025 * sin(t * 0.9 + 2.1), 0)) - 0.48;
    float right = length(p - float3(0.50, 0.0 + 0.02 * sin(t * 0.9 + 4.2), 0)) - 0.32;
    return min(min(base, left), min(top, right));
}

ORB_FORMA(nuvola)
