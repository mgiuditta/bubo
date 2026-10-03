#include "../OrbShading.h"

// Agente: a drawing pin leaning to the right, a round flat head over a short neck and a sharp needle.
static float puntina(float3 p, float) {
    p.xy = p.xy * rot(0.5);
    float head = sdCylinder(p - float3(0, 0.72, 0), 0.4, 0.07) - 0.02;
    float neck = sdCylinder(p - float3(0, 0.52, 0), 0.2, 0.13);
    float pin = sdCappedCone(p - float3(0, -0.16, 0), 0.55, 0.02, 0.12);
    return min(min(head, neck), pin);
}

ORB_FORMA(puntina)
