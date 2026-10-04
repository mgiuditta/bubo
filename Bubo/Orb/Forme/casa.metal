#include "../OrbShading.h"

// Finanza · casa e soldi: a little house with a gabled roof, a chimney and a door on its front.
static float casa(float3 p, float) {
    float walls = extrude(sdRoundBox2(p.xy - float2(0, -0.35), float2(0.55, 0.35), 0.0), p.z, 0.3);
    float2 a = float2(-0.75, 0), b = float2(0.75, 0), c = float2(0, 0.6);
    float roof = extrude(sdQuad2(p.xy, a, b, c, 0.5 * (c + a)), p.z, 0.36) - 0.02;
    float chimney = extrude(sdRoundBox2(p.xy - float2(0.4, 0.55), float2(0.1, 0.25), 0.0), p.z, 0.1);
    float door = extrude(sdRoundBox2(p.xy - float2(0, -0.5), float2(0.12, 0.2), 0.0), p.z - 0.3, 0.05);
    return min(min(walls, roof), min(chimney, door));
}

ORB_FORMA(casa)
