#include "../OrbShading.h"

// Salute · corpo: a steaming cup on its saucer, with a handle; the steam rises in wisps.
static float tazza(float3 p, float t) {
    float body = sdCappedCone(p - float3(0, -0.1, 0), 0.38, 0.3, 0.42);
    float rim = length(float2(length(p.xz) - 0.42, p.y - 0.28)) - 0.04;
    float handle = sdTorusXY(p - float3(0.45, -0.1, 0), 0.2, 0.06);
    float saucer = sdCylinder(p - float3(0, -0.58, 0), 0.62, 0.05);
    float d = min(min(body, rim), min(handle, saucer));
    for (int j = 0; j < 3; j++) {
        float phase = fract(t / 3.0 + float(j) * 0.33);
        float r = (0.05 + 0.03 * phase) * (1.0 - smoothstep(0.65, 1.0, phase));
        d = min(d, length(p - float3((float(j) - 1.0) * 0.17 + 0.05 * sin(phase * 8.0 + float(j) * 2.0), 0.4 + 0.5 * phase, 0)) - r);
    }
    return d;
}

ORB_FORMA(tazza)
