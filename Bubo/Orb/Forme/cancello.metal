#include "../OrbShading.h"

// Agente: a gate of two leaves with vertical bars between two posts; the leaves swing open a little now and then.
static float cancello(float3 p, float t) {
    float a = 0.4 * (0.5 - 0.5 * cos(t * 0.9));
    float3 q = float3(abs(p.x), p.y, p.z);
    float d = sdRoundBox(q - float3(0.80, -0.05, 0), float3(0.08, 0.68, 0.08), 0.03);
    d = min(d, length(q - float3(0.80, 0.72, 0)) - 0.10);
    float3 l = q - float3(0.72, 0, 0);
    l.xz = l.xz * rot(a);
    d = min(d, sdSegment(l, float3(-0.68, 0.5, 0), float3(0, 0.5, 0), 0.04));
    d = min(d, sdSegment(l, float3(-0.68, -0.5, 0), float3(0, -0.5, 0), 0.04));
    for (int i = 0; i < 5; i++) {
        float x = -0.05 - 0.15 * float(i);
        d = min(d, sdSegment(l, float3(x, -0.5, 0), float3(x, 0.5, 0), 0.03));
    }
    return d;
}

ORB_FORMA(cancello)
