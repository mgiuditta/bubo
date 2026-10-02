#include "../OrbShading.h"

// Musica: two beamed eighth notes, hopping to a slow beat.
static float nota(float3 p, float t) {
    p.y -= 0.03 * abs(sin(t * 2.6));
    const float2 tilt = float2(0.906, 0.423) * 0.09;   // the heads lean 25°
    float3 h1 = float3(-0.38, -0.52, 0), h2 = float3(0.34, -0.40, 0);
    float3 d = float3(tilt, 0);
    float heads = min(sdSegment(p, h1 - d, h1 + d, 0.17), sdSegment(p, h2 - d, h2 + d, 0.17));
    float stems = min(sdSegment(p, float3(-0.22, -0.48, 0), float3(-0.22, 0.56, 0), 0.045),
                      sdSegment(p, float3(0.50, -0.36, 0), float3(0.50, 0.68, 0), 0.045));
    float beam = sdSegment(p, float3(-0.22, 0.56, 0), float3(0.50, 0.68, 0), 0.075);
    return min(heads, min(stems, beam));
}

ORB_FORMA(nota)
