#include "../OrbShading.h"

// Il gufo del Segno (Bubo bubo), seen from the front: the round disc of head and body, two ear tufts pushed
// outward, the V of the facial disc between them, two big eyes standing out of the face and a small beak.
static float gufo(float3 p, float) {
    const float round = 0.18;
    float disc = extrude(length(p.xy - float2(0, -0.05)) - 0.58 + round, p.z, 0.10) - round;
    float2 m = float2(abs(p.x), p.y); // the face is symmetric: one tuft, eye and arm of the V for both sides
    float3 q = float3(m, p.z);
    float tuft = sdRoundCone(q, float3(0.30, 0.38, 0), float3(0.58, 0.80, 0), 0.14, 0.04);
    float vee = sdSegment(q, float3(0.16, 0.46, 0.24), float3(0, 0.02, 0.27), 0.035);
    float eye = length(q - float3(0.22, 0.08, 0.20)) - 0.14;
    float beak = sdRoundCone(p, float3(0, -0.06, 0.26), float3(0, -0.20, 0.36), 0.06, 0.02);
    return min(min(disc, tuft), min(min(vee, eye), beak));
}

ORB_FORMA(gufo)
