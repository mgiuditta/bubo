#include "../OrbShading.h"

// Viaggi · documenti: a closed passport, a globe on the cover and two lines of text below it.
static float passaporto(float3 p, float) {
    float cover = sdRoundBox(p, float3(0.5, 0.7, 0.09), 0.06);
    float spine = sdRoundBox(p - float3(-0.5, 0, 0), float3(0.04, 0.7, 0.12), 0.03);
    float globe = min(sdTorusXY(p - float3(0, 0.18, 0.1), 0.27, 0.035),
                      min(sdSegment(p, float3(-0.27, 0.18, 0.1), float3(0.27, 0.18, 0.1), 0.03),
                          sdSegment(p, float3(0, -0.09, 0.1), float3(0, 0.45, 0.1), 0.03)));
    float text = min(sdSegment(p, float3(-0.25, -0.4, 0.1), float3(0.25, -0.4, 0.1), 0.04),
                     sdSegment(p, float3(-0.18, -0.55, 0.1), float3(0.18, -0.55, 0.1), 0.035));
    return min(min(cover, spine), min(globe, text));
}

ORB_FORMA(passaporto)
