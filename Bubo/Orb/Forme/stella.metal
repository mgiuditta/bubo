#include "../OrbShading.h"

// Ricerca: a five-pointed star with softened points, for ratings.
static float stella(float3 p, float) {
    return extrude(sdStar5(p.xy + float2(0, 0.075), 0.86, 0.45), p.z, 0.04) - 0.04;
}

ORB_FORMA(stella)
