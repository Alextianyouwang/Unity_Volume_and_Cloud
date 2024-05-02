#ifndef ATMOSPHERE_INCLUDE
#define ATMOSPHERE_INCLUDE
uniform float4 _BlitScaleBias;
sampler2D _BlitTexture,_DepthTexture;
float3 _CamPosWS;
float3 _WaveLength;
float _ScatterIntensity, _FinalColorMultiplier, _AtmosphereHeight, _AtmosphereDensityFalloff,_EarthRadius;
float _Camera_Near, _Camera_Far;
int _NumInScatteringSample, _NumOutScatteringSample;

#define MAX_DISTANCE 10000

float2 RaySphere(float3 sphereCentre, float sphereRadius, float3 rayOrigin, float3 rayDir)
{
    float3 offset = rayOrigin - sphereCentre;
    float a = 1; // Set to dot(rayDir, rayDir) if rayDir might not be normalized
    float b = 2 * dot(offset, rayDir);
    float c = dot(offset, offset) - sphereRadius * sphereRadius;
    float d = b * b - 4 * a * c; // Discriminant from quadratic formula

		// Number of intersections: 0 when d < 0; 1 when d = 0; 2 when d > 0
    if (d > 0)
    {
        float s = sqrt(d);
        float dstToSphereNear = max(0, (-b - s) / (2 * a));
        float dstToSphereFar = (-b + s) / (2 * a);

			// Ignore intersections that occur behind the ray
        if (dstToSphereFar >= 0)
        {
            return float2(dstToSphereNear, dstToSphereFar - dstToSphereNear);
        }
    }
		// Ray did not intersect sphere
    return float2(MAX_DISTANCE, 0);
}

struct appdata
{
    float4 positionOS : POSITION;
    uint vertexID : SV_VertexID;
    float2 uv : TEXCOORD0;
};

struct v2f
{
    float2 uv : TEXCOORD0;
    float4 positionCS : SV_POSITION;
    float3 viewDir : TEXCOORD1;
};


v2f vert(appdata input)
{
    v2f output;
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

#if SHADER_API_GLES
                float4 pos = input.positionOS;
                float2 uv = input.uv;
#else
    float4 pos = GetFullScreenTriangleVertexPosition(input.vertexID);
    float2 uv = GetFullScreenTriangleTexCoord(input.vertexID);
#endif

    output.positionCS = pos;
    output.uv = uv * _BlitScaleBias.xy + _BlitScaleBias.zw;
    float3 viewVector = mul(unity_CameraInvProjection, float4(uv.xy * 2 - 1, 0, -1));
    output.viewDir = mul(unity_CameraToWorld, float4(viewVector, 0));
    return output;
}
inline float LinearEyeDepth(float depth)
{
    // Reversed Z
    depth = 1 - depth;
    float x = 1 - _Camera_Far / _Camera_Near;
    float y = _Camera_Far / _Camera_Near;
    float z = x / _Camera_Far;
    float w = y / _Camera_Far;
    return 1.0 / (z * depth + w);
}
float LocalDensity(float3 pos)
{
    float distToCenter = length(pos - float3(0, -_EarthRadius, 0));
    float heightAboveSurface = max(distToCenter - _EarthRadius,0);
    float height01 =  heightAboveSurface / _AtmosphereHeight;
    return exp(-height01 * _AtmosphereDensityFalloff) * (1 - height01);

}
float OpticalDepth(float3 rayOrigin, float3 rayDir, float rayLength)
{
    float3 densitySamplePoint = rayOrigin;
    float stepSize = rayLength / (_NumOutScatteringSample - 1);
    float opticalDepth = 0;

    for (int i = 0; i <_NumOutScatteringSample; i++)
    {
        float localDensity = LocalDensity(densitySamplePoint);
        opticalDepth += localDensity * stepSize;
        densitySamplePoint += rayDir * stepSize;
    }
    return opticalDepth;
}



void CalculateLight(float3 pointInAtmosphere, float3 rayDir, float3 sunDir, float distanceThroughPlane, float3 originalCol, float3 sunColor,
 out float3 inScatteredLight, out float3 finalColor)
{
    
    float3 scatteringCoefficients = pow(100/ _WaveLength, 4) * _ScatterIntensity;
    float3 samplePos = pointInAtmosphere;
    inScatteredLight = 0;
    float viewRayOpticalDepth = 0;
    float stepSize = distanceThroughPlane / (_NumInScatteringSample - 1);
    
    
    for (int i = 0; i <_NumInScatteringSample; i++)
    {
        float sunRayLength = RaySphere(float3(0, -_EarthRadius, 0), _EarthRadius + _AtmosphereHeight, samplePos, sunDir).y;
        float sunRayOpticalDepth = OpticalDepth(samplePos, sunDir, sunRayLength);
        viewRayOpticalDepth = OpticalDepth(samplePos, -rayDir, stepSize * i);
        float3 transmittance = exp(-(sunRayOpticalDepth + viewRayOpticalDepth) * scatteringCoefficients);
    
        inScatteredLight += length(transmittance) < 0.001 ? 0: transmittance * LocalDensity(samplePos) * stepSize;
  
        samplePos += rayDir * stepSize;
    }
    inScatteredLight *= scatteringCoefficients * _FinalColorMultiplier * sunColor;
    float3 sceneColor = originalCol * exp(-viewRayOpticalDepth * scatteringCoefficients);
    finalColor = sceneColor + inScatteredLight;

}

float4 frag(v2f i) : SV_Target
{
    float3 rayOrigin = _WorldSpaceCameraPos;
    float3 rayDir = normalize(i.viewDir);
    
    float4 col = tex2D(_BlitTexture, i.uv);
    float3 forward = mul((float3x3) unity_CameraToWorld, float3(0, 0, 1));
    float sceneDepthNonLinear = tex2D(_DepthTexture, i.uv);
    float sceneDepth = LinearEyeDepth(sceneDepthNonLinear) / dot(rayDir, forward);

    Light mainLight = GetMainLight();

    float2 hitInfo = RaySphere(float3(0, -_EarthRadius, 0), _EarthRadius + _AtmosphereHeight, rayOrigin, rayDir);
    float distanceToSphere = hitInfo.x;
    float distanceThroughSphere = min(hitInfo.y,sceneDepth - distanceToSphere);
    float3 pointInAtmosphere = rayOrigin + rayDir * (distanceToSphere + 0.001);
    float3 inScatteredLight;
    float3 finalColor;
    CalculateLight(pointInAtmosphere, rayDir, mainLight.direction, distanceThroughSphere, col, mainLight.color, inScatteredLight,finalColor);
    return finalColor.xyzz;
}
#endif