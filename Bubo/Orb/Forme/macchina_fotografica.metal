#include "../OrbShading.h"

// Creativo · fotografia: a camera, wide body with a viewfinder hump, a shutter button and a round lens facing us.
static float macchina_fotografica(float3 p, float) {
    float body = sdRoundBox(p - float3(0, -0.10, 0), float3(0.75, 0.42, 0.22), 0.08);
    float hump = sdRoundBox(p - float3(-0.25, 0.38, 0), float3(0.28, 0.10, 0.18), 0.05);
    float button = sdCylinder(p - float3(0.45, 0.40, 0), 0.07, 0.05) - 0.02;
    float barrel = sdCylinder(float3(p.x, p.z - 0.30, p.y + 0.06), 0.32, 0.12) - 0.02;
    float ring = sdTorusXY(p - float3(0, -0.06, 0.42), 0.19, 0.04);
    float glass = length(p - float3(0, -0.06, 0.40)) - 0.15;
    return min(min(body, hump), min(button, min(barrel, min(ring, glass))));
}

ORB_FORMA(macchina_fotografica)
