#include "../OrbShading.h"

// Musica: a turntable seen from above: a base, a record with a ridge across its label that turns, and the tonearm on a post past the base.
static float giradischi(float3 p, float t) {
    p.yz = p.yz * rot(-0.7);
    float d = sdRoundBox(p, float3(0.72, 0.10, 0.62), 0.05);
    float3 c = float3(-0.12, 0.14, 0.02);
    d = min(d, sdCylinder(p - c, 0.50, 0.035));
    d = min(d, sdCylinder(p - c - float3(0, 0.04, 0), 0.14, 0.03));
    float2 dir = float2(cos(t * 3.0), sin(t * 3.0)) * 0.34;
    d = min(d, sdSegment(p, c + float3(dir.x, 0.05, dir.y), c + float3(-dir.x, 0.05, -dir.y), 0.03));
    d = min(d, sdCylinder(p - float3(0.86, 0.20, -0.30), 0.09, 0.14));
    d = min(d, sdSegment(p, float3(0.86, 0.32, -0.30), float3(0.35, 0.25, 0.28), 0.03));
    return min(d, sdRoundBox(p - float3(0.32, 0.24, 0.32), float3(0.04, 0.02, 0.06), 0.01));
}

ORB_FORMA(giradischi)
