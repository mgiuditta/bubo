#include "../OrbShading.h"

// Creativo: a deerstalker, a round crown on a band, with a visor at the front and one at the back.
static float cappello_detective(float3 p, float) {
    float crown = length(p - float3(0, 0.1, 0)) - 0.5;
    float band = sdCylinder(p - float3(0, -0.33, 0), 0.5, 0.07) - 0.02;
    float knot = length(p - float3(0, 0.62, 0)) - 0.07;
    float3 v = float3(abs(p.x) - 0.7, p.y + 0.45, p.z);
    v.xy = v.xy * rot(0.2);
    float visors = sdRoundBox(v, float3(0.28, 0.04, 0.28), 0.03);
    return min(min(crown, band), min(knot, visors));
}

ORB_FORMA(cappello_detective)
