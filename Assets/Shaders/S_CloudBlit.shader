Shader "Custom/S_CloudBlit"
{   

    Properties
    {
        _BoxRotation ("BoxRotationInAngle", Float) = 0
        _CloudGlobalDensityMultiplier ("Cloud Global Density Multiplier", Float) = 1.0
        _Octave ("Octave", Int) = 5
        _Persistance ("Persistance", Float) = 1
        _Lacunarity ("Lacunarity", Float) = 1
        _Multiscattering_DensityAttenuation ("Multiscattering DensityAttenuation", Range (0,1)) = 0.5
        _Multiscattering_PhaseFunctionShift ("Multiscattering DensityAttenuation", Range (0,0.3)) = 0.15
        _AmbientUpColor ("AmbientUpColor", Color) = (0.5,0.5,0.5,0.5)
        _AmbientDownColor ("AmbientDownColor", Color) = (0.5,0.5,0.5,0.5)
        _CloudPhaseLUT ("CloudPhaseLUT", 2D) = "white" {}

    }
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
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile _ EVALUATE_SH_MIXED EVALUATE_SH_VERTEX
            #pragma multi_compile _ LIGHTMAP_ON

            float3 _BoxMin;
            float3 _BoxMax;

            float _CloudGlobalDensityMultiplier;
            int   _Octave;
            float _Persistance;
            float _Lacunarity;
            float _Camera_Near, _Camera_Far;

            float4 _AmbientUpColor;
            float4 _AmbientDownColor;

            sampler2D _CameraDepthTexture;
            sampler2D _CloudPhaseLUT;
            float4 _CloudPhaseLUT_TexelSize;
            
            // Custom volumetric light data (passed from C#)
            #define MAX_VOLUMETRIC_LIGHTS 8
            int _VolumetricLightCount;
            float4 _VolumetricLightPositions[MAX_VOLUMETRIC_LIGHTS];
            float4 _VolumetricLightColors[MAX_VOLUMETRIC_LIGHTS];
            float _VolumetricLightRanges[MAX_VOLUMETRIC_LIGHTS];
            float  _Multiscattering_DensityAttenuation;
            float _Multiscattering_PhaseFunctionShift;
            float _BoxRotation;

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "../Resources/HL_Noise.hlsl"

            #define STEP_COUNT 32
            #define STEP_COUNT_SUNRAY 4
            #define USE_BOX_ROTATION

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
                #ifdef USE_BOX_ROTATION
                    float theta = radians(_BoxRotation);
                    float3 x = float3 (cos (theta), 0, -sin(theta));
                    float3 y = float3 (0, 1, 0);
                    float3 z = float3 (sin (theta), 0, cos(theta));
                    float3x3 rotationMatrix = float3x3(x, y, z);
                    rayOrigin = mul(rotationMatrix, rayOrigin);
                    rayDir = mul(rotationMatrix, rayDir);
                #endif
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


            float GetLocalDensity(float3 pos)
            {
                return _CloudGlobalDensityMultiplier * ( smoothstep( 0.3,0.8, WorleyFBM(pos * 0.01, _Octave,_Persistance,_Lacunarity)));
               // return _CloudGlobalDensityMultiplier * ( 1 - smoothstep( 0.2,0.8, Worley3D(pos * 0.1)));
            }

            float ResolveLightRayDepth(float3 direction, float3 origin) 
            {

                float sunRayDistance = 0;
                float2 sunRayIntersection = rayBoxDst(_BoxMin, _BoxMax, origin,direction);
                float sunRayStepSize = sunRayIntersection.y / STEP_COUNT_SUNRAY;
                float sunRayOpticalDepth = 0;
                for (int j = 0; j < STEP_COUNT_SUNRAY; j++)
                {
                    sunRayDistance += sunRayStepSize;
                    float3 sunRaySamplePoint = origin + direction * sunRayDistance;

                    float sunRaylocalDensity = GetLocalDensity(sunRaySamplePoint);
                    sunRayOpticalDepth += sunRayStepSize * sunRaylocalDensity;
                }
                return sunRayOpticalDepth;
            }

// Beer-Powder: used for LIGHT rays only (simulates powder/self-shadowing effect)
// The (1 - exp(-2d)) term adds extra darkening deep in the cloud
float BeerPowder(float d)
{
    return exp(-d) * (1 - exp(-2 * d));
}

// Standard Beer's law: used for VIEW ray transmittance
float Beer(float d)
{
    return exp(-d);
}

void PhaseFunction_float(float costheta, float g, out float phase)
{
    float g2 = g * g;
    float symmetry = (3 * (1 - g2)) / (2 * (2 + g2));
    phase = (1 + costheta * costheta) / pow(abs(1 + g2 - 2 * g * costheta), 1.5);
            
}
void DuelLobePhaseFunction_float(float costheta, float g1, float g2, float a, out float phase)
{
    float phase1;
    PhaseFunction_float(costheta, g1, phase1);
    float phase2;
    PhaseFunction_float(costheta, g2, phase2);
    phase = a * phase1 + (1 - a) * phase2;
}

float HGPhase(float cosTheta, float g)
{
    float g2 = g * g;
    float denom = pow(1.0 + g2 - 2.0 * g * cosTheta, 1.5);
    return (1.0 - g2) / denom;
}

float3 BakedPhase(float cosTheta) 
{
      // LUT method;
     float cosTheta01 = 1 - (cosTheta * 0.5 + 0.5);
     // Idk why have to add 0.504 it should be 0.5 but whatever...
     float correction = (cosTheta01 - 0.5) * (0.996) + 0.5;
     // Use tex2Dlod instead of tex2D - this is safe to call from loops
     // tex2D requires gradients which are undefined inside loops and can hang the compiler
     float3 phase_baked = tex2Dlod(_CloudPhaseLUT, float4(correction, 0, 0, 0)).rgb;

     return phase_baked ;
}

//https://www.youtube.com/watch?v=Qj_tK_mdRcA
float MultipleOctaveScattering(float density)
{
    float a = 1.0;
    float b = 1.0;
    float c = 0.85;

    float luminance = 0.0;
    [unroll]
    for (int i = 0; i < 4; i++)
    {
        float phaseFunction =BakedPhase(c);
        float beers = Beer(density * a);

        luminance += b * phaseFunction * beers;

        a *= _Multiscattering_DensityAttenuation;
        b *= 0.5;
        c -= _Multiscattering_PhaseFunctionShift;
    }

    return luminance;
}

            float3 CloudMarching(float3 rayOrigin, float3 rayDir, float rayLength, float depth, float3 viewDirVS, float3 viewDirWS, out float viewRayOpticalDepth) 
            {
                float stepSize = rayLength / STEP_COUNT;

                Light mainLight = GetMainLight();
                float3 mainLightDir = mainLight.direction;

                float viewRayDistance = 0;  
                float3 irradiance = 0;

                float cosTheta = dot(normalize(viewDirWS),normalize( mainLightDir));

                float phase_duelLobe;
                DuelLobePhaseFunction_float (cosTheta, 0.6, -0.5, 0.7, phase_duelLobe);
                phase_duelLobe *=  0.4;

                // multiply purely for artistic direction, since we are using single scattering, purly rely on the light intensity is not enough...
                float3 phase_baked = BakedPhase(cosTheta);
  
                float3 phase = phase_baked; 
                for (int i = 0; i < STEP_COUNT; i++)
                {
                    float3 samplePoint = rayOrigin + rayDir * viewRayDistance;
                    
                    // Early exit if we've passed the scene depth
                    if (distance(samplePoint, _WorldSpaceCameraPos) * dot(normalize(viewDirVS), float3(0,0,1)) > depth)
                        break;

                    float localDensity = GetLocalDensity(samplePoint);
                    viewRayOpticalDepth += localDensity * stepSize;
                    
                    float3 viewRayTransmittance = Beer(viewRayOpticalDepth);
                    
                    // === Main Directional Light ===
                    float sunRayOpticalDepth = ResolveLightRayDepth(mainLightDir, samplePoint);
                    // Light ray uses BeerPowder for the powder/self-shadowing effect
                    float3 sunRayTransmittance = MultipleOctaveScattering(sunRayOpticalDepth);
                    
                    float4 shadowCoord = TransformWorldToShadowCoord(samplePoint);
                    half shadow = MainLightRealtimeShadow(shadowCoord);

                
                float heightNorm = saturate((samplePoint.y - _BoxMin.y) / (_BoxMax.y - _BoxMin.y));
                float3 ambientColor = lerp(_AmbientDownColor,_AmbientUpColor, heightNorm);
   
                 //ambientColor = _GlossyEnvironmentColor.rgb

                    irradiance += mainLight.color * sunRayTransmittance * localDensity * stepSize * viewRayTransmittance * shadow * phase;
                     irradiance += ambientColor *  localDensity * stepSize * viewRayTransmittance;

                    // === Additional Point Lights (using custom volumetric light data) ===
                    for (int lightIdx = 0; lightIdx < _VolumetricLightCount; lightIdx++)
                    {
                        float3 lightPos = _VolumetricLightPositions[lightIdx].xyz;
                        float3 lightColor = _VolumetricLightColors[lightIdx].rgb;
                        float lightRange = _VolumetricLightRanges[lightIdx];
                        
                        float3 toLight = lightPos - samplePoint;
                        float distanceToLight = length(toLight);
                        
                        // Skip if outside light range
                        if (distanceToLight > lightRange)
                            continue;
                        
                        float3 lightDir = toLight / distanceToLight;
                        

                        float distanceAttenuation = saturate(1.0 - distanceToLight / lightRange);
                        distanceAttenuation *= distanceAttenuation;
                        
                        // March toward the light to calculate optical depth
                        float2 lightRayIntersection = rayBoxDst(_BoxMin, _BoxMax, samplePoint, lightDir);
                        float marchDistance = min(lightRayIntersection.y, distanceToLight);
                        float lightStepSize = marchDistance / STEP_COUNT_SUNRAY;
                        
                        float lightRayOpticalDepth = 0;
                        float lightRayDistance = 0;
                        
                        for (int k = 0; k < STEP_COUNT_SUNRAY; k++)
                        {
                            lightRayDistance += lightStepSize;
                            float3 lightRaySamplePoint = samplePoint + lightDir * lightRayDistance;
                            lightRayOpticalDepth += lightStepSize * GetLocalDensity(lightRaySamplePoint);
                        }
                        
                        float lightRayTransmittance = exp(-lightRayOpticalDepth);
                        
                        // Contribution from this point light
                        irradiance += lightColor * distanceAttenuation * lightRayTransmittance * localDensity * stepSize * viewRayTransmittance;
                    }

                    viewRayDistance += stepSize;
                }


                return irradiance;
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
                //if (distanceToCubeCameraForward > sceneDepth)
                //    return color;

                float totalRayLength =  min( (sceneDepth - distanceToCubeCameraForward),  intersection.y);
                float viewRayOpticalDepth = 0;
                float3 cloudRadiance = CloudMarching(rayOrigin + viewDirWS * intersection.x, viewDirWS, totalRayLength, sceneDepth, viewDirVS,viewDirWS, viewRayOpticalDepth );

                // Standard volume rendering compositing: in-scattered + attenuated background
                // Beer's law for transmittance (how much background shows through)
                float transmittance = Beer(viewRayOpticalDepth);
                
                // Powder term adds extra brightness at cloud edges (the "silver lining" effect)
                // This modulates the cloud's in-scattered light, NOT the background
                float powder = 1.0 - exp(-2.0 * viewRayOpticalDepth);
                
                // Apply powder effect to cloud radiance (boosts brightness at thin edges)
                float3 cloudWithPowder = cloudRadiance * powder;
                
                // Final composite: cloud (with powder effect) + attenuated background (standard Beer)
                float3 finalColor = cloudRadiance + color.rgb * transmittance;
                return float4(finalColor, 1);
            }
            
            ENDHLSL
        }
    }
}
