#ifndef ATMOSPHERE_INCLUDE
#define ATMOSPHERE_INCLUDE
uniform float4 _BlitScaleBias;

sampler2D _BlitTexture,_DepthTexture;
float4x4 _CamInvProjection, _CamToWorld;
float3 _CamPosWS;
float _Camera_Near, _Camera_Far;
float _AtmosphereHeight;
struct Ray
{
    float3 origin;
    float3 direction;
};
float2 PlaneRayIntersection(float3 normal, float3 position, float3 rayPosition, float3 rayDirection, float maxDist)
{
    float denominator = dot(normal, rayDirection);
    float distToPlane;
    float distThroughPlane;
    if (abs(denominator) > 0.00001f)
    {
        float t = min(dot(position - rayPosition, normal) / denominator, maxDist);
        if (rayPosition.y < position.y)
        {
            distToPlane = 0;
            distThroughPlane = t < 0 ? maxDist : min(t,maxDist);
        }
        else
        {
            distToPlane = t;
            distThroughPlane = t > 0 ? maxDist : 0;
        }
    }

    else
    {
        distToPlane = 0;
        distThroughPlane = 0;
    }
    return float2(distToPlane, distThroughPlane);
}
float LocalDensity(float3 pos)
{
    float height01 = pos.y / _AtmosphereHeight;
    return exp(-height01) * (1 - height01);

}

Ray CreateRay(float3 _origin, float3 _direction)
{
    Ray ray;
    ray.origin = _origin;
    ray.direction = _direction;
    return ray;
}
Ray ComputeCameraRay(float2 uv)
{
    
    float3 direction = mul(_CamInvProjection, float4(uv, 0, 1)).xyz;
    direction = mul(_CamToWorld, float4(direction, 0)).xyz;
    direction = normalize(direction);
    return CreateRay(_CamPosWS, direction);
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
void CalculateLight(float3 pointInAtmosphere, float3 rayDir, float sceneDepth, float distanceThroughPlane, out float volumeDepth, out float volumeDensity)
{
    float3 samplePos = pointInAtmosphere;
    volumeDepth = 0;
    volumeDensity = 0;
    float numInScatterPoints = 10;
    float stepSize = distanceThroughPlane / numInScatterPoints;
    
    for (int i = 0; i < numInScatterPoints; i++)
    {
        volumeDepth += stepSize;
        volumeDensity += LocalDensity(samplePos) * stepSize;
        if (volumeDepth > distanceThroughPlane)
            break;
        samplePos = pointInAtmosphere + rayDir * volumeDepth;
    }
   
}

float4 frag(v2f i) : SV_Target
{
    float4 col = tex2D(_BlitTexture, i.uv);
    float sceneDepthNonLinear = tex2D(_DepthTexture, i.uv);
    float sceneDepth = LinearEyeDepth(sceneDepthNonLinear);
   
    Ray camRay = ComputeCameraRay(i.uv * 2 - 1);
    
    float maxDistance = 1000;

    float2 hitInfo = PlaneRayIntersection(float3(0, 1, 0), float3(0, _AtmosphereHeight, 0), camRay.origin, camRay.direction,maxDistance);
    float distanceToPlane = hitInfo.x;
    float distanceThroughPlane = min(hitInfo.y, max(sceneDepth - distanceToPlane, 0));
    float3 pointInAtmosphere = camRay.origin + camRay.direction * (distanceToPlane + 0.001);
    
    float volumeDepth;
    float volumeDensity;
    CalculateLight(pointInAtmosphere, camRay.direction, sceneDepth, distanceThroughPlane,volumeDepth,volumeDensity);
    return volumeDensity.xxxx / 10;
    //return volumeDepth.xxxx / 10;
    return col + volumeDepth.xxxx / 100;
}
#endif