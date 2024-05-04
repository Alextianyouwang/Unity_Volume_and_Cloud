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

            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile _ _SHADOWS_SOFT

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/UnityInstancing.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "HL_Atmosphere.hlsl"


            ENDHLSL
        }
    }
}
