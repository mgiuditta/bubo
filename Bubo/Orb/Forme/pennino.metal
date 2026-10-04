#include "../OrbShading.h"

// The 2D triangle abc, made of a quad whose fourth corner lies on its edge.
static float pennino_tri(float2 p, float2 a, float2 b, float2 c) { return sdQuad2(p, a, b, c, 0.5 * (c + a)); }

// Creativo · grafica vettoriale: a pen-tool nib, its slit and eye on the front, a curve handle out to each side.
static float pennino(float3 p, float) {
    float2 m = float2(abs(p.x), p.y);
    float nib = min(sdQuad2(p.xy, float2(-0.38, 0.45), float2(-0.30, -0.1), float2(0.30, -0.1), float2(0.38, 0.45)),
                    pennino_tri(p.xy, float2(-0.30, -0.1), float2(0.30, -0.1), float2(0, -0.85)));
    float handles = udSegment2(m, float2(0, 0.5), float2(0.78, 0.78)) - 0.035;
    handles = min(handles, length(m - float2(0.78, 0.78)) - 0.09);
    float flat = extrude(min(nib - 0.02, handles), p.z, 0.05) - 0.02;
    float eye = sdTorusXY(p - float3(0, 0.12, 0.08), 0.09, 0.03);
    float slit = sdSegment(p, float3(0, -0.2, 0.08), float3(0, -0.7, 0.08), 0.03);
    return min(flat, min(eye, slit));
}

ORB_FORMA(pennino)
