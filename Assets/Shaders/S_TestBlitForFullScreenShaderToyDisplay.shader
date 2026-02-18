Shader "Custom/S_TestBlitForFullScreenShaderToyDisplay"
{   
    Properties
    {

    }
    SubShader
    {
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
        ENDHLSL

        Pass
        {
            HLSLPROGRAM
            
            #pragma vertex Vert
            #pragma fragment Frag


// https://x.com/XorDev/status/1894123951401378051
float4 SpecialEffectExact(float2 FC, float2 r, float t)
{
    float4 o = 0.0;

    // Centered, aspect-correct coords
    float2 p = (FC * 2.0 - r) / r.y;

    // Explicit init (GLSL trick)
    float2 l = 0.0;
    float2 i = 0.0;

    // l += scalar (vector-scalar add)
    float scalar = 4.0 - 4.0 * abs(0.7 - dot(p, p));
    l += scalar;

    float2 v = p * l;

    // Loop with post-increment behavior
    while (i.y < 8.0)
    {
        i.y += 1.0;

        // o += (sin(v.xyyx) + 1) * abs(v.x - v.y)
        float4 s = sin(float4(v.x, v.y, v.y, v.x)) + 1.0;
        o += s * abs(v.x - v.y);

        // v += cos(v.yx * i.y + i + t) / i.y + .7
        v += cos(v.yx * i.y + i + t) / i.y + 0.7;
    }

    // Final nonlinear compression
    o = tanh(
        5.0 *
        exp(l.x - 4.0 - p.y * float4(-1.0, 1.0, 2.0, 0.0))
        / o
    );

    return o;
}

            float4 Frag (Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;
                float shape;
                float3 col = SpecialEffectExact(uv * _ScreenParams.xy, _ScreenParams.xy, _Time.y);
                return float4(col, 1);
            }
            
            ENDHLSL
        }
    }
}
