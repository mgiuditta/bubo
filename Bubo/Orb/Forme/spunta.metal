#include "../OrbShading.h"

// Agente · fatto: a big check mark, two thick strokes with rounded ends.
static float spunta(float3 p, float) {
    float short_ = sdSegment(p, float3(-0.60, -0.05, 0), float3(-0.20, -0.45, 0), 0.17);
    float long_ = sdSegment(p, float3(-0.20, -0.45, 0), float3(0.65, 0.50, 0), 0.17);
    return min(short_, long_);
}

ORB_FORMA(spunta)
