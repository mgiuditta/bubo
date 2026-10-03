#include "../OrbShading.h"

// Chat: a round picnic basket, wider at the top, with a flat lid and an arched handle.
static float cestino_picnic(float3 p, float) {
    p.y -= 0.03;
    float body = sdCappedCone(p - float3(0, -0.32, 0), 0.32, 0.5, 0.62);
    float lid = sdCylinder(p - float3(0, 0.05, 0), 0.63, 0.02) - 0.03;
    float handle = sdTorusXY(p - float3(0, 0.07, 0), 0.45, 0.045);
    return min(min(body, lid), handle);
}

ORB_FORMA(cestino_picnic)
