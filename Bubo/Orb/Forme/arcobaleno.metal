#include "../OrbShading.h"

// Distance to the upper half of the circle of radius R around the origin.
static float arcobalenoArc(float2 q, float R) {
    return q.y >= 0.0 ? abs(length(q) - R) : min(length(q - float2(R, 0)), length(q + float2(R, 0)));
}

// Meteo: a rainbow, three concentric bands with a gap between them.
static float arcobaleno(float3 p, float) {
    p.y += 0.46;
    float d = min(arcobalenoArc(p.xy, 0.85), min(arcobalenoArc(p.xy, 0.60), arcobalenoArc(p.xy, 0.35)));
    return extrude(d - 0.05, p.z, 0.04) - 0.04;
}

ORB_FORMA(arcobaleno)
