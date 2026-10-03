#include "../OrbShading.h"

// Creativo · ceramica: a pot-bellied vase with a narrow neck and two handles, turning like on a wheel.
static float vaso(float3 p, float t) {
    p.xz = p.xz * rot(t * 1.2);
    float d = length(p - float3(0, -0.25, 0)) - 0.50;
    d = min(d, sdCylinder(p - float3(0, 0.40, 0), 0.14, 0.25));
    d = min(d, sdCylinder(p - float3(0, 0.68, 0), 0.22, 0.04));
    d = min(d, sdCylinder(p - float3(0, -0.78, 0), 0.25, 0.04));
    return min(d, sdTorusXY(float3(abs(p.x) - 0.34, p.y - 0.34, p.z), 0.20, 0.05));
}

ORB_FORMA(vaso)
