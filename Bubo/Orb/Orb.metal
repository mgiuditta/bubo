// The Orb: one pipeline per Forma, each with its own fragment function `forma_<name>` built from
// OrbShading.h. This file holds what they share and the Blob; every other Forma is a file in Forme/.
#include "OrbShading.h"

vertex VOut orbVertex(uint vid [[vertex_id]]) {
    float2 p[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    return { float4(p[vid], 0, 1) };
}

// The Blob alone: the rest shape every Morph starts from and returns to.
struct Forma_blob {
    static float distance(float3 p, float) { return length(p) - 0.92; }
    static float ripple() { return 1.0; }
    static bool isBlob() { return true; }
};

fragment float4 forma_blob(VOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
    return orbColor<Forma_blob>(in, u) * u.opacity;
}
