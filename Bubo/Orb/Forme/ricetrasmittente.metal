#include "../OrbShading.h"

// Agente · aggiornamenti: a walkie-talkie with a short antenna that sways, a speaker grille and a knob.
static float ricetrasmittente(float3 p, float t) {
    float body = sdRoundBox(p - float3(0, -0.2, 0), float3(0.3, 0.52, 0.14), 0.1);
    float3 a = p - float3(0.16, 0.3, 0);
    a.xy = a.xy * rot(-0.15 * sin(t * 2.2));
    float antenna = min(sdSegment(a, float3(0, 0, 0), float3(0, 0.5, 0), 0.05), length(a - float3(0, 0.52, 0)) - 0.07);
    float grille = 9.0;
    for (int i = 0; i < 3; i++) {
        float y = 0.24 - 0.12 * float(i);
        grille = min(grille, sdSegment(p, float3(-0.14, y, 0.15), float3(0.14, y, 0.15), 0.03));
    }
    float knob = sdCylinder(float3(p.x + 0.14, p.z - 0.14, p.y - 0.36), 0.06, 0.1);
    float screen = sdRoundBox(p - float3(0, -0.32, 0.15), float3(0.15, 0.1, 0.03), 0.02);
    return min(min(body, antenna), min(min(grille, knob), screen));
}

ORB_FORMA(ricetrasmittente)
