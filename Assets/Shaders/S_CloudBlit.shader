Shader "Custom/S_CloudBlit"
{   

    Properties
    {
        _CloudGlobalDensityMultiplier ("Cloud Global Density Multiplier", Float) = 1.0
        _Octave ("Octave", Int) = 5
        _Persistance ("Persistance", Float) = 1
        _Lacunarity ("Lacunarity", Float) = 1
    }
    SubShader
    {
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
        #include "../Resources/HL_Noise.hlsl"
        ENDHLSL

        Tags { "RenderType"="Opaque" }
        LOD 100
        ZWrite Off Cull Off
        Pass
        {
            Name "S_CloudBlit"

            HLSLPROGRAM
            
            #pragma vertex Vert
            #pragma fragment Frag

            float3 _BoxMin;
            float3 _BoxMax;

            float _CloudGlobalDensityMultiplier;
            int   _Octave;
            float _Persistance;
            float _Lacunarity;
            float _Camera_Near, _Camera_Far;

            sampler2D _CameraDepthTexture;

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            #define STEP_COUNT 32

            float ConvertToLinearEyeDepth(float depth)
            {
                // Handle reversed Z buffer
                depth = 1.0 - depth;
                
                float x = 1.0 - _Camera_Far / _Camera_Near;
                float y = _Camera_Far / _Camera_Near;
                float z = x / _Camera_Far;
                float w = y / _Camera_Far;
                
                return 1.0 / (z * depth + w);
            }

            // Returns (dstToBox, dstInsideBox).
            // If ray misses box, dstInsideBox will be zero.
            float2 rayBoxDst(float3 boundsMin, float3 boundsMax, float3 rayOrigin, float3 rayDir)
            {
                // Adapted from: http://jcgt.org/published/0007/03/04/
                float3 t0 = (boundsMin - rayOrigin) / rayDir;
                float3 t1 = (boundsMax - rayOrigin) / rayDir;
            
                float3 tmin = min(t0, t1);
                float3 tmax = max(t0, t1);
            
                float dstA = max(max(tmin.x, tmin.y), tmin.z);
                float dstB = min(tmax.x, min(tmax.y, tmax.z));
            
                // CASE 1: ray intersects box from outside (0 <= dstA <= dstB)
                // dstA is distance to nearest intersection, dstB is distance to far intersection
            
                // CASE 2: ray intersects box from inside (dstA < 0 < dstB)
                // dstA is distance to intersection behind the ray, dstB is distance to forward intersection
            
                // CASE 3: ray misses box (dstA > dstB)
            
                float dstToBox = max(0.0, dstA);
                float dstInsideBox = max(0.0, dstB - dstToBox);
            
                return float2(dstToBox, dstInsideBox);
            }

            //developer.nvidia.com/gpugems/gpugems2/part-ii-shading-lighting-and-shadows/chapter-16-accurate-atmospheric-scattering
            float PhaseFunction(float costheta, float g)
            {
                float g2 = g * g;
                float symmetry = (3 * (1 - g2)) / (2 * (2 + g2));
                return (1 + costheta * costheta) / pow(abs(1 + g2 - 2 * g * costheta), 1.5);
            
            }



            float3 CloudMarching(float3 rayOrigin, float3 rayDir, float rayLength, float depth, float3 viewDirVS) 
            {
                float viewRayOpticalDepth = 0;
                float opticalDepth = 0;
                float stepSize = rayLength / STEP_COUNT;

                Light mainLight = GetMainLight();
                float3 mainLightDir = mainLight.direction;

                float viewRayDistance = 0;  
                

                for (int i = 0 ; i< STEP_COUNT; i++)
                {
                    float3 samplePoint = rayOrigin + rayDir * viewRayDistance;
                    float sunRayDistance = 0;
                    float2 sunRayIntersection = rayBoxDst(_BoxMin, _BoxMax, rayOrigin + rayDir * (i * stepSize), mainLightDir);
                    float sunRayStepSize = sunRayIntersection.y / STEP_COUNT;

                   // float localDensity =   _CloudGlobalDensityMultiplier * WorleyFBM (samplePoint, _Octave, _Persistance, _Lacunarity);
                    float localDensity =   _CloudGlobalDensityMultiplier * smoothstep (0.2,0.8, 1-  Worley3D (0.3 * samplePoint));
                    viewRayOpticalDepth += localDensity * stepSize;

                    if (distance (samplePoint, _WorldSpaceCameraPos)* dot(normalize(viewDirVS), float3 (0,0,1)) > depth)
                    {
                        break;
                    }
                    for (int j = 0; j< STEP_COUNT; j++)
                    {
                        float3 sunRaySamplePoint = samplePoint + mainLightDir * sunRayDistance;

                        float sunRaylocalDensity = _CloudGlobalDensityMultiplier;
                        opticalDepth += sunRayStepSize * sunRaylocalDensity;

                        sunRayDistance += sunRayStepSize ;
                    }

                    viewRayDistance += stepSize;
                }

                float transmittance = 1- exp(-viewRayOpticalDepth);
                return transmittance;    
            }
 
            float4 Frag (Varyings input) : SV_Target
            {
                float3 rayOrigin = _WorldSpaceCameraPos;
                float2 uv = input.texcoord;
                float2 ndc = uv * 2.0 - 1.0;
                float4 viewDirVS = mul(unity_CameraInvProjection, float4(ndc, 0, -1));
                float3 viewDirWS = normalize(mul(unity_CameraToWorld, float4 (viewDirVS.xyz,0))).xyz;

                float4 color = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, input.texcoord).rgba;
                float sceneDepthNonLinear = tex2D(_CameraDepthTexture, uv).x;
                float sceneDepth = ConvertToLinearEyeDepth(sceneDepthNonLinear);

                float2 intersection = rayBoxDst(_BoxMin, _BoxMax, rayOrigin, viewDirWS);
                float distanceToCubeCameraForward = intersection.x * dot(normalize( viewDirVS.xyz), float3 (0,0,1));
                if (distanceToCubeCameraForward > sceneDepth)
                    return color;

                intersection.x = min (distanceToCubeCameraForward, intersection.x);
                float totalRayLength =  min( (sceneDepth - distanceToCubeCameraForward),  intersection.y);
                float3 cloudRadiance = CloudMarching(rayOrigin + viewDirWS * intersection.x, viewDirWS, totalRayLength, sceneDepth, viewDirVS);

                return lerp (color,1 ,cloudRadiance.x);
                return cloudRadiance.x;
                return   lerp (color, color * intersection.y * 0.1f,  intersection.y > 0);
            }
            
            ENDHLSL
        }
    }
}
