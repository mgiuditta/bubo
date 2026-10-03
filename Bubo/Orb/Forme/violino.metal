#include "../OrbShading.h"

// Musica · archi: a violin with two bouts, bridge, f-holes, neck and scroll, and its bow beside it; the bow slides to and fro.
static float violino(float3 p, float t) {
    float3 q = p + float3(0.20, 0.19, 0);
    float lower = extrude(length(q.xy - float2(0, -0.35)) - 0.23, q.z, 0.04) - 0.04;
    float upper = extrude(length(q.xy - float2(0, 0.05)) - 0.16, q.z, 0.04) - 0.04;
    float neck = sdRoundBox(q - float3(0, 0.55, 0), float3(0.04, 0.40, 0.03), 0.015);
    float scroll = length(q - float3(0, 1.0, 0)) - 0.07;
    float bridge = sdRoundBox(q - float3(0, -0.30, 0.09), float3(0.10, 0.02, 0.02), 0.01);
    float3 m = float3(abs(q.x), q.y, q.z);
    float fhole = sdSegment(m, float3(0.09, -0.18, 0.09), float3(0.09, -0.38, 0.09), 0.015);
    float dy = 0.2 * sin(t * 1.5);
    float bow = sdSegment(q, float3(0.62, -0.70 + dy, 0), float3(0.62, 0.60 + dy, 0), 0.025);
    float frog = length(q - float3(0.62, -0.70 + dy, 0)) - 0.05;
    return min(min(min(lower, upper), min(neck, scroll)), min(min(bridge, fhole), min(bow, frog)));
}

ORB_FORMA(violino)
