#include "../OrbShading.h"

// Codice · scrittura: a pencil leaning tip down to the left, rubber on top; it scribbles a short mark back and forth.
static float matita(float3 p, float t) {
    const float3 u = float3(0.7071, 0.7071, 0), w = float3(0.7071, -0.7071, 0);
    const float3 rest = float3(-0.70, -0.70, 0);       // where the tip touches the paper
    float mark = sdSegment(p, rest - w * 0.13 - u * 0.05, rest + w * 0.13 - u * 0.05, 0.03);
    float3 tip = rest + w * 0.09 * sin(t * 2.2);
    float lead = sdRoundCone(p, tip + u * 0.02, tip + u * 0.14, 0.02, 0.055);
    float wood = sdRoundCone(p, tip + u * 0.12, tip + u * 0.42, 0.05, 0.16);
    float body = sdSegment(p, tip + u * 0.44, tip + u * 1.40, 0.16);
    float ferrule = sdSegment(p, tip + u * 1.42, tip + u * 1.56, 0.175);
    float rubber = sdSegment(p, tip + u * 1.60, tip + u * 1.70, 0.15);
    return min(min(mark, lead), min(min(wood, body), min(ferrule, rubber)));
}

ORB_FORMA(matita)
