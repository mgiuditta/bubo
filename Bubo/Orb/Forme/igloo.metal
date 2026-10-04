#include "../OrbShading.h"

// Viaggi · paesi nordici: an igloo, a dome of stacked ice blocks with a short tunnel for the entrance.
static float igloo(float3 p, float) {
    const float s = 0.85;
    p.x -= 0.05;
    p /= s;
    float3 d0 = p - float3(-0.25, 0, 0);
    const float ys[5] = { -0.8, -0.62, -0.44, -0.26, -0.08 };
    const float rs[5] = { 0.76, 0.73, 0.66, 0.54, 0.33 };
    float d = length(d0 - float3(0, 0.02, 0)) - 0.22;
    for (int i = 0; i < 5; i++) d = min(d, sdCylinder(d0 - float3(0, ys[i], 0), rs[i], 0.09));
    float tunnel = sdCylinder(float3(p.y + 0.62, p.x - 0.78, p.z), 0.26, 0.3);
    float lip = sdCylinder(float3(p.y + 0.62, p.x - 1.04, p.z), 0.3, 0.04);
    return min(d, min(tunnel, lip)) * s;
}

ORB_FORMA(igloo)
