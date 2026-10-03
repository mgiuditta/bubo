#include "../OrbShading.h"

// Salute: a boxing glove, a big rounded fist with a thumb on the side and a short cuff.
static float guantone(float3 p, float) {
    float fist = sdRoundBox(p - float3(0, 0.2, 0), float3(0.48, 0.42, 0.36), 0.3);
    float thumb = sdSegment(p, float3(0.45, -0.1, 0.22), float3(0.55, 0.3, 0.22), 0.15);
    float cuff = sdRoundBox(p - float3(0, -0.52, 0), float3(0.3, 0.2, 0.28), 0.08);
    return min(fist, min(thumb, cuff));
}

ORB_FORMA(guantone)
