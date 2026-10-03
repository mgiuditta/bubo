#include "../OrbShading.h"

// Viaggi: a kick scooter in profile, a low deck, a slanted stem with handlebars and two small wheels.
static float monopattino(float3 p, float) {
    float deck = sdRoundBox(p - float3(0, -0.45, 0), float3(0.55, 0.05, 0.14), 0.03);
    float stem = sdSegment(p, float3(0.6, -0.65, 0), float3(0.4, 0.67, 0), 0.05);
    float bars = min(sdSegment(p, float3(0.28, 0.7, 0), float3(0.52, 0.7, 0), 0.05), sdSegment(p, float3(0.4, 0.7, -0.3), float3(0.4, 0.7, 0.3), 0.05));
    float wheels = min(extrude(length(p.xy - float2(0.6, -0.65)) - 0.12, p.z, 0.04), extrude(length(p.xy - float2(-0.58, -0.65)) - 0.12, p.z, 0.04)) - 0.04;
    float fender = sdSegment(p, float3(-0.58, -0.5, 0), float3(-0.35, -0.42, 0), 0.04);
    return min(min(deck, stem), min(bars, min(wheels, fender)));
}

ORB_FORMA(monopattino)
