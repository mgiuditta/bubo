#include "../OrbShading.h"

// Codice · unione: a blender, a ribbed jar on a square base with a handle; the blades turn inside the jar.
static float frullatore(float3 p, float t) {
    float d = sdRoundBox(p - float3(0, -0.72, 0), float3(0.42, 0.12, 0.2), 0.06);
    float r0 = 0.22, r1 = 0.36;                        // the jar's radius at its foot and at its brim
    for (int i = 0; i < 3; i++) {                      // rings
        float y = -0.4 + 0.5 * float(i);
        float R = mix(r0, r1, (y + 0.4) / 1.0);
        d = min(d, length(float2(length(p.xz) - R, p.y - y)) - 0.04);
    }
    float3 q = float3(abs(p.x), p.y, p.z);
    d = min(d, sdSegment(q, float3(r0, -0.4, 0), float3(r1, 0.6, 0), 0.04));
    d = min(d, sdSegment(p, float3(0, -0.4, r0), float3(0, 0.6, r1), 0.04));
    d = min(d, sdCylinder(p - float3(0, 0.68, 0), 0.40, 0.04) - 0.03);
    d = min(d, length(p - float3(0, 0.83, 0)) - 0.07);
    d = min(d, sdSegment(p, float3(0.34, 0.45, 0), float3(0.60, 0.45, 0), 0.04));
    d = min(d, sdSegment(p, float3(0.60, 0.45, 0), float3(0.60, -0.15, 0), 0.04));
    d = min(d, sdSegment(p, float3(0.60, -0.15, 0), float3(0.27, -0.15, 0), 0.04));
    float3 b = float3(p.x, p.y + 0.28, p.z);           // the blades, turning
    b.xz = b.xz * rot(t * 9.0);
    d = min(d, sdSegment(b, float3(-0.2, 0, 0), float3(0.2, 0, 0), 0.035));
    d = min(d, sdSegment(b, float3(0, 0.02, 0), float3(0, 0.16, 0.0), 0.04));
    return d;
}

ORB_FORMA(frullatore)
