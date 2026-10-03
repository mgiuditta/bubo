#include "../OrbShading.h"

// Creativo · storie fantastiche: a dragon in profile facing right, curled tail, horn and a wing that beats.
static float drago(float3 p, float t) {
    float d = sdRoundCone(p, float3(-0.85, -0.45, 0), float3(-0.5, -0.5, 0), 0.03, 0.10);
    d = min(d, sdRoundCone(p, float3(-0.5, -0.5, 0), float3(-0.1, -0.3, 0), 0.10, 0.20));
    d = min(d, sdRoundCone(p, float3(-0.1, -0.3, 0), float3(0.2, 0.0, 0), 0.20, 0.22));
    d = min(d, sdRoundCone(p, float3(0.2, 0.0, 0), float3(0.38, 0.35, 0), 0.22, 0.14));
    d = min(d, sdRoundCone(p, float3(0.38, 0.35, 0), float3(0.55, 0.5, 0), 0.14, 0.17));
    d = min(d, sdRoundCone(p, float3(0.55, 0.5, 0), float3(0.8, 0.45, 0), 0.17, 0.08));
    float horn = sdSegment(p, float3(0.5, 0.65, 0), float3(0.35, 0.9, 0), 0.03);
    const float2 shoulder = float2(0, 0.15);
    float3 q = p;
    q.xy = (p.xy - shoulder) * rot(0.2 * sin(t * 2.0)) + shoulder;
    float wing = extrude(sdQuad2(q.xy, shoulder, float2(-0.85, 0.5), float2(-0.55, 0.85), float2(-0.2, 0.95)), q.z, 0.04) - 0.01;
    float bones = min(sdSegment(q, float3(shoulder, 0), float3(-0.85, 0.5, 0), 0.035), sdSegment(q, float3(shoulder, 0), float3(-0.55, 0.85, 0), 0.035));
    return min(min(d, horn), min(wing, bones));
}

ORB_FORMA(drago)
