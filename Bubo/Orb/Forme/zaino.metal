#include "../OrbShading.h"

// Viaggi · zaino in spalla: a backpack with a top handle, a front pocket, two side pockets and a zip line.
static float zaino(float3 p, float) {
    float body = sdRoundBox(p - float3(0, -0.1, 0), float3(0.5, 0.55, 0.28), 0.18);
    float handle = sdTorusXY(p - float3(0, 0.5, 0), 0.17, 0.045);
    float front = sdRoundBox(p - float3(0, -0.4, 0.3), float3(0.36, 0.22, 0.08), 0.08);
    float sides = sdRoundBox(float3(abs(p.x), p.y, p.z) - float3(0.55, -0.3, 0), float3(0.1, 0.28, 0.18), 0.08);
    float zip = sdSegment(p, float3(-0.3, 0.12, 0.29), float3(0.3, 0.12, 0.29), 0.03);
    return min(min(body, handle), min(front, min(sides, zip)));
}

ORB_FORMA(zaino)
