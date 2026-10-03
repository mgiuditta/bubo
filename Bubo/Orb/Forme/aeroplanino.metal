#include "../OrbShading.h"

// The exact 2D triangle a b c.
static float aeroplaninoTriangle(float2 p, float2 a, float2 b, float2 c) {
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

// Mail · invio: a paper plane in profile, nose to the right, wing and keel folded on a raised crease; it glides forward and back.
static float aeroplanino(float3 p, float t) {
    float3 q = p - float3(0.2 * sin(t * 0.8), 0.05 * cos(t * 1.6), 0);
    q.xy = q.xy * rot(-0.05 * sin(t * 0.8));
    float wing = extrude(aeroplaninoTriangle(q.xy, float2(0.85, 0.05), float2(-0.80, 0.32), float2(-0.80, -0.05)), q.z, 0.03) - 0.02;
    float keel = extrude(aeroplaninoTriangle(q.xy, float2(0.85, 0.05), float2(-0.80, -0.05), float2(-0.45, -0.32)), q.z, 0.03) - 0.02;
    float crease = sdSegment(q, float3(0.85, 0.05, 0.03), float3(-0.80, -0.05, 0.03), 0.03);
    return min(min(wing, keel), crease);
}

ORB_FORMA(aeroplanino)
