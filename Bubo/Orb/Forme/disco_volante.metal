#include "../OrbShading.h"

// Creativo: a flying saucer, a double cone with a glass dome and three lights under the rim; it bobs and tilts in the air.
static float disco_volante(float3 p, float t) {
    p.y -= 0.06 * sin(t * 1.8);
    p.xy = p.xy * rot(0.1 * sin(t * 1.2));
    float lower = sdCappedCone(p - float3(0, -0.12, 0), 0.12, 0.4, 0.82);
    float upper = sdCappedCone(p - float3(0, 0.07, 0), 0.07, 0.82, 0.45);
    float dome = length(p - float3(0, 0.2, 0)) - 0.3;
    float lights = length(p - float3(0, -0.2, 0.47)) - 0.07;
    lights = min(lights, length(float3(abs(p.x), p.y, p.z) - float3(0.4, -0.2, 0.25)) - 0.07);
    return min(min(lower, upper), min(dome, lights));
}

ORB_FORMA(disco_volante)
