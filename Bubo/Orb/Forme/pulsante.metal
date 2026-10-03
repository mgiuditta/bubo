#include "../OrbShading.h"

// Agente: a big round button on a low base, seen a little from above; it sinks and comes back up.
static float pulsante(float3 p, float t) {
    p.yz = p.yz * rot(-0.5);
    float press = 0.14 * pulse(fract(t / 2.6), 0.3, 0.16);
    float base = sdCylinder(p - float3(0, -0.45, 0), 0.64, 0.04) - 0.06;
    float button = sdCylinder(p - float3(0, -0.16 - press, 0), 0.40, 0.14) - 0.06;
    return min(base, button);
}

ORB_FORMA(pulsante)
