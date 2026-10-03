#include "../OrbShading.h"

// Codice · verifica: a vertical traffic light with three round lamps; they light up in turn, the lit one swells.
static float semaforo(float3 p, float t) {
    float d = sdRoundBox(p, float3(0.3, 0.6, 0.18), 0.1);
    d = min(d, sdCylinder(p - float3(0, -0.8, 0), 0.08, 0.15));
    float phase = fract(t / 3.0) * 3.0;
    for (int i = 0; i < 3; i++) {
        float lit = pulse(phase, float(i) + 0.5, 0.55);
        d = min(d, length(p - float3(0, 0.36 - 0.36 * float(i), 0.16)) - (0.15 + 0.1 * lit));
    }
    return d;
}

ORB_FORMA(semaforo)
