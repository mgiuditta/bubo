#include "../OrbShading.h"

// Salute: a bathroom scale seen from above: a square slab with a dial and needle at the top and two foot pads.
static float pesapersone(float3 p, float) {
    float slab = extrude(sdRoundBox2(p.xy, float2(0.68), 0.16), p.z, 0.05) - 0.03;
    float dial = sdTorusXY(p - float3(0, 0.36, 0.08), 0.24, 0.03);
    float needle = sdSegment(p, float3(0, 0.36, 0.09), float3(0.11, 0.50, 0.09), 0.025);
    float pads = sdRoundBox(float3(abs(p.x) - 0.24, p.y + 0.30, p.z - 0.08), float3(0.14, 0.20, 0.012), 0.01);
    return min(min(slab, dial), min(needle, pads));
}

ORB_FORMA(pesapersone)
