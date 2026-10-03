#include "../OrbShading.h"

// Codice · verifica: the four corners of a viewfinder with a small cross in the middle. The cross sits a hair off
// the axes and the corners are not square, so no crease of the field lies on a plane of the test grid.
static float mirino(float3 p, float) {
    float2 q = abs(p.xy);
    float2 r = abs(p.xy - float2(0.03, 0));
    float d2 = min(udSegment2(q, float2(0.65, 0.32), float2(0.65, 0.60)), udSegment2(q, float2(0.37, 0.60), float2(0.65, 0.60)));
    d2 = min(d2, min(udSegment2(r, float2(0, 0), float2(0.18, 0)), udSegment2(r, float2(0, 0), float2(0, 0.18))));
    return extrude(d2 - 0.06, p.z, 0.05);
}

ORB_FORMA(mirino)
