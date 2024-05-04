#ifndef ATMOSPHERE_INCLUDE
#define ATMOSPHERE_INCLUDE
uniform float4 _BlitScaleBias;
sampler2D _CameraOpaqueTexture, _DepthTexture;
float _ScatterIntensity, _AtmosphereHeight, _AtmosphereDensityFalloff, _AtmosphereDensityMultiplier, _EarthRadius, _AnisotropicScattering, _RayleighStrength;
float _Camera_Near, _Camera_Far;
int _NumInScatteringSample, _NumOpticalDepthSample;
float4 _RayleighScatterWeight,_InsColor;

#define MAX_DISTANCE 10000

float PhaseFunction(float costheta, float g)
{
    float g2 = g * g;
    return (1 - g2) / ( pow((1 + g2 - 2 * g * costheta), 1.5)) * 0.5;

}
float AngleBetweenVectors(float3 vec1, float3 vec2)
{
    float dotProduct = dot(normalize(vec1), normalize(vec2));
    return acos(dotProduct);
}

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
    return exp(-height01 * _AtmosphereDensityFalloff) * (1 - height01) *_AtmosphereDensityMultiplier;

}
float OpticalDepth(float3 rayOrigin, float3 rayDir, float rayLength)
{
    float3 densitySamplePoint = rayOrigin;
    float stepSize = rayLength / (_NumOpticalDepthSample - 1);
    float opticalDepth = 0;

    for (int i = 0; i < _NumOpticalDepthSample; i++)
    {
        float localDensity = LocalDensity(densitySamplePoint);
        opticalDepth += localDensity * stepSize;
        densitySamplePoint += rayDir * stepSize;
    }
    return opticalDepth;
}




void CalCulateHeightFogLight(float3 rayOrigin, float3 rayDir, float3 sunDir, float distance, float3 originalColor,
 out float3 inscatteredLight)
{
    float stepSize = distance / (_NumInScatteringSample - 1);
    float3 samplePos = rayOrigin;
    float phase = PhaseFunction(dot(sunDir, rayDir), _AnisotropicScattering);
    float viewRayOpticalDepth = 0;
    float3 scatteringWeight = lerp(1, _RayleighScatterWeight.xyz, _RayleighStrength);
    for (int i = 0; i < _NumInScatteringSample; i++)
    {
         Light mainLight = GetMainLight(TransformWorldToShadowCoord(samplePos));
        
        float localDensity = LocalDensity(samplePos) * stepSize;
        float sunRayLength = RaySphere(float3(0, -_EarthRadius, 0), _EarthRadius + _AtmosphereHeight, samplePos, sunDir).y;
        float sunRayOpticalDepth = OpticalDepth(samplePos, sunDir, sunRayLength);
        viewRayOpticalDepth = OpticalDepth(samplePos, -rayDir, stepSize * i);
        
        float3 transmittance = exp(-(sunRayOpticalDepth + viewRayOpticalDepth) * _ScatterIntensity * scatteringWeight);
        inscatteredLight += transmittance * LocalDensity(samplePos) * stepSize * phase * scatteringWeight * _InsColor.xyz;
        samplePos += rayDir * stepSize;
    }
    inscatteredLight += originalColor * exp(-viewRayOpticalDepth * scatteringWeight * _ScatterIntensity);

}

float4 frag(v2f i) : SV_Target
{
    float3 rayOrigin = _WorldSpaceCameraPos;
    float3 rayDir = normalize(i.viewDir);
    
    float4 col = tex2D(_CameraOpaqueTexture, i.uv);
    float3 forward = mul((float3x3) unity_CameraToWorld, float3(0, 0, 1));
    float sceneDepthNonLinear = tex2D(_DepthTexture, i.uv);
    float sceneDepth = LinearEyeDepth(sceneDepthNonLinear) /dot(rayDir, forward);

    Light mainLight = GetMainLight();

    float2 hitInfo = RaySphere(float3(0, -_EarthRadius, 0), _EarthRadius + _AtmosphereHeight, rayOrigin, rayDir);
    float distanceToSphere = hitInfo.x;
    float distanceThroughSphere = min(hitInfo.y, max(sceneDepth - distanceToSphere,0));
    float3 pointInAtmosphere = rayOrigin + rayDir * distanceToSphere;
    float3 inScatteredLight;
    float3 finalColor;

    CalCulateHeightFogLight(pointInAtmosphere, rayDir, mainLight.direction, distanceThroughSphere, col, finalColor);
    return finalColor.xyzz;
}
#endif