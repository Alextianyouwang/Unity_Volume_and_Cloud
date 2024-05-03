Shader "Hidden/S_Atmosphere"
{
    Properties
    {
    }
    SubShader
    {
        Tags{"RenderPipeline" = "UniversalPipeline"}

        Pass
        {
            Name "BlitAtmosphere"

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/UnityInstancing.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "HL_Atmosphere.hlsl"

            ENDHLSL
        }
    }
}
