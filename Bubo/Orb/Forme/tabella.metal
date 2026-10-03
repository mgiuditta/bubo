#include "../OrbShading.h"

// Codice · dati tabellari: a grid of three rows by three columns, the header row solid and thicker.
static float tabella(float3 p, float) {
    float d = sdRoundBox2(p.xy - float2(0, 0.55), float2(0.83, 0.25), 0.0); // header
    d = min(d, sdRoundBox2(p.xy - float2(0, -0.15), float2(0.83, 0.05), 0.0));
    d = min(d, sdRoundBox2(p.xy - float2(0, -0.6), float2(0.83, 0.05), 0.0));
    d = min(d, sdRoundBox2(p.xy - float2(-0.78, 0.075), float2(0.05, 0.725), 0.0));
    d = min(d, sdRoundBox2(p.xy - float2(-0.26, 0.075), float2(0.05, 0.725), 0.0));
    d = min(d, sdRoundBox2(p.xy - float2(0.26, 0.075), float2(0.05, 0.725), 0.0));
    d = min(d, sdRoundBox2(p.xy - float2(0.78, 0.075), float2(0.05, 0.725), 0.0));
    return extrude(d, p.z, 0.05) - 0.03;
}

ORB_FORMA(tabella)
