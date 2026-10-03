#include "../OrbShading.h"

// Viaggi: a motorcycle in profile, two wheels, a frame with engine, tank and seat, a fork and handlebars.
static float motocicletta(float3 p, float) {
    p.y -= 0.13;
    float wheels = min(sdTorusXY(p - float3(-0.55, -0.4, 0), 0.3, 0.07), sdTorusXY(p - float3(0.55, -0.4, 0), 0.3, 0.07));
    float hubs = min(length(p - float3(-0.55, -0.4, 0)) - 0.08, length(p - float3(0.55, -0.4, 0)) - 0.08);
    float engine = sdRoundBox(p - float3(0, -0.28, 0), float3(0.2, 0.17, 0.1), 0.05);
    float tank = sdSegment(p, float3(-0.2, 0.1, 0), float3(0.25, 0.15, 0), 0.15);
    float seat = sdSegment(p, float3(-0.72, 0.0, 0), float3(-0.25, 0.04, 0), 0.08);
    float frame = min(sdSegment(p, float3(-0.55, -0.4, 0), float3(-0.2, 0.0, 0), 0.05), sdSegment(p, float3(0.55, -0.4, 0), float3(0.42, 0.3, 0), 0.05));
    float bars = sdSegment(p, float3(0.42, 0.3, 0), float3(0.28, 0.42, 0), 0.04);
    float light = length(p - float3(0.5, 0.12, 0)) - 0.09;
    return min(min(wheels, hubs), min(min(engine, tank), min(min(seat, frame), min(bars, light))));
}

ORB_FORMA(motocicletta)
