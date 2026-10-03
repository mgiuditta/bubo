#include "../OrbShading.h"

// Tempo: a two-tier cake with three candles; the flames tremble.
static float torta(float3 p, float t) {
    p.yz = p.yz * rot(-0.25);
    p.y -= 0.13;
    float d = min(sdCylinder(p - float3(0, -0.50, 0), 0.65, 0.17), sdCylinder(p - float3(0, -0.155, 0), 0.42, 0.155));
    for (int i = 0; i < 3; i++) {
        float x = -0.2 + 0.2 * float(i);
        float k = float(i) * 2.1;
        d = min(d, sdCylinder(p - float3(x, 0.12, 0), 0.04, 0.12));
        float3 flame = float3(x + 0.025 * sin(t * 9.0 + k), 0.34, 0);
        d = min(d, length(p - flame) - 0.065 * (1.0 + 0.15 * sin(t * 13.0 + k)));
    }
    return d;
}

ORB_FORMA(torta)
