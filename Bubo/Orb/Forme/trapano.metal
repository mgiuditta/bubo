#include "../OrbShading.h"

// Chat · fai da te: a cordless drill with a battery under the grip; the bit turns, its flute winding along it.
static float trapano(float3 p, float t) {
    p.x += 0.05;
    float2 q = p.xy;
    float body = udSegment2(q, float2(-0.35, 0.3), float2(0.25, 0.3)) - 0.2;
    float grip = udSegment2(q, float2(-0.1, 0.2), float2(-0.22, -0.55)) - 0.14;
    float battery = sdRoundBox2(q - float2(-0.28, -0.72), float2(0.3, 0.1), 0.05);
    float chuck = udSegment2(q, float2(0.4, 0.3), float2(0.55, 0.3)) - 0.13;
    float shape = extrude(min(min(body, grip), min(battery, chuck)), p.z, 0.08) - 0.04;
    float bit = sdSegment(p, float3(0.6, 0.3, 0), float3(0.98, 0.3, 0), 0.035);
    for (int i = 0; i < 4; i++) {
        float x = 0.68 + 0.08 * float(i);
        float a = t * 9.0 + x * 22.0;
        bit = min(bit, length(p - float3(x, 0.3 + 0.05 * sin(a), 0.05 * cos(a))) - 0.04);
    }
    return min(shape, bit);
}

ORB_FORMA(trapano)
