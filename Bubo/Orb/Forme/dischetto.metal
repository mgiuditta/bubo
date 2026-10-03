#include "../OrbShading.h"

// Codice · salvataggio: a floppy disk, a square with one corner cut, the shutter and the label raised on it.
static float dischetto(float3 p, float) {
    float body = min(sdQuad2(p.xy, float2(-0.7, -0.7), float2(0.7, -0.7), float2(0.7, 0.4), float2(-0.7, 0.4)),
                     sdQuad2(p.xy, float2(-0.7, 0.4), float2(0.7, 0.4), float2(0.42, 0.7), float2(-0.7, 0.7)));
    float d = extrude(body, p.z, 0.05) - 0.03;
    d = min(d, sdRoundBox(p - float3(0.05, 0.45, 0.10), float3(0.32, 0.22, 0.04), 0.02));
    return min(d, sdRoundBox(p - float3(0, -0.35, 0.10), float3(0.45, 0.28, 0.04), 0.02));
}

ORB_FORMA(dischetto)
