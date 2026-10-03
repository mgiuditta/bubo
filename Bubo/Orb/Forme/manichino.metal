#include "../OrbShading.h"

// Codice · test: a tailor's dummy, a torso on a pole with a three-footed base.
static float manichino(float3 p, float) {
    float d = sdRoundCone(p, float3(0, -0.20, 0), float3(0, 0.35, 0), 0.22, 0.30);
    d = min(d, sdSegment(p, float3(0, 0.60, 0), float3(0, 0.70, 0), 0.05));
    d = min(d, length(p - float3(0, 0.76, 0)) - 0.09);
    d = min(d, sdSegment(p, float3(0, -0.20, 0), float3(0, -0.75, 0), 0.04));
    float3 q = float3(abs(p.x), p.y, p.z);
    d = min(d, sdSegment(q, float3(0, -0.75, 0), float3(0.42, -0.92, 0), 0.04));
    return min(d, sdSegment(p, float3(0, -0.75, 0), float3(0, -0.95, 0), 0.04));
}

ORB_FORMA(manichino)
