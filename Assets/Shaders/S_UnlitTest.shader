Shader "Custom/S_UnlitTest"
{
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        [MainTexture] _BaseMap("Base Map", 2D) = "white"

        _MainGradientSlide ("Main Gradient Slide", float) = 0.0
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                float4 _BaseMap_ST;
                float _MainGradientSlide;
            CBUFFER_END

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
                return OUT;
            }

            float invLerp(float from, float to, float value) {
                return (value - from) / (to - from);
            }

            float remap(float origFrom, float origTo, float targetFrom, float targetTo, float value){
                float rel = invLerp(origFrom, origTo, value);
                return lerp(targetFrom, targetTo, rel);
            }

            half4 frag(Varyings IN) : SV_Target
            {
                half4 color = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv) * _BaseColor;
                half2 effectUV = IN.uv;

                _MainGradientSlide = remap (0,1,-1,1,_MainGradientSlide);
                float uvMaskY =   step (0,effectUV.y   + _MainGradientSlide) - step(1, effectUV.y+ _MainGradientSlide);
                effectUV.y *= uvMaskY;

                
                float wideSignWave =(1  - pow (abs(cos(PI * (IN.uv.y + _MainGradientSlide))), 1.5)) * uvMaskY ;
                float thinSignWave =(1  - pow (abs(cos(PI * (IN.uv.y + _MainGradientSlide)* 2)), 4)) * uvMaskY ;
   
                return float4 (wideSignWave, thinSignWave, 0,1);
                return color;
            }
            ENDHLSL
        }
    }
}
