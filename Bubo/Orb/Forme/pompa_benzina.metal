#include "../OrbShading.h"

// Viaggi: a petrol pump with its screen, a hose and the nozzle hung on its side.
static float pompa_benzina(float3 p, float) {
    p.x += 0.13;
    float body = sdRoundBox(p - float3(-0.2, 0, 0), float3(0.4, 0.7, 0.25), 0.08);
    float screen = sdRoundBox(p - float3(-0.2, 0.4, 0.25), float3(0.26, 0.14, 0.05), 0.02);
    float base = sdRoundBox(p - float3(-0.2, -0.75, 0), float3(0.5, 0.07, 0.3), 0.03);
    float hose = min(sdSegment(p, float3(0.2, 0.25, 0), float3(0.6, 0.35, 0), 0.045),
                     min(sdSegment(p, float3(0.6, 0.35, 0), float3(0.7, 0.0, 0), 0.045),
                         sdSegment(p, float3(0.7, 0.0, 0), float3(0.62, -0.2, 0), 0.045)));
    float gun = min(sdSegment(p, float3(0.62, -0.2, 0), float3(0.62, -0.45, 0), 0.09),
                    sdSegment(p, float3(0.62, -0.2, 0), float3(0.82, -0.05, 0), 0.04));
    return min(min(body, screen), min(base, min(hose, gun)));
}

ORB_FORMA(pompa_benzina)
