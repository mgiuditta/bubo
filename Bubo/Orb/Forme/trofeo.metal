#include "../OrbShading.h"

// Ricerca: a cup with two handles on a stem and a base.
static float trofeo(float3 p, float) {
    float bowl = sdRoundCone(p, float3(0, 0.0, 0), float3(0, 0.50, 0), 0.16, 0.42);
    float stem = sdCylinder(p - float3(0, -0.22, 0), 0.07, 0.15);
    float base = sdRoundBox(p - float3(0, -0.65, 0), float3(0.35, 0.10, 0.20), 0.03);
    float3 q = float3(abs(p.x), p.y, p.z);
    float handle = sdTorusXY(q - float3(0.50, 0.38, 0), 0.20, 0.04);
    return min(min(bowl, stem), min(base, handle));
}

ORB_FORMA(trofeo)
