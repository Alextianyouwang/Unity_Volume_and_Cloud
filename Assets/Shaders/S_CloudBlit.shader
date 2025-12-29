Shader "Custom/S_CloudBlit"
{   
    SubShader
    {
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
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
 
            float4 Frag (Varyings input) : SV_Target
            {
                float3 rayOrigin = _WorldSpaceCameraPos;
                float2 uv = input.texcoord;
                float2 ndc = uv * 2.0 - 1.0;
                float3 viewDirVS = mul(unity_CameraInvProjection, float4(ndc, 0, -1)).xyz;
                float3 viewDirWS = normalize(mul(unity_CameraToWorld, float4 (viewDirVS,0))).xyz;

                float2 intersection = rayBoxDst(_BoxMin, _BoxMax, rayOrigin, viewDirWS);
                float4 color = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, input.texcoord).rgba;

                

                return   lerp (color, color * intersection.x * 0.1f,  intersection.y > 0)  ;
            }
            
            ENDHLSL
        }
    }
}
