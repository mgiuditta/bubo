#include "../OrbShading.h"

// One oval link lying in the plane of q, thickness along w: a stadium of half-length 0.22 and radius 0.19, a tube of 0.065.
static float catenaLink(float2 q, float w) {
    float d = udSegment2(q, float2(-0.22, 0), float2(0.22, 0)) - 0.19;
    return length(float2(abs(d), w)) - 0.065;
}

// Codice: three oval links of a chain in a row, the middle one turned a quarter so they interlock; the chain lies diagonal.
static float catena(float3 p, float) {
    p.xy = p.xy * rot(0.45);
    float a = catenaLink(p.xy - float2(-0.55, 0), p.z);
    float b = catenaLink(float2(p.x, p.z), p.y);
    float c = catenaLink(p.xy - float2(0.55, 0), p.z);
    return min(a, min(b, c));
}

ORB_FORMA(catena)
