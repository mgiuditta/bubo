#include "../OrbShading.h"

// Chat · natura: a monkey sitting seen from the front, round ears, long arms, tail curled at its side.
static float scimmia(float3 p, float) {
    p.x += 0.15;
    p.y -= 0.15;
    float head = length(p - float3(0, 0.3, 0)) - 0.3;
    float3 q = float3(abs(p.x), p.y, p.z);
    float ears = length(q - float3(0.33, 0.32, 0)) - 0.13;
    float muzzle = length(p - float3(0, 0.18, 0.2)) - 0.14;
    float body = sdRoundCone(p, float3(0, -0.5, 0), float3(0, -0.05, 0), 0.32, 0.22);
    float arms = sdSegment(q, float3(0.26, -0.08, 0), float3(0.46, -0.45, 0), 0.08);
    float feet = length(q - float3(0.22, -0.8, 0.05)) - 0.12;
    float tail = sdTorusXY(p - float3(0.5, -0.5, 0), 0.2, 0.06);
    return min(min(min(head, ears), min(muzzle, body)), min(min(arms, feet), tail));
}

ORB_FORMA(scimmia)
