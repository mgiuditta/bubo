#include "../OrbShading.h"

// Ricerca: a shopping cart seen three-quarters: basket, handle, chassis and four wheels.
static float carrello(float3 p, float) {
    p.xz = p.xz * rot(0.5);
    const float s = 0.92;
    p /= s;
    float basket = extrude(sdQuad2(p.xy, float2(-0.55, 0.38), float2(0.72, 0.38), float2(0.50, -0.24), float2(-0.42, -0.24)), p.z, 0.28) - 0.03;
    float3 q = float3(p.x, p.y, abs(p.z));
    float post = sdSegment(q, float3(-0.55, 0.38, 0.28), float3(-0.82, 0.64, 0.28), 0.04);
    float bar = sdSegment(p, float3(-0.82, 0.64, -0.28), float3(-0.82, 0.64, 0.28), 0.05);
    float frame = sdSegment(q, float3(-0.40, -0.40, 0.24), float3(0.45, -0.40, 0.24), 0.04);
    float legs = min(sdSegment(q, float3(-0.38, -0.24, 0.24), float3(-0.38, -0.62, 0.24), 0.035),
                     sdSegment(q, float3(0.40, -0.24, 0.24), float3(0.40, -0.62, 0.24), 0.035));
    float wheels = min(length(q - float3(-0.38, -0.64, 0.24)) - 0.11, length(q - float3(0.40, -0.64, 0.24)) - 0.11);
    return min(min(min(basket, post), min(bar, frame)), min(legs, wheels)) * s;
}

ORB_FORMA(carrello)
