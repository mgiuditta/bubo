#include "../OrbShading.h"

// A hexagonal prism along y: apothem a, half-height h, flat faces toward ±z (the exact prism of Inigo Quilez's).
static float bulloneHex(float3 p, float a, float h) {
    const float3 k = float3(-0.8660254, 0.5, 0.57735);
    float3 q = float3(abs(p.x), abs(p.z), abs(p.y));
    q.xy -= 2.0 * min(dot(k.xy, q.xy), 0.0) * k.xy;
    float2 d = float2(length(q.xy - float2(clamp(q.x, -k.z * a, k.z * a), a)) * sign(q.y - a), q.z - h);
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}

// Codice · rilascio: a hexagonal bolt with three thread ridges and its nut; the nut turns a sixth of a turn, then rests.
static float bullone(float3 p, float t) {
    float head = bulloneHex(p - float3(0, 0.72, 0), 0.30, 0.12);
    float shaft = sdCylinder(p - float3(0, -0.1, 0), 0.15, 0.7);
    float turn = smoothstep(0.25, 0.5, fract(t / 3.0));
    float3 n = p - float3(0, -0.28, 0);
    n.xz = n.xz * rot(1.0472 * turn);
    float d = min(min(head, shaft), bulloneHex(n, 0.27, 0.13));
    for (int i = 0; i < 3; i++) {
        d = min(d, length(float2(length(p.xz) - 0.15, p.y + 0.5 + 0.1 * float(i))) - 0.025);
    }
    return d;
}

ORB_FORMA(bullone)
