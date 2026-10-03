#include "../OrbShading.h"

// Codice · infrastruttura: a cylindrical battery with the pole on top, a ring around the foot and a plus on its face.
static float pila(float3 p, float) {
    float body = sdCylinder(p - float3(0, -0.1, 0), 0.42, 0.55);
    float pole = sdCylinder(p - float3(0, 0.55, 0), 0.16, 0.1);
    float ring = sdCylinder(p - float3(0, -0.4, 0), 0.45, 0.07);
    float plus = min(sdSegment(p, float3(-0.13, 0.15, 0.4), float3(0.13, 0.15, 0.4), 0.045),
                     sdSegment(p, float3(0, 0.02, 0.4), float3(0, 0.28, 0.4), 0.045));
    return min(min(body, pole), min(ring, plus));
}

ORB_FORMA(pila)
