#include "../OrbShading.h"

// Codice · algoritmi: a flowchart, a diamond over two boxes joined by lines.
static float diagramma(float3 p, float) {
    float d = sdQuad2(p.xy, float2(0, 0.9), float2(0.4, 0.55), float2(0, 0.2), float2(-0.4, 0.55));
    d = min(d, sdRoundBox2(p.xy - float2(-0.5, -0.55), float2(0.35, 0.22), 0.0));
    d = min(d, sdRoundBox2(p.xy - float2(0.5, -0.55), float2(0.35, 0.22), 0.0));
    d = min(d, udSegment2(p.xy, float2(0, 0.2), float2(0, -0.1)) - 0.035);
    d = min(d, udSegment2(p.xy, float2(-0.5, -0.1), float2(0.5, -0.1)) - 0.035);
    d = min(d, udSegment2(p.xy, float2(-0.5, -0.1), float2(-0.5, -0.33)) - 0.035);
    d = min(d, udSegment2(p.xy, float2(0.5, -0.1), float2(0.5, -0.33)) - 0.035);
    return extrude(d, p.z, 0.05) - 0.02;
}

ORB_FORMA(diagramma)
