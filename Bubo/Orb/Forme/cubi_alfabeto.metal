#include "../OrbShading.h"

// Chat · lingue: three letter blocks, two below and one on top, each a little turned, with A, B and C raised on them.
static float cubi_alfabeto(float3 p, float) {
    // A, bottom left
    float3 a = float3((p.xy - float2(-0.33, -0.40)) * rot(-0.08), p.z);
    float d = sdRoundBox(a, float3(0.30, 0.30, 0.30), 0.04);
    d = min(d, sdSegment(a, float3(-0.12, -0.14, 0.31), float3(0, 0.14, 0.31), 0.03));
    d = min(d, sdSegment(a, float3(0, 0.14, 0.31), float3(0.12, -0.14, 0.31), 0.03));
    d = min(d, sdSegment(a, float3(-0.07, -0.04, 0.31), float3(0.07, -0.04, 0.31), 0.03));
    // B, bottom right
    float3 b = float3((p.xy - float2(0.33, -0.40)) * rot(0.10), p.z);
    d = min(d, sdRoundBox(b, float3(0.30, 0.30, 0.30), 0.04));
    d = min(d, sdSegment(b, float3(-0.08, -0.14, 0.31), float3(-0.08, 0.14, 0.31), 0.03));
    d = min(d, sdTorusXY(b - float3(-0.01, 0.07, 0.31), 0.07, 0.03));
    d = min(d, sdTorusXY(b - float3(-0.01, -0.07, 0.31), 0.07, 0.03));
    // C, on top
    float3 c = float3((p.xy - float2(0.0, 0.20)) * rot(0.15), p.z);
    d = min(d, sdRoundBox(c, float3(0.30, 0.30, 0.30), 0.04));
    d = min(d, sdSegment(c, float3(0.10, 0.12, 0.31), float3(-0.06, 0.12, 0.31), 0.03));
    d = min(d, sdSegment(c, float3(-0.06, 0.12, 0.31), float3(-0.06, -0.12, 0.31), 0.03));
    d = min(d, sdSegment(c, float3(-0.06, -0.12, 0.31), float3(0.10, -0.12, 0.31), 0.03));
    return d;
}

ORB_FORMA(cubi_alfabeto)
