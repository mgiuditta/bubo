#include "../OrbShading.h"

// Musica · concerti dal vivo: a stage spotlight on a fork stand, its beam sweeping slowly across the stage.
static float riflettore(float3 p, float t) {
    const float2 pivot = float2(0.25, -0.15);
    float stand = sdSegment(p, float3(pivot, 0), float3(0.25, -0.75, 0), 0.06);
    float base = sdSegment(p, float3(-0.05, -0.8, 0), float3(0.55, -0.8, 0), 0.07);
    float yoke = sdTorusXY(p - float3(pivot, 0), 0.34, 0.035);
    float3 q = float3(p.xy - pivot, p.z);
    q.xy = q.xy * rot(0.85 + 0.25 * sin(t * 1.1)); // local +y is the beam's direction
    float lamp = sdCappedCone(q, 0.27, 0.17, 0.26);
    float beam = sdCappedCone(q - float3(0, 0.72, 0), 0.42, 0.2, 0.46);
    return min(min(stand, base), min(min(lamp, beam), yoke));
}

ORB_FORMA(riflettore)
