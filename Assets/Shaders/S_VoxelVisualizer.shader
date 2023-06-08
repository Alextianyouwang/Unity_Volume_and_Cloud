Shader "Hidden/S_VoxelVisualizer"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"
            #include "AutoLight.cginc"

            StructuredBuffer<int> _SmokeVoxels;
            float3 _BoundsExtent;
            uint3 _VoxelResolution;
            float _VoxelSize;

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal : NORMAL;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                float3 normal : TEXCOORD1;
                float3 hashCol  :TEXCOORD2;
                
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;

            float hash(uint n) {
                // integer hash copied from Hugo Elias
                n = (n << 13U) ^ n;
                n = n * (n * n * 15731U + 0x789221U) + 0x1376312589U;
                return float(n & uint(0x7fffffffU)) / float(0x7fffffff);
            }

            v2f vert (appdata v, uint instanceID : SV_INSTANCEID)
            {
               uint x = instanceID % (_VoxelResolution.x);
                uint y = (instanceID / _VoxelResolution.x) % _VoxelResolution.y;
                uint z = instanceID / (_VoxelResolution.x * _VoxelResolution.y);
                v2f o;
                o.vertex = UnityObjectToClipPos((v.vertex + float3(x, y, z)) * _VoxelSize + (_VoxelSize * 0.5f) - _BoundsExtent);
                o.normal = UnityObjectToWorldNormal(v.normal);
                o.hashCol = float3(hash(instanceID),hash(instanceID*instanceID),hash(instanceID*instanceID*instanceID));
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                fixed4 col = tex2D(_MainTex, i.uv);
                const float NdotL = (dot(i.normal,_WorldSpaceLightPos0) + 1)/2;
                return fixed4 (i.hashCol * NdotL * col,1);
            }
            ENDCG
        }
    }
}
