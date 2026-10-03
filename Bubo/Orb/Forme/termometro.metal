#include "../OrbShading.h"

// Meteo: a thermometer, tube and bulb with four ticks; the mercury column bulges from the front and rises and falls.
static float termometro(float3 p, float t) {
    float top = 0.20 + 0.32 * sin(t * 0.9);
    float tube = sdSegment(p, float3(0, -0.35, 0), float3(0, 0.70, 0), 0.14);
    float bulb = length(p - float3(0, -0.62, 0)) - 0.28;
    float mercury = sdSegment(p, float3(0, -0.55, 0.11), float3(0, top, 0.11), 0.065);
    float d = min(tube, min(bulb, mercury));
    for (int i = 0; i < 4; i++) {
        float y = 0.2 * float(i);
        d = min(d, sdSegment(p, float3(0.20, y, 0), float3(0.36, y, 0), 0.03));
    }
    return d;
}

ORB_FORMA(termometro)
