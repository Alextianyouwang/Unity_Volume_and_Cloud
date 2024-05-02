#ifndef ATMOSPHERE_INCLUDE
#define ATMOSPHERE_INCLUDE
uniform float4 _BlitScaleBias;

sampler2D _BlitTexture,_DepthTexture;
float3 _CamPosWS;
float _Camera_Near, _Camera_Far;
float _AtmosphereHeight, _AtmosphereDensityFalloff;

#define MAX_DISTANCE 10000
#define EARTH_RADIUS 1000

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
    float heightAboveSurface = length(pos - float3(0, -EARTH_RADIUS, 0)) - EARTH_RADIUS;
    float height01 = heightAboveSurface / _AtmosphereHeight;
    return exp(-height01 * _AtmosphereDensityFalloff) * (1 - height01);

}
float OpticalDepth(float3 rayOrigin, float3 rayDir, float rayLength)
{
    float3 densitySamplePoint = rayOrigin;
    int numOpticalDepthPoints = 10;
    float stepSize = rayLength / (numOpticalDepthPoints - 1);
    float opticalDepth = 0;

    for (int i = 0; i < numOpticalDepthPoints; i++)
    {
        float localDensity = LocalDensity(densitySamplePoint);
        opticalDepth += localDensity * stepSize;
        densitySamplePoint += rayDir * stepSize;
    }
    return opticalDepth;
}



void CalculateLight(float3 pointInAtmosphere, float3 rayDir, float3 sunDir, float distanceThroughPlane, out float volumeDepth, out float volumeDensity, out float3 inScatteredLight)
{
    
    float3 scatteringCoefficients = float3(700, 530, 440);
    scatteringCoefficients = pow(150/ scatteringCoefficients, 4) * 1;
    float3 samplePos = pointInAtmosphere;
    volumeDepth = 0;
    volumeDensity = 0;
    inScatteredLight = 0;
    
    int numInScatterPoints = 10;
    float stepSize = distanceThroughPlane / (numInScatterPoints-1);
    
    
    for (int i = 0; i < numInScatterPoints; i++)
    {
        volumeDepth += stepSize;
        volumeDensity += LocalDensity(samplePos) * stepSize;
        float sunRayLength = RaySphere(float3(0, -EARTH_RADIUS, 0), EARTH_RADIUS + _AtmosphereHeight, samplePos, sunDir).y;
        float sunRayOpticalDepth = OpticalDepth(samplePos, sunDir, sunRayLength);
        float viewRayOpticalDepth = OpticalDepth(pointInAtmosphere, rayDir, stepSize * i);
        float3 transmittance = exp(-(sunRayOpticalDepth + viewRayOpticalDepth) * scatteringCoefficients);
        inScatteredLight += transmittance * LocalDensity(samplePos) * stepSize;
  
        samplePos += rayDir * stepSize;
    }
    inScatteredLight *= scatteringCoefficients * 1.5;
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

    float2 hitInfo = RaySphere(float3(0, -EARTH_RADIUS, 0),EARTH_RADIUS +_AtmosphereHeight, rayOrigin, rayDir);
    float distanceToSphere = hitInfo.x;
    float distanceThroughSphere = min(hitInfo.y,sceneDepth - distanceToSphere);
    float3 pointInAtmosphere = rayOrigin + rayDir * (distanceToSphere + 0.001);
    
    float volumeDepth;
    float volumeDensity;
    float3 inScatteredLight;
    CalculateLight(pointInAtmosphere, rayDir, mainLight.direction, distanceThroughSphere, volumeDepth, volumeDensity, inScatteredLight);
    if (distanceThroughSphere > 0)
    {
        return inScatteredLight.xyzz;
        return col + volumeDensity.xxxx / 100;
    }
    else
    {
        return col;
    }

}
#endif