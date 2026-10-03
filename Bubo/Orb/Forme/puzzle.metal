#include "../OrbShading.h"

// Codice · integrazione: a puzzle piece with a knob on top and on the right, a notch on the left and at the bottom.
static float puzzle(float3 p, float) {
    float2 u = p.xy + 0.08;                            // the piece is centred by this shift
    float d = sdRoundBox2(u - float2(0.1, 0.1), float2(0.4, 0.4), 0.0);              // core
    d = min(d, sdRoundBox2(u - float2(-0.4, 0.32), float2(0.1, 0.18), 0.0));           // left edge above the notch
    d = min(d, sdRoundBox2(u - float2(-0.4, -0.4), float2(0.1, 0.1), 0.0));            // lower-left corner
    d = min(d, sdRoundBox2(u - float2(-0.4, -0.22), float2(0.1, 0.08), 0.0));          // left edge below the notch
    d = min(d, sdRoundBox2(u - float2(-0.22, -0.4), float2(0.08, 0.1), 0.0));          // bottom edge left of the notch
    d = min(d, sdRoundBox2(u - float2(0.32, -0.4), float2(0.18, 0.1), 0.0));           // bottom edge right of the notch
    d = min(d, sdRoundBox2(u - float2(0, 0.57), float2(0.07, 0.07), 0.0));             // top neck
    d = min(d, length(u - float2(0, 0.74)) - 0.17);                                    // top knob
    d = min(d, sdRoundBox2(u - float2(0.57, 0), float2(0.07, 0.07), 0.0));             // right neck
    d = min(d, length(u - float2(0.74, 0)) - 0.17);                                    // right knob
    return extrude(d, p.z, 0.07) - 0.03;
}

ORB_FORMA(puzzle)
