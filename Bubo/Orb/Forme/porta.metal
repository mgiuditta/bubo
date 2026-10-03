#include "../OrbShading.h"

// Mail · benvenuto: a door in its frame, ajar; the leaf swings a little more open and back on its hinge.
static float porta(float3 p, float t) {
    float f = sdRoundBox2(p.xy - float2(-0.52, 0), float2(0.1, 0.92), 0.0);
    f = min(f, sdRoundBox2(p.xy - float2(0.52, 0), float2(0.1, 0.92), 0.0));
    f = min(f, sdRoundBox2(p.xy - float2(0, 0.84), float2(0.62, 0.08), 0.0));
    f = min(f, sdRoundBox2(p.xy - float2(0, -0.84), float2(0.62, 0.06), 0.0));
    float frame = extrude(f, p.z, 0.09) - 0.01;
    const float hinge = -0.42;
    float3 l = p;
    l.xz = (p.xz - float2(hinge, 0)) * rot(0.5 + 0.12 * sin(t * 0.9));
    float leaf = sdRoundBox(float3(l.x - 0.40, l.y, l.z), float3(0.38, 0.74, 0.04), 0.02);
    float panel = sdRoundBox(float3(l.x - 0.40, l.y - 0.25, l.z - 0.05), float3(0.2, 0.3, 0.015), 0.01);
    float knob = length(float3(l.x - 0.68, l.y + 0.05, l.z - 0.09)) - 0.06;
    return min(min(frame, leaf), min(panel, knob));
}

ORB_FORMA(porta)
