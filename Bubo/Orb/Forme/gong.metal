#include "../OrbShading.h"

// Musica: a round gong with a boss and a rim, hung by two cords from a frame; it shivers in bursts.
static float gong(float3 p, float t) {
    float3 q = p;
    q.x += 0.02 * sin(t * 38.0) * (0.5 + 0.5 * sin(t * 1.5));
    const float3 c = float3(0, -0.05, 0);
    float disc = extrude(length(q.xy - c.xy) - 0.45, q.z, 0.06) - 0.03;
    float rim = sdTorusXY(q - c, 0.47, 0.045);
    float boss = length(q - c - float3(0, 0, 0.06)) - 0.15;
    float3 f = float3(abs(p.x), p.y, p.z);
    float frame = min(sdSegment(f, float3(0.7, -0.8, 0), float3(0.7, 0.74, 0), 0.05),
                      sdSegment(p, float3(-0.7, 0.74, 0), float3(0.7, 0.74, 0), 0.05));
    float cords = sdSegment(f, float3(0.3, 0.74, 0), float3(0.2, 0.38, 0), 0.03);
    return min(min(disc, rim), min(boss, min(frame, cords)));
}

ORB_FORMA(gong)
