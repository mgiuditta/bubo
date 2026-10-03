#include "../OrbShading.h"

// Codice · rilascio: a waste bin, a tapered body with vertical grooves, a lid and a handle.
static float cestino(float3 p, float) {
    float body = sdCappedCone(p - float3(0, -0.15, 0), 0.55, 0.38, 0.45);
    float lid = sdCylinder(p - float3(0, 0.46, 0), 0.5, 0.06);
    float grip = sdSegment(p, float3(-0.14, 0.64, 0), float3(0.14, 0.64, 0), 0.06);
    float posts = min(sdSegment(p, float3(-0.14, 0.52, 0), float3(-0.14, 0.64, 0), 0.05),
                      sdSegment(p, float3(0.14, 0.52, 0), float3(0.14, 0.64, 0), 0.05));
    float d = min(min(body, lid), min(grip, posts));
    for (int i = 0; i < 4; i++) {
        float x = -0.225 + 0.15 * float(i);
        float z = sqrt(0.41 * 0.41 - x * x) - 0.01;
        d = min(d, sdSegment(p, float3(x, -0.5, z), float3(x, 0.15, z), 0.04));
    }
    return d;
}

ORB_FORMA(cestino)
