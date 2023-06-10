#ifndef NOISE
#define NOISE
float3x3 m =float3x3(0.00, 0.80, 0.60,
    -0.80, 0.36, -0.48,
    -0.60, -0.48, 0.64);
float hash(float n)
{
    return frac(sin(n) * 43758.5453);
}
float noise( float3 x)
{
    float3 p = floor(x);
    float3  f = frac(x);
    f = f * f * (3.0 - 2.0 * f);

    const float n = p.x + p.y * 57.0 + 113.0 * p.z;

    const float res = lerp(lerp(lerp(hash(n + 0.0), hash(n + 1.0), f.x),
        lerp(hash(n + 57.0), hash(n + 58.0), f.x), f.y),
        lerp(lerp(hash(n + 113.0), hash(n + 114.0), f.x),
            lerp(hash(n + 170.0), hash(n + 171.0), f.x), f.y), f.z);
    return res;
}
float fbm(float3 p)
{
    float f = 0.5000 * noise(p); p = mul(m , p) * 2.02;

    f += 0.2500 * noise(p); p = mul(m , p) * 2.03;
    f += 0.1250 * noise(p);
    return f;
}

#endif
