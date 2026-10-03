#include "../OrbShading.h"

// Viaggi · aeroporti: a control tower, a tapering shaft carrying a wide glass cab with a roof and a mast.
static float torre_controllo(float3 p, float) {
    float base = sdCylinder(p - float3(0, -0.86, 0), 0.5, 0.06);
    float shaft = sdCappedCone(p - float3(0, -0.28, 0), 0.52, 0.22, 0.13);
    float cab = sdCappedCone(p - float3(0, 0.46, 0), 0.17, 0.18, 0.42);
    float rim = sdCylinder(p - float3(0, 0.3, 0), 0.2, 0.025);
    float roof = sdCylinder(p - float3(0, 0.67, 0), 0.46, 0.04);
    float mast = sdSegment(p, float3(0, 0.7, 0), float3(0, 0.95, 0), 0.025);
    float dish = length(p - float3(0, 0.95, 0)) - 0.05;
    return min(min(min(base, shaft), min(cab, rim)), min(roof, min(mast, dish)));
}

ORB_FORMA(torre_controllo)
