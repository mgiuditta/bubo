#include "../OrbShading.h"

// Musica · arpa: a triangular harp, a straight pillar, a curved neck and a soundbox, with five strings.
static float arpa(float3 p, float) {
    float frame = sdSegment(p, float3(0.55, 0.8, 0), float3(0.55, -0.8, 0), 0.08);
    frame = min(frame, sdSegment(p, float3(0.55, 0.8, 0), float3(-0.05, 0.45, 0), 0.06));
    frame = min(frame, sdSegment(p, float3(-0.05, 0.45, 0), float3(-0.7, -0.45, 0), 0.06));
    frame = min(frame, sdSegment(p, float3(0.55, -0.8, 0), float3(-0.7, -0.45, 0), 0.1));
    float strings = min(min(sdSegment(p, float3(-0.5, -0.173, 0), float3(-0.5, -0.506, 0), 0.02),
                            sdSegment(p, float3(-0.3, 0.104, 0), float3(-0.3, -0.562, 0), 0.02)),
                        min(sdSegment(p, float3(-0.1, 0.381, 0), float3(-0.1, -0.618, 0), 0.02),
                            min(sdSegment(p, float3(0.1, 0.537, 0), float3(0.1, -0.674, 0), 0.02),
                                sdSegment(p, float3(0.3, 0.683, 0), float3(0.3, -0.73, 0), 0.02))));
    return min(frame, strings);
}

ORB_FORMA(arpa)
