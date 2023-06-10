Shader "Hidden/S_Composite"
{
    
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
            

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            sampler2D _MainTex;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                return o;
            }

        
            fixed4 frag (v2f i) : SV_Target
            {
                fixed4 scene = tex2D(_MainTex,i.uv);
                return scene;
            }
            ENDCG
        }
        Pass
        {
            Blend SrcAlpha OneMinusSrcAlpha
            //BlendOp Screen
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"
            
            

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            sampler2D _MainTex,_CloudCol,_CloudMask,_CloudDepth,_CameraDepthTexture,_CloudAlpha;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                return o;
            }

        
            fixed4 frag (v2f i) : SV_Target
            {

                fixed4 cloud = tex2D(_CloudCol, i.uv);
                //const float  cloudAlpha= tex2D(_CloudAlpha,i.uv);
                //cloud.a = 1;
                //cloud.a = cloudAlpha;
                //float sceneDepth = tex2D(_CameraDepthTexture,i.uv);
                //sceneDepth = LinearEyeDepth(sceneDepth);
                //const float cloudDepth = tex2D(_CloudDepth,i.uv);
                //const fixed4 cloudMask = tex2D(_CloudMask,i.uv);

                return cloud;
 
            }
            ENDCG
        }
    }
}
