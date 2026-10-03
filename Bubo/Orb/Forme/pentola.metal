#include "../OrbShading.h"

// Chat · cucina: a pot with two handles and a lid with a knob; the lid hops now and then.
static float pentola(float3 p, float t) {
    float body = sdCylinder(p - float3(0, -0.15, 0), 0.47, 0.31) - 0.05;
    float3 q = float3(abs(p.x), p.y, p.z);
    float handle = sdRoundBox(q - float3(0.62, 0.05, 0), float3(0.12, 0.05, 0.05), 0.03);
    float hop = 0.07 * pow(max(sin(t * 7.0), 0.0), 2.0) * step(0.0, sin(t * 1.1));
    float3 l = p - float3(0, hop, 0);
    float lid = sdCylinder(l - float3(0, 0.25, 0), 0.52, 0.05) - 0.03;
    float knob = length(l - float3(0, 0.37, 0)) - 0.08;
    return min(min(body, handle), min(lid, knob));
}

ORB_FORMA(pentola)
