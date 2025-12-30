#ifndef GENERAL_HELPER_INCLUDED
#define GENERAL_HELPER_INCLUDED

void PhaseFunction_float(float costheta, float g, out float phase)
{
    float g2 = g * g;
    float symmetry = (3 * (1 - g2)) / (2 * (2 + g2));
    phase = (1 + costheta * costheta) / pow(abs(1 + g2 - 2 * g * costheta), 1.5);
            
}

void DuelLobePhaseFunction_float(float costheta, float g1, float g2, float a, out float phase)
{
    float phase1;
    PhaseFunction_float(costheta, g1, phase1);
    float phase2;
    PhaseFunction_float(costheta, g2, phase2);
    phase = a * phase1 + (1 - a) * phase2;
}



#endif