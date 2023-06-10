
#ifndef UTILITY
#define UTILITY
float Blend( float a, float b, float k )
{
    const float h = clamp( 0.5+0.5*(b-a)/k, 0.0, 1.0 );
    const float blendDst = lerp( b, a, h ) - k*h*(1.0-h);
    return blendDst;
}
#endif
