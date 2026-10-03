#include "../OrbShading.h"

// One slice of the pyramid between heights y0 and y1: a trapezoid of the triangle that narrows to y = 0.8.
static float piramideBand(float3 p, float y0, float y1) {
    float w0 = 0.8 * (0.8 - y0) / 1.5, w1 = 0.8 * (0.8 - y1) / 1.5;
    return extrude(sdQuad2(p.xy, float2(-w0, y0), float2(w0, y0), float2(w1, y1), float2(-w1, y1)), p.z, 0.16) - 0.02;
}

// Codice · verifica: a pyramid cut into three bands, with a gap between them: unit, integration, end-to-end.
static float piramide(float3 p, float) {
    return min(piramideBand(p, 0.26, 0.72), min(piramideBand(p, -0.2, 0.18), piramideBand(p, -0.7, -0.28)));
}

ORB_FORMA(piramide)
