#include "../OrbShading.h"

// Codice · scrittura: a drawing set square, a right triangle that is only a frame around its triangular hole.
// The right angle sits a little off the grid diagonal so no crease of the field lies on a plane of the test grid.
static float squadra(float3 p, float) {
    float tri = sdQuad2(p.xy, float2(-0.62, -0.55), float2(0, -0.55), float2(0.62, -0.55), float2(-0.62, 0.65));
    return extrude(abs(tri) - 0.07, p.z, 0.04);
}

ORB_FORMA(squadra)
