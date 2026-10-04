#include "../OrbShading.h"

// Chat · natura: an astronaut helmet, a round dome with a bulging visor, side pods and a neck ring.
static float casco_astronauta(float3 p, float) {
    float dome = length(p - float3(0, 0.12, 0)) - 0.62;
    float visor = sdRoundBox(p - float3(0, 0.18, 0.58), float3(0.36, 0.22, 0.15), 0.15);
    float ring = length(float2(length(p.xz) - 0.5, p.y + 0.5)) - 0.11;
    float pods = length(float3(abs(p.x) - 0.66, p.y - 0.12, p.z)) - 0.13;
    return min(min(dome, visor), min(ring, pods));
}

ORB_FORMA(casco_astronauta)
