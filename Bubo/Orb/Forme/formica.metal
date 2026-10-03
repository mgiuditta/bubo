#include "../OrbShading.h"

// One leg at `hip`, hip to knee to foot, the foot swinging by `swing`.
static float formicaLeg(float3 p, float3 hip, float swing) {
    float3 knee = hip + float3(0.10 + swing * 0.5, -0.30, 0);
    float3 foot = knee + float3(0.10 + swing, -0.34, 0);
    return min(sdSegment(p, hip, knee, 0.035), sdSegment(p, knee, foot, 0.03));
}

// Agente: an ant in profile, three segments, two antennae and six legs that walk in two tripods.
static float formica(float3 p, float t) {
    float abdomen = length(p - float3(-0.50, 0, 0)) - 0.27;
    float thorax = length(p - float3(-0.05, 0.02, 0)) - 0.17;
    float head = length(p - float3(0.40, 0.04, 0)) - 0.20;
    float waist = min(sdSegment(p, float3(-0.30, 0, 0), float3(-0.12, 0.02, 0), 0.07),
                      sdSegment(p, float3(0.05, 0.03, 0), float3(0.30, 0.04, 0), 0.08));
    float antennae = min(sdSegment(p, float3(0.50, 0.20, 0.08), float3(0.68, 0.52, 0.08), 0.03),
                         sdSegment(p, float3(0.50, 0.20, -0.08), float3(0.74, 0.46, -0.08), 0.03));
    float d = min(min(abdomen, thorax), min(head, min(waist, antennae)));
    for (int i = 0; i < 3; i++) {
        for (int s = 0; s < 2; s++) {
            float z = s == 0 ? -0.10 : 0.10;
            float swing = 0.10 * sin(t * 4.0 + float(i) * 2.1 + M_PI_F * float((i + s) % 2));
            d = min(d, formicaLeg(p, float3(-0.18 + 0.15 * float(i), -0.10, z), swing));
        }
    }
    return d;
}

ORB_FORMA(formica)
