#include "../OrbShading.h"

// Salute · barba e rasatura: a safety razor, a long ridged handle under a wide head with the guard plate.
static float rasoio(float3 p, float) {
    p.y -= 0.05;
    float handle = sdCappedCone(p - float3(0, -0.4, 0), 0.45, 0.075, 0.095);
    float rings = min(sdCylinder(p - float3(0, -0.2, 0), 0.125, 0.03), min(sdCylinder(p - float3(0, -0.4, 0), 0.125, 0.03), sdCylinder(p - float3(0, -0.6, 0), 0.125, 0.03)));
    float neck = sdCylinder(p - float3(0, 0.12, 0), 0.07, 0.12);
    float plate = sdRoundBox(p - float3(0, 0.3, 0), float3(0.44, 0.04, 0.14), 0.02);
    float cap = sdRoundBox(p - float3(0, 0.46, 0), float3(0.5, 0.1, 0.17), 0.07);
    return min(min(handle, rings), min(neck, min(plate, cap)));
}

ORB_FORMA(rasoio)
