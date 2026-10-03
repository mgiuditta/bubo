#include "../OrbShading.h"

// The exact 2D triangle a b c.
static float avvisoTriangle(float2 p, float2 a, float2 b, float2 c) {
    float2 e0 = b - a, e1 = c - b, e2 = a - c;
    float2 v0 = p - a, v1 = p - b, v2 = p - c;
    float2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
    float2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
    float2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);
    float s = sign(e0.x * e2.y - e0.y * e2.x);
    float2 d = min(min(float2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
                       float2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))),
                   float2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));
    return -sqrt(d.x) * sign(d.y);
}

// Codice · errori: a triangle with rounded corners and a raised exclamation mark.
static float avviso(float3 p, float) {
    float tri = extrude(avvisoTriangle(p.xy, float2(-0.70, -0.50), float2(0.70, -0.50), float2(0, 0.72)), p.z, 0.06) - 0.10;
    float bar = sdSegment(p, float3(0, 0.28, 0.17), float3(0, -0.05, 0.17), 0.07);
    float dot_ = length(p - float3(0, -0.27, 0.17)) - 0.08;
    return min(tri, min(bar, dot_));
}

ORB_FORMA(avviso)
