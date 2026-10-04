#include "../OrbShading.h"

// Viaggi: a trolley case with ribs on its front, wheels and the handle pulled out.
static float valigia(float3 p, float) {
    float3 q = float3(abs(p.x), p.y, p.z);
    float body = sdRoundBox(p - float3(0, -0.2, 0), float3(0.45, 0.50, 0.20), 0.10);
    float rib = sdRoundBox(q - float3(0.18, -0.2, 0), float3(0.03, 0.38, 0.22), 0.02);
    float rod = sdSegment(q, float3(0.25, 0.25, 0), float3(0.25, 0.72, 0), 0.035);
    float grip = sdSegment(p, float3(-0.25, 0.76, 0), float3(0.25, 0.76, 0), 0.05);
    float wheel = length(q - float3(0.30, -0.74, 0.10)) - 0.07;
    return min(min(body, rib), min(min(rod, grip), wheel));
}

ORB_FORMA(valigia)
