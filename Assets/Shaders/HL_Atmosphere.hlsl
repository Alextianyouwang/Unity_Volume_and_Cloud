#ifndef ATMOSPHERE_INCLUDE
#define ATMOSPHERE_INCLUDE
uniform float4 _BlitScaleBias;
sampler2D _CameraOpaqueTexture, _CameraDepthTexture,_OpticalDepthTexture;
float _Camera_Near, _Camera_Far, _EarthRadius;
int _NumInScatteringSample, _NumOpticalDepthSample;

float _Rs_Absorbsion, _Rs_Thickness, _Rs_DensityFalloff, _Rs_DensityMultiplier, _Rs_ChannelSplit;
float4 _Rs_ScatterWeight, _Rs_InsColor;

float _Ms_Absorbsion, _Ms_Thickness, _Ms_DensityFalloff, _Ms_DensityMultiplier, _Ms_Anisotropic;
float4 _Ms_InsColor;

bool _VolumeOnly = 0;
#define MAX_DISTANCE 10000

//developer.nvidia.com/gpugems/gpugems2/part-ii-shading-lighting-and-shadows/chapter-16-accurate-atmospheric-scattering
float PhaseFunction(float costheta, float g)
{
    float g2 = g * g;
    float symmetry = (3 * (1 - g2)) / (2 * (2 + g2));
    return (1 + costheta * costheta) / pow(1 + g2 - 2 * g * costheta, 1.5);

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
float LocalDensity(float3 pos, float relativeHeight, float falloff, float multiplier)
{
    float distToCenter = length(pos - float3(0, -_EarthRadius, 0));
    float heightAboveSurface = max(distToCenter - _EarthRadius,0);
    float height01 = clamp(heightAboveSurface / relativeHeight,0,1);
    return exp(-height01 * falloff) * (1 - height01) * multiplier;

}
float OpticalDepth(float3 rayOrigin, float3 rayDir, float rayLength, float relativeHeight, float falloff, float multiplier)
{
    float3 densitySamplePoint = rayOrigin;
    float stepSize = rayLength / (_NumOpticalDepthSample - 1);
    float opticalDepth = 0;

    for (int i = 0; i < _NumOpticalDepthSample; i++)
    {
        float localDensity = LocalDensity(densitySamplePoint,relativeHeight,falloff,multiplier);
        opticalDepth += localDensity * stepSize;
        densitySamplePoint += rayDir * stepSize;
    }
    return opticalDepth;
}

float4 OpticalDepthBaked(float3 rayOrigin, float3 rayDir)
{
    float3 relativeDistToCenter = rayOrigin - float3(0, -_EarthRadius, 0);
    float distAboveGround = length(relativeDistToCenter) - _EarthRadius;
    float height01 = distAboveGround / _Rs_Thickness;
    float zenithAngle = dot(normalize(relativeDistToCenter), rayDir);
    float angle01 = 1 - (zenithAngle * 0.5 + 0.5);
    float4 opticalDepth = tex2D(_OpticalDepthTexture, float2(angle01,height01));
    return opticalDepth;
}



void AtmosphereicScattering(float3 rayOrigin, float3 rayDir, float3 sunDir, float distance,
 out float3 inscatteredLight, out float3 transmittance)
{
    float stepSize = distance / (_NumInScatteringSample - 1);
    float3 samplePos = rayOrigin;
#if _USE_RAYLEIGH
    float rs_phase = PhaseFunction(dot(sunDir, rayDir), 0);
#else
    float rs_phase = 0;
#endif
#if _USE_MIE
    float ms_phase = PhaseFunction(dot(sunDir, rayDir), _Ms_Anisotropic);
#else
    float ms_phase = 0;
#endif
    float3 rs_scatteringWeight = lerp(length(_Rs_ScatterWeight.xyz) / 3, _Rs_ScatterWeight.xyz, _Rs_ChannelSplit) * _Rs_Absorbsion;
    float ms_scatteringWeight = _Ms_Absorbsion / 100;
    float rs_viewRayOpticalDepth = 0;
    float ms_viewRayOpticalDepth = 0;
    float3 rs_inscatterLight = 0;
    float3 ms_inscatterLight = 0;
    for (int i = 0; i < _NumInScatteringSample; i++)
    {
        float sunRayLength = RaySphere(float3(0, -_EarthRadius, 0), _EarthRadius + _Rs_Thickness, samplePos, sunDir).y;
        float4 opticalDepthData = OpticalDepthBaked(samplePos, sunDir);
#if _USE_RAYLEIGH
        float rs_localDensity = LocalDensity(samplePos, _Rs_Thickness, _Rs_DensityFalloff, _Rs_DensityMultiplier) * stepSize;
        rs_localDensity = opticalDepthData.y* stepSize* _Rs_DensityMultiplier;
        rs_viewRayOpticalDepth += rs_localDensity;
        float rs_sunRayOpticalDepth = OpticalDepth(samplePos, sunDir, sunRayLength, _Rs_Thickness,_Rs_DensityFalloff, _Rs_DensityMultiplier);
        rs_sunRayOpticalDepth = opticalDepthData.x;
        float3 rs_tau = (rs_viewRayOpticalDepth + rs_sunRayOpticalDepth) * rs_scatteringWeight;
#else
        float3 rs_tau = 0;
        float rs_localDensity = 0;
#endif
#if _USE_MIE
        float ms_localDensity = LocalDensity(samplePos, _Ms_Thickness, _Ms_DensityFalloff, _Ms_DensityMultiplier) * stepSize;
        ms_localDensity = opticalDepthData.w * stepSize * _Ms_DensityMultiplier;
        ms_viewRayOpticalDepth += ms_localDensity;
        float ms_sunRayOpticalDepth = OpticalDepth(samplePos, sunDir, sunRayLength, _Ms_Thickness, _Ms_DensityFalloff, _Ms_DensityMultiplier);
        ms_sunRayOpticalDepth =  opticalDepthData.z;
        float3 ms_tau = (ms_sunRayOpticalDepth + ms_viewRayOpticalDepth) * ms_scatteringWeight;
#else
        float3 ms_tau = 0;
        float ms_localDensity = 0;
#endif
        
        float3 totalTransmittance = exp(-rs_tau - ms_tau);
        
        rs_inscatterLight += totalTransmittance * rs_localDensity;
        ms_inscatterLight += totalTransmittance * ms_localDensity;
        samplePos += rayDir * stepSize;
    }
    rs_inscatterLight *=  rs_scatteringWeight * _Rs_InsColor.xyz;
    ms_inscatterLight *= ms_phase * ms_scatteringWeight * _Ms_InsColor.xyz;
    transmittance = exp(-rs_viewRayOpticalDepth * rs_scatteringWeight - ms_viewRayOpticalDepth * ms_scatteringWeight);
    inscatteredLight =   ms_inscatterLight + rs_inscatterLight;
}

float4 frag(v2f i) : SV_Target
{
    float3 rayOrigin = _WorldSpaceCameraPos;
    float3 rayDir = normalize(i.viewDir); 
    float4 opticalDepth = tex2D(_OpticalDepthTexture, i.uv);
    
    float4 col = tex2D(_CameraOpaqueTexture, i.uv);

    float3 forward = mul((float3x3) unity_CameraToWorld, float3(0, 0, 1));
    float sceneDepthNonLinear = tex2D(_CameraDepthTexture, i.uv);
    float sceneDepth = LinearEyeDepth(sceneDepthNonLinear) /dot(rayDir, forward);

    Light mainLight = GetMainLight();

    float2 hitInfo = RaySphere(float3(0, -_EarthRadius, 0), _EarthRadius + _Rs_Thickness, rayOrigin, rayDir);
    float distThroughVolume = min(hitInfo.y, max(sceneDepth - hitInfo.x, 0));
    float3 marchStart = rayOrigin + rayDir * (hitInfo.x+ 0.01);
    float3 inscatteredLight;
    float3 transmittance;
    AtmosphereicScattering(marchStart, rayDir, mainLight.direction, distThroughVolume, inscatteredLight,transmittance);

    float3 finalCol = _VolumeOnly ? inscatteredLight : inscatteredLight + transmittance * col.xyz;
    
   //return opticalDepth ;
    
    return finalCol.xyzz;
}
#endif