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

int _CellSize = 1, _AxisCellCount= 20, _InvertNoise = 1, _Seed = 3286365;
float ace_hash(uint n) {
    // integer hash copied from Hugo Elias
    n = (n << 13U) ^ n;
    n = n * (n * n * 15731U + 0x789221U) + 0x1376312589U;
    return float(n & uint(0x7fffffffU)) / float(0x7fffffff);
}
float  ace_worley(float3 coord, int axisCellCount) {
    int3 cell = floor(coord / _CellSize);

    float3 localSamplePos = float3(coord / _CellSize - cell);

    float dist = 1.0f;

    for (int x = -1; x <= 1; ++x) {
        for (int y = -1; y <= 1; ++y) {
            for (int z = -1; z <= 1; ++z) {
                int3 cellCoordinate = cell + int3(x, y, z);
                int x = cellCoordinate.x;
                int y = cellCoordinate.y;
                int z = cellCoordinate.z;

                if (x == -1 || x == axisCellCount || y == -1 || y == axisCellCount || z == -1 || z == axisCellCount) {
                    int3 wrappedCellCoordinate = fmod(cellCoordinate + axisCellCount, (int3)axisCellCount);
                    int wrappedCellIndex = wrappedCellCoordinate.x + axisCellCount * (wrappedCellCoordinate.y + wrappedCellCoordinate.z * axisCellCount);
                    float3 featurePointOffset = cellCoordinate + float3(hash(_Seed + wrappedCellIndex), hash(_Seed + wrappedCellIndex * 2), hash(_Seed + wrappedCellIndex * 3));
                    dist = min(dist, distance(cell + localSamplePos, featurePointOffset));
                }
                else {
                    int cellIndex = cellCoordinate.x + axisCellCount * (cellCoordinate.y + cellCoordinate.z * axisCellCount);
                    float3 featurePointOffset = cellCoordinate + float3(hash(_Seed + cellIndex), hash(_Seed + cellIndex * 2), hash(_Seed + cellIndex * 3));
                    dist = min(dist, distance(cell + localSamplePos, featurePointOffset));
                }
            }
        }
    }

    dist = sqrt(1.0f - dist * dist);
    dist *= dist * dist * dist * dist * dist;
    return dist;
}


float3 Hash3(float3 p)
{
    p = frac(p * 0.1031);
    p += dot(p, p.yzx + 33.33);
    return frac((p.xxy + p.yzz) * p.zyx);
}

float Worley3D(float3 p)
{
    float3 cell = floor(p);
    float3 localPos = frac(p);

    float minDist = 1e6;

    // Search neighboring cells
    [unroll]
    for (int z = -1; z <= 1; z++)
    {
        [unroll]
        for (int y = -1; y <= 1; y++)
        {
            [unroll]
            for (int x = -1; x <= 1; x++)
            {
                float3 neighbor = float3(x, y, z);
                float3 randomPoint = Hash3(cell + neighbor);
                float3 diff = neighbor + randomPoint - localPos;
                float dist = dot(diff, diff); // squared distance
                minDist = min(minDist, dist);
            }
        }
    }

    return sqrt(minDist); // true distance
}

float WorleyFBM(
    float3 p,
    int octaves,
    float persistence,
    float lacunarity)
{
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;

    for (int i = 0; i < octaves; i++)
    {
        float n = Worley3D(p * frequency);

        // Optional inversion for nicer cloud / smoke patterns
        n = 1.0 - n;

        value += n * amplitude;

        frequency *= lacunarity;
        amplitude *= persistence;
    }

    return value;
}
#endif
