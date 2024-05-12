#ifndef VOLUMEDISTORSION_INCLUDE
#define VOLUMEDISTORSION_INCLUDE
sampler2D _CameraOpaqueTexture, _CameraDepthTexture;
float _Camera_Near, _Camera_Far , _EarthRadius;
uint _NumOpticalDepthSample, _NumInScatteringSample;
float _Rs_Thickness;


float3 _SphereMaskCenter;
float _SphereMaskRadius;
float _SphereMaskBlend;
#include "../INCLUDE/HL_AtmosphereHelper.hlsl"


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

#if SHADER_API_GLES
                float4 pos = input.positionOS;
                float2 uv = input.uv;
#else
    float4 pos = GetFullScreenTriangleVertexPosition(input.vertexID);
    float2 uv = GetFullScreenTriangleTexCoord(input.vertexID);
#endif

    output.positionCS = pos;
    output.uv = uv;
    float3 viewVector = mul(unity_CameraInvProjection, float4(uv.xy * 2 - 1, 0, -1)).xyz;
    output.viewDir = mul(unity_CameraToWorld, float4(viewVector, 0)).xyz;
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

void CalculateDistortion(float3 rayOrigin, float3 rayDir, float distance, inout float2 uv)
{
    float stepSize = distance / (_NumInScatteringSample - 1);
    float3 samplePos = rayOrigin;
    float3 totalDir = 0;
    float dist = 0;
    int sampleCount = 0;
    float fraction = 1 / (float) _NumInScatteringSample;
    for (uint i = 0; i < _NumInScatteringSample; i++)
    {
        float ring;
        float prevRing = 0;
        float mask = SphereMask(_SphereMaskCenter, _SphereMaskRadius - 5, 5, samplePos, ring);
        float3 dirToCenter = normalize(prevRing > ring ? samplePos - _SphereMaskCenter : _SphereMaskCenter - samplePos);
        totalDir += dirToCenter * stepSize * ring * fraction ;
        sampleCount += 1;
        dist += stepSize;

        samplePos = rayOrigin + dist * rayDir;
        prevRing = ring;
    }

    float3 dirVS = mul(UNITY_MATRIX_V, float4(totalDir, 0)).xyz;
    //rayDir += totalDir;
   // uv = mul(unity_CameraProjection,mul(UNITY_MATRIX_V, float4(rayDir, 0))).xy/2 + 0.5;
    
    uv += dirVS.xy * -0.5;

}

float4 frag(v2f i) : SV_Target
{
    float3 rayOrigin = _WorldSpaceCameraPos;
    float3 rayDir = normalize(i.viewDir); 
    

    
    float2 hitInfo = RaySphere(_SphereMaskCenter, _SphereMaskRadius + 5, rayOrigin, rayDir);
    float3 marchStart = rayOrigin + rayDir * (hitInfo.x + 0.01);

    float3 forward = mul((float3x3) unity_CameraToWorld, float3(0, 0, 1));
    float originalSceneDepth = LinearEyeDepth(tex2D(_CameraDepthTexture, i.uv).x) / dot(rayDir, forward);
    

    float distThroughVolume = min(hitInfo.y, max(originalSceneDepth - hitInfo.x, 0));

    float2 uv = i.uv;
    CalculateDistortion(marchStart, rayDir,50, uv);
    
    float4 col = tex2D(_CameraOpaqueTexture, uv);
    return col.xyzz;
}
#endif