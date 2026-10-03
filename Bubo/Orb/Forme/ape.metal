#include "../OrbShading.h"

// Chat · api e miele: a bee in profile, striped, with a head, feelers and two wings that hum.
static float ape(float3 p, float t) {
    p.y += 0.1;
    float body = sdSegment(p, float3(-0.28, -0.12, 0), float3(0.18, -0.12, 0), 0.32);
    float stripes = min(sdCylinder(float3(p.y + 0.12, p.x + 0.14, p.z), 0.345, 0.05),
                        sdCylinder(float3(p.y + 0.12, p.x - 0.06, p.z), 0.345, 0.05));
    float head = length(p - float3(0.46, -0.06, 0)) - 0.2;
    float eye = length(p - float3(0.55, 0.0, 0.14)) - 0.05;
    float feeler = sdSegment(p, float3(0.52, 0.1, 0), float3(0.66, 0.34, 0), 0.035);
    float sting = sdRoundCone(p, float3(-0.58, -0.12, 0), float3(-0.8, -0.12, 0), 0.06, 0.015);
    float buzz = 0.2 * sin(t * 16.0);
    float3 w1 = p - float3(-0.04, 0.2, -0.05);
    w1.xy = w1.xy * rot(0.5 + buzz);
    float3 w2 = p - float3(0.08, 0.2, -0.05);
    w2.xy = w2.xy * rot(-0.15 - buzz);
    float wings = min(sdSegment(w1, float3(0, 0, 0), float3(0, 0.55, 0), 0.13), sdSegment(w2, float3(0, 0, 0), float3(0, 0.45, 0), 0.11));
    return min(min(min(body, stripes), min(head, eye)), min(min(feeler, sting), wings));
}

ORB_FORMA(ape)
