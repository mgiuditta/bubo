#include "../OrbShading.h"

// Chat · conversazione: a highlighter pen on the slant, barrel, tapered neck and chisel tip.
static float evidenziatore(float3 p, float) {
    p.xy = p.xy * rot(0.6);
    p.y -= 0.08;
    float barrel = sdRoundBox(p - float3(0, -0.15, 0), float3(0.17, 0.4, 0.12), 0.07);
    float neck = sdCappedCone(p - float3(0, 0.4, 0), 0.15, 0.15, 0.08);
    float tip = sdRoundBox(p - float3(0, 0.62, 0), float3(0.06, 0.07, 0.04), 0.03);
    float clip = sdRoundBox(p - float3(0.0, -0.2, 0.15), float3(0.04, 0.28, 0.03), 0.02);
    return min(min(barrel, neck), min(tip, clip));
}

ORB_FORMA(evidenziatore)
