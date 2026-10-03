#include "../OrbShading.h"

// Ricerca · raccolta di dati: a pickaxe, a crescent head on a straight handle.
static float piccone(float3 p, float) {
    float handle = sdSegment(p, float3(0, 0.55, 0), float3(0, -0.95, 0), 0.07);
    float knob = length(p - float3(0, -0.95, 0)) - 0.1;
    float3 m = float3(abs(p.x), p.y, p.z);
    float boss = length(p - float3(0, 0.58, 0)) - 0.14;
    float inner = sdRoundCone(m, float3(0, 0.6, 0), float3(0.5, 0.5, 0), 0.11, 0.08);
    float tip = sdRoundCone(m, float3(0.5, 0.5, 0), float3(0.85, 0.15, 0), 0.08, 0.03);
    return min(min(handle, knob), min(boss, min(inner, tip)));
}

ORB_FORMA(piccone)
