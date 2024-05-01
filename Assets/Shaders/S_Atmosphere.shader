Shader "Hidden/S_Atmosphere"
{
    Properties
    {
        [HideInInspector]_BlitTexture ("Texture", 2D) = "white" {}
        [HideInInspector]_DepthTexture ("Texture", 2D) = "white" {}
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
#include "HL_Atmosphere.hlsl"

            ENDHLSL
        }
    }
}
