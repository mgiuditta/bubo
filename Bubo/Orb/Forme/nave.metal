#include "../OrbShading.h"

// Viaggi: a ship with two funnels, rocking on the swell.
static float nave(float3 p, float t) {
    p.xy = p.xy * rot(-0.09 * sin(t * 1.7));
    float2 q = p.xy + float2(0, 0.20);
    float hull = sdQuad2(q, float2(-0.85, 0.0), float2(0.92, 0.0), float2(0.55, -0.45), float2(-0.62, -0.45));
    float deck = sdRoundBox2(q - float2(-0.05, 0.20), float2(0.50, 0.15), 0.04);
    float bridge = sdRoundBox2(q - float2(-0.10, 0.45), float2(0.30, 0.10), 0.04);
    float funnels = min(sdRoundBox2(q - float2(-0.22, 0.70), float2(0.08, 0.15), 0.03),
                        sdRoundBox2(q - float2(0.14, 0.70), float2(0.08, 0.15), 0.03));
    return extrude(min(min(hull, deck), min(bridge, funnels)), p.z, 0.15) - 0.03;
}

ORB_FORMA(nave)
