#include "../OrbShading.h"

// Mail: a closed envelope, its flap drawn as a raised V on the front.
static float busta(float3 p, float) {
    float body = sdRoundBox(p, float3(0.84, 0.56, 0.08), 0.05);
    float3 q = float3(abs(p.x), p.y, p.z);
    float flap = sdSegment(q, float3(0.74, 0.46, 0.10), float3(0.0, -0.06, 0.10), 0.05);
    return min(body, flap);
}

ORB_FORMA(busta)
