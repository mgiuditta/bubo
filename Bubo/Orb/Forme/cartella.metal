#include "../OrbShading.h"

// Codice: a closed folder: a back panel with a tab at the top left and a lower front panel.
static float cartella(float3 p, float) {
    float back = sdRoundBox(p, float3(0.78, 0.55, 0.06), 0.05);
    float tab = sdRoundBox(p - float3(-0.45, 0.62, 0), float3(0.33, 0.10, 0.06), 0.05);
    float front = sdRoundBox(p - float3(0, -0.12, 0.10), float3(0.78, 0.43, 0.03), 0.03);
    return min(back, min(tab, front));
}

ORB_FORMA(cartella)
