#ifndef MY_CUSTOM_BRDF_INCLUDED
#define MY_CUSTOM_BRDF_INCLUDED

//=============================================================================
// MY CUSTOM BRDF - A step-by-step recreation of Unity URP's PBR lighting
//=============================================================================
//
// This file replicates the logic from Unity URP's lighting system.
// Reference files in URP package (com.unity.render-pipelines.universal):
//   - ShaderLibrary/Lighting.hlsl         -> UniversalFragmentPBR, LightingPhysicallyBased
//   - ShaderLibrary/BRDF.hlsl             -> BRDFData, DirectBRDF, EnvironmentBRDF
//   - ShaderLibrary/GlobalIllumination.hlsl -> GlobalIllumination, GlossyEnvironmentReflection
//   - ShaderLibrary/RealtimeLights.hlsl   -> Light struct, GetMainLight, GetAdditionalLight
//   - ShaderLibrary/Shadows.hlsl          -> Shadow sampling functions
//   - ShaderLibrary/SurfaceInput.hlsl     -> SurfaceData struct
//   - ShaderLibrary/Input.hlsl            -> InputData struct
//
// The final color is computed as:
//   color = DirectLighting + IndirectLighting + Emission
//   DirectLighting = MainLightContribution + AdditionalLightsContribution
//   IndirectLighting = GI_Diffuse + GI_Specular
//
//=============================================================================

//-----------------------------------------------------------------------------
// CONSTANTS
// Reference: BRDF.hlsl
//-----------------------------------------------------------------------------
#define PI 3.14159265359
#define HALF_MIN 6.103515625e-5  // 2^-14, minimum positive half precision
#define HALF_MIN_SQRT 0.0078125  // sqrt(HALF_MIN)
#define MEDIUMP_FLT_MAX 65504.0

//-----------------------------------------------------------------------------
// BRDF DATA STRUCTURE
// Reference: BRDF.hlsl -> struct BRDFData
//
// This structure holds pre-computed values needed for BRDF calculations.
// It converts artist-friendly parameters (metallic, smoothness) into
// physically-based values (diffuse, specular, roughness).
//-----------------------------------------------------------------------------
struct MyBRDFData
{
    half3 diffuse;              // Diffuse color (albedo * (1 - metallic))
    half3 specular;             // Specular color (lerp(0.04, albedo, metallic) for metals)
    half perceptualRoughness;   // Artist roughness (1 - smoothness)
    half roughness;             // Squared perceptual roughness (for GGX)
    half roughness2;            // roughness^2 (used in D term)
    half grazingTerm;           // For Fresnel at grazing angles (1 - roughness) * saturate(1.8 - metallic)
    half normalizationTerm;     // (roughness + 0.5) * 4.0 for energy normalization
    half roughness2MinusOne;    // roughness^2 - 1 (optimization for D term)
};

//-----------------------------------------------------------------------------
// INITIALIZE BRDF DATA
// Reference: BRDF.hlsl -> InitializeBRDFData()
//
// Converts SurfaceData (metallic workflow) into BRDFData.
// Key insight: Metals have colored specular and no diffuse.
//              Dielectrics have white(ish) specular and colored diffuse.
//-----------------------------------------------------------------------------
MyBRDFData MyInitializeBRDFData(half3 albedo, half metallic, half smoothness)
{
    MyBRDFData brdfData = (MyBRDFData)0;
    
    // Dielectric F0 reflectance at normal incidence (4% for most materials)
    // Reference: BRDF.hlsl -> kDielectricSpec = half4(0.04, 0.04, 0.04, 1.0 - 0.04)
    half3 dielectricSpec = half3(0.04, 0.04, 0.04);
    half oneMinusDielectricSpec = 1.0 - 0.04; // = 0.96
    
    // Metallic workflow:
    // - Metals: specular = albedo, diffuse = 0
    // - Dielectrics: specular = 0.04, diffuse = albedo
    half oneMinusMetallic = 1.0 - metallic;
    
    brdfData.diffuse = albedo * oneMinusDielectricSpec * oneMinusMetallic;
    brdfData.specular = lerp(dielectricSpec, albedo, metallic);
    
    // Roughness conversion
    // perceptualRoughness = 1 - smoothness (artist friendly)
    // roughness = perceptualRoughness^2 (physically correct for GGX)
    brdfData.perceptualRoughness = 1.0 - smoothness;
    brdfData.roughness = max(brdfData.perceptualRoughness * brdfData.perceptualRoughness, HALF_MIN_SQRT);
    brdfData.roughness2 = max(brdfData.roughness * brdfData.roughness, HALF_MIN);
    brdfData.roughness2MinusOne = brdfData.roughness2 - 1.0;
    
    // Grazing term for environment BRDF Fresnel
    // At grazing angles, even rough surfaces become more reflective
    brdfData.grazingTerm = saturate(smoothness + (1.0 - oneMinusMetallic));
    
    // Normalization term for direct specular
    brdfData.normalizationTerm = brdfData.roughness * 4.0 + 2.0;
    
    return brdfData;
}

//=============================================================================
// STEP 1: FRESNEL TERM (F)
// Reference: BRDF.hlsl -> F_Schlick()
//
// The Fresnel effect describes how reflectivity changes based on view angle.
// At grazing angles (looking across surface), reflectivity approaches 100%.
// At normal incidence (looking straight at surface), reflectivity = F0.
//
// Schlick's approximation: F = F0 + (1 - F0) * (1 - cosTheta)^5
//=============================================================================
half3 MyFresnelSchlick(half3 F0, half cosTheta)
{
    // F0 = specular color (reflectance at normal incidence)
    // cosTheta = dot(N, H) for direct lighting, dot(N, V) for environment
    half t = 1.0 - cosTheta;
    half t2 = t * t;
    half t5 = t2 * t2 * t;  // (1 - cosTheta)^5
    return F0 + (1.0 - F0) * t5;
}

// Variant with custom max value for grazing angle (used in environment BRDF)
half3 MyFresnelSchlickRoughness(half3 F0, half cosTheta, half3 F90)
{
    half t = 1.0 - cosTheta;
    half t2 = t * t;
    half t5 = t2 * t2 * t;
    return F0 + (F90 - F0) * t5;
}

//=============================================================================
// STEP 2: NORMAL DISTRIBUTION FUNCTION (D) - GGX/Trowbridge-Reitz
// Reference: BRDF.hlsl -> D_GGX()
//
// Describes the statistical distribution of microfacet normals.
// Rough surfaces have normals spread out; smooth surfaces have normals aligned.
//
// D_GGX(h) = α² / (π * ((n·h)² * (α² - 1) + 1)²)
//
// Where α = roughness² (URP uses roughness directly, which is perceptualRoughness²)
//=============================================================================
half MyDistributionGGX(half NdotH, half roughness2)
{
    // NdotH = dot(normal, halfVector)
    // roughness2 = roughness^2 = (perceptualRoughness^2)^2 = perceptualRoughness^4
    
    half NdotH2 = NdotH * NdotH;
    half denom = NdotH2 * (roughness2 - 1.0) + 1.0;
    denom = denom * denom;
    
    return roughness2 / (PI * denom + HALF_MIN); // +HALF_MIN prevents division by zero
}

//=============================================================================
// STEP 3: GEOMETRY/VISIBILITY FUNCTION (G) - Smith-Schlick-GGX
// Reference: BRDF.hlsl -> V_SmithJointGGX()
//
// Describes self-shadowing of microfacets. Rough surfaces have more
// microfacets that block light from reaching or leaving other microfacets.
//
// URP uses the "visibility" formulation V = G / (4 * NdotL * NdotV)
// This is an optimization since the (4 * NdotL * NdotV) term cancels elsewhere.
//
// V_SmithGGX ≈ 0.5 / (NdotL * (NdotV * (1 - k) + k) + NdotV * (NdotL * (1 - k) + k))
// where k = roughness^2 / 2 for direct lighting (different for IBL)
//=============================================================================
half MyVisibilitySmithGGX(half NdotL, half NdotV, half roughness2)
{
    // Optimized Smith-GGX visibility term
    // Reference: BRDF.hlsl uses an approximation for mobile
    
    half lambdaV = NdotL * sqrt(NdotV * NdotV * (1.0 - roughness2) + roughness2);
    half lambdaL = NdotV * sqrt(NdotL * NdotL * (1.0 - roughness2) + roughness2);
    
    return 0.5 / (lambdaV + lambdaL + HALF_MIN);
}

// Simplified/approximated version (faster, used on mobile)
// Reference: BRDF.hlsl -> V_SmithJointGGXApprox()
half MyVisibilitySmithGGXApprox(half NdotL, half NdotV, half roughness)
{
    half a = roughness;
    half lambdaV = NdotL * (NdotV * (1.0 - a) + a);
    half lambdaL = NdotV * (NdotL * (1.0 - a) + a);
    return 0.5 / (lambdaV + lambdaL + HALF_MIN);
}

//=============================================================================
// STEP 4: DIRECT BRDF (Cook-Torrance)
// Reference: BRDF.hlsl -> DirectBRDF(), DirectBDRF()
//
// Combines all terms for direct (punctual) light contribution:
//   f = Diffuse + Specular
//   Diffuse = albedo / π (Lambertian)
//   Specular = D * G * F / (4 * NdotL * NdotV)
//
// With visibility term: Specular = D * V * F (V already has the 4*NdotL*NdotV)
//
// Energy conservation: what isn't reflected (specular) is diffused.
// F determines specular intensity, so diffuse is implicitly (1-F)*diffuse.
// URP approximates this with the pre-computed diffuse color.
//=============================================================================
half3 MyDirectBRDF(MyBRDFData brdfData, half3 normalWS, half3 lightDirWS, half3 viewDirWS)
{
    // Half vector - the "perfect mirror" direction for this light/view pair
    half3 halfDir = normalize(lightDirWS + viewDirWS);
    
    // Dot products (all clamped to avoid negative values)
    half NdotL = saturate(dot(normalWS, lightDirWS));
    half NdotV = saturate(dot(normalWS, viewDirWS));
    half NdotH = saturate(dot(normalWS, halfDir));
    half LdotH = saturate(dot(lightDirWS, halfDir));
    
    // Prevent NdotV = 0 causing division issues
    NdotV = max(NdotV, HALF_MIN);
    
    //-------------------------------------------------------------------------
    // SPECULAR TERM = D * V * F
    //-------------------------------------------------------------------------
    
    // D: How many microfacets are aligned with the half vector
    half D = MyDistributionGGX(NdotH, brdfData.roughness2);
    
    // V: Visibility/Geometry - microfacet shadowing/masking
    // URP uses an optimized approximation for performance
    // Reference: BRDF.hlsl line ~150
    half V = MyVisibilitySmithGGXApprox(NdotL, NdotV, brdfData.roughness);
    
    // F: Fresnel - use LdotH (same as VdotH due to half vector symmetry)
    half3 F = MyFresnelSchlick(brdfData.specular, LdotH);
    
    half3 specular = D * V * F;
    
    //-------------------------------------------------------------------------
    // DIFFUSE TERM = albedo / π (Lambertian diffuse)
    //-------------------------------------------------------------------------
    // Note: The 1/π is often baked into the light intensity in URP for efficiency.
    // brdfData.diffuse already accounts for metallic (metals have no diffuse).
    //
    // Energy conservation: Energy not reflected as specular goes to diffuse.
    // Proper: diffuse = (1 - F) * albedo / π
    // URP approx: Uses pre-multiplied diffuse color and skips (1-F) for performance.
    //-------------------------------------------------------------------------
    half3 diffuse = brdfData.diffuse;
    
    // Final direct BRDF (note: NdotL is applied in LightingPhysicallyBased)
    return diffuse + specular;
}

//=============================================================================
// STEP 5: ENVIRONMENT BRDF (Indirect Specular)
// Reference: BRDF.hlsl -> EnvironmentBRDF(), EnvironmentBRDFSpecular()
//
// For image-based lighting (IBL), we can't integrate over all light directions
// in real-time. Instead, we use the split-sum approximation:
//   L_spec = prefilteredColor * (F0 * scale + bias)
//
// Where scale/bias come from a pre-computed LUT (environment BRDF).
// URP approximates this with an analytical function.
//=============================================================================
half3 MyEnvironmentBRDF(MyBRDFData brdfData, half3 indirectDiffuse, half3 indirectSpecular, half NdotV)
{
    //-------------------------------------------------------------------------
    // INDIRECT DIFFUSE
    // Reference: GlobalIllumination.hlsl -> GlobalIllumination()
    //-------------------------------------------------------------------------
    // Just multiply the diffuse color by indirect irradiance (from SH or lightmaps)
    half3 diffuse = indirectDiffuse * brdfData.diffuse;
    
    //-------------------------------------------------------------------------
    // INDIRECT SPECULAR
    // Reference: BRDF.hlsl -> EnvironmentBRDFSpecular()
    //
    // Uses Fresnel with grazing term and a "surface reduction" factor
    // to approximate the environment BRDF integral.
    //-------------------------------------------------------------------------
    
    // Fresnel at this view angle, but capped by roughness (rough = less reflection)
    half3 F = MyFresnelSchlickRoughness(brdfData.specular, NdotV, half3(brdfData.grazingTerm, brdfData.grazingTerm, brdfData.grazingTerm));
    
    // Surface reduction - reduces reflectivity based on roughness
    // This approximates the integral of the visibility term over the hemisphere
    // Reference: BRDF.hlsl -> surfaceReduction = 1.0 / (roughness^2 + 1.0)
    half surfaceReduction = 1.0 / (brdfData.roughness2 + 1.0);
    
    half3 specular = indirectSpecular * F * surfaceReduction;
    
    return diffuse + specular;
}

//=============================================================================
// STEP 6: GLOBAL ILLUMINATION (GI)
// Reference: GlobalIllumination.hlsl -> GlobalIllumination()
//
// GI has two components:
// 1. Diffuse GI: From spherical harmonics (SH) or lightmaps
// 2. Specular GI: From reflection probes (cubemaps)
//=============================================================================

// Sample spherical harmonics for diffuse GI
// Reference: EntityLighting.hlsl -> SampleSH()
// Note: This function is in Core RP, we assume SampleSH is available from includes
half3 MyGIDiffuse(half3 bakedGI, half3 normalWS, half occlusion)
{
    // bakedGI is pre-sampled (SampleSH called in vertex or fragment)
    // Apply occlusion to reduce GI in occluded areas
    return bakedGI * occlusion;
}

// Sample reflection probe for specular GI
// Reference: GlobalIllumination.hlsl -> GlossyEnvironmentReflection()
// Note: This requires unity_SpecCube0 and related uniforms from Lighting.hlsl
half3 MyGISpecular(half3 reflectVector, half perceptualRoughness, half occlusion)
{
    // Convert roughness to mip level (rougher = blurrier = higher mip)
    // Reference: ImageBasedLighting.hlsl -> PerceptualRoughnessToMipmapLevel()
    // Cubemaps typically have 6-7 mip levels
    half mip = perceptualRoughness * (1.7 - 0.7 * perceptualRoughness) * 6.0; // UNITY_SPECCUBE_LOD_STEPS
    
    // Sample the reflection probe cubemap
    half4 encodedIrradiance = SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, reflectVector, mip);
    
    // Decode HDR (reflection probes store HDR data in RGBM or similar format)
    // Reference: EntityLighting.hlsl -> DecodeHDREnvironment()
    half3 irradiance = DecodeHDREnvironment(encodedIrradiance, unity_SpecCube0_HDR);
    
    return irradiance * occlusion;
}

//=============================================================================
// STEP 7: DIRECT LIGHT CONTRIBUTION
// Reference: Lighting.hlsl -> LightingPhysicallyBased()
//
// Combines BRDF with light properties:
//   contribution = BRDF * lightColor * lightAttenuation * NdotL
//=============================================================================
half3 MyLightingPhysicallyBased(MyBRDFData brdfData, Light light, half3 normalWS, half3 viewDirWS)
{
    // NdotL: Lambert's cosine law
    half NdotL = saturate(dot(normalWS, light.direction));
    
    // Light attenuation includes:
    // - Distance attenuation (for point/spot lights)
    // - Shadow attenuation
    // - Spot angle attenuation (for spot lights)
    half3 radiance = light.color * (light.distanceAttenuation * light.shadowAttenuation);
    
    // Final contribution = BRDF * Li * NdotL
    return MyDirectBRDF(brdfData, normalWS, light.direction, viewDirWS) * radiance * NdotL;
}

//=============================================================================
// STEP 8: MAIN LIGHT CALCULATION
// Reference: Lighting.hlsl -> UniversalFragmentPBR()
//
// The main directional light gets special treatment:
// - Always evaluated (no culling)
// - Uses cascaded shadow maps
// - May have light cookies
//=============================================================================
half3 MyCalculateMainLight(MyBRDFData brdfData, InputData inputData, half3 viewDirWS)
{
    // Get main light with shadows
    // Reference: RealtimeLights.hlsl -> GetMainLight()
    Light mainLight = GetMainLight(inputData.shadowCoord);
    
    // Apply shadow strength (allows artists to control shadow intensity)
    // mainLight.shadowAttenuation is already computed from shadow map sampling
    
    return MyLightingPhysicallyBased(brdfData, mainLight, inputData.normalWS, viewDirWS);
}

//=============================================================================
// STEP 9: ADDITIONAL LIGHTS CALCULATION
// Reference: Lighting.hlsl -> UniversalFragmentPBR() additional lights loop
//
// Point lights, spot lights, and other non-main lights.
// These are culled per-object or per-tile depending on rendering path.
//=============================================================================
half3 MyCalculateAdditionalLights(MyBRDFData brdfData, InputData inputData, half3 viewDirWS)
{
    half3 additionalLightColor = half3(0, 0, 0);
    
    // GetAdditionalLightsCount() returns number of lights affecting this object
    // Reference: RealtimeLights.hlsl -> GetAdditionalLightsCount()
    uint lightsCount = GetAdditionalLightsCount();
    
    for (uint i = 0; i < lightsCount; i++)
    {
        // GetAdditionalLight computes:
        // - Light direction (from position to light)
        // - Distance attenuation (falloff)
        // - Shadow attenuation (for shadow-casting additional lights)
        // Reference: RealtimeLights.hlsl -> GetAdditionalLight()
        Light light = GetAdditionalLight(i, inputData.positionWS);
        
        additionalLightColor += MyLightingPhysicallyBased(brdfData, light, inputData.normalWS, viewDirWS);
    }
    
    return additionalLightColor;
}

//=============================================================================
// STEP 10: COMPLETE GLOBAL ILLUMINATION
// Reference: GlobalIllumination.hlsl -> GlobalIllumination()
//
// Combines diffuse and specular indirect lighting.
//=============================================================================
half3 MyCalculateGlobalIllumination(MyBRDFData brdfData, InputData inputData, half3 viewDirWS, half occlusion)
{
    half NdotV = saturate(dot(inputData.normalWS, viewDirWS));
    
    //-------------------------------------------------------------------------
    // DIFFUSE GI (from spherical harmonics or lightmaps)
    //-------------------------------------------------------------------------
    half3 indirectDiffuse = MyGIDiffuse(inputData.bakedGI, inputData.normalWS, occlusion);
    
    //-------------------------------------------------------------------------
    // SPECULAR GI (from reflection probes)
    //-------------------------------------------------------------------------
    // Reflection vector for specular probe sampling
    half3 reflectVector = reflect(-viewDirWS, inputData.normalWS);
    
    half3 indirectSpecular = MyGISpecular(reflectVector, brdfData.perceptualRoughness, occlusion);
    
    //-------------------------------------------------------------------------
    // COMBINE using environment BRDF
    //-------------------------------------------------------------------------
    return MyEnvironmentBRDF(brdfData, indirectDiffuse, indirectSpecular, NdotV);
}

//=============================================================================
// FINAL STEP: MyCustomBRDF - Main Entry Point
// Reference: Lighting.hlsl -> UniversalFragmentPBR()
//
// This is the equivalent of UniversalFragmentPBR.
// It orchestrates all the lighting calculations.
//
// Final output = DirectLighting + IndirectLighting + Emission
// Then fog is applied.
//=============================================================================
half4 MyCustomBRDF(InputData inputData, SurfaceData surfaceData)
{
    //=========================================================================
    // STEP A: Initialize BRDF Data from Surface Data
    // Convert artist parameters to physically-based values
    //=========================================================================
    MyBRDFData brdfData = MyInitializeBRDFData(
        surfaceData.albedo,
        surfaceData.metallic,
        surfaceData.smoothness
    );
    
    // View direction (from surface to camera)
    half3 viewDirWS = inputData.viewDirectionWS;
    
    //=========================================================================
    // STEP B: Calculate Direct Lighting
    // Contribution from all real-time lights
    //=========================================================================
    
    // Main directional light (sun)
    half3 directLighting = MyCalculateMainLight(brdfData, inputData, viewDirWS);
    
    // Additional lights (point, spot, etc.)
    directLighting += MyCalculateAdditionalLights(brdfData, inputData, viewDirWS);

    
    //=========================================================================
    // STEP C: Calculate Indirect Lighting (Global Illumination)
    // Contribution from environment (probes, lightmaps, sky)
    //=========================================================================
    half3 indirectLighting = MyCalculateGlobalIllumination(
        brdfData,
        inputData,
        viewDirWS,
        surfaceData.occlusion
    );
    
    //=========================================================================
    // STEP D: Combine All Lighting Components
    //=========================================================================
    half3 color = half3(0, 0, 0);
    
    // Direct lighting (main light + additional lights)
    color += directLighting;
    
    // Indirect lighting (GI diffuse + GI specular)
    color += indirectLighting;
    
    // Emission (self-illumination, unaffected by lighting)
    color += surfaceData.emission;
    
    //=========================================================================
    // STEP E: Apply Fog
    // Reference: ShaderVariablesFunctions.hlsl -> MixFog()
    //
    // Fog blends the surface color toward the fog color based on distance.
    // fogFactor is computed per-vertex using ComputeFogFactor().
    //=========================================================================
    color = MixFog(color, inputData.fogCoord);
    
    //=========================================================================
    // FINAL OUTPUT
    //=========================================================================
    return half4(color, surfaceData.alpha);
}

//=============================================================================
// SUMMARY OF THE PBR PIPELINE:
//=============================================================================
//
// 1. SURFACE DATA (artist input)
//    - Albedo, Metallic, Smoothness, Normal, Occlusion, Emission
//
// 2. BRDF DATA (derived)
//    - Diffuse color = albedo * (1 - metallic)
//    - Specular color = lerp(0.04, albedo, metallic)
//    - Roughness = (1 - smoothness)²
//
// 3. DIRECT LIGHTING (per light)
//    - For each light:
//      a. Calculate half vector H = normalize(L + V)
//      b. D term: GGX distribution - how many microfacets aligned with H
//      c. G term: Smith visibility - microfacet shadowing
//      d. F term: Schlick Fresnel - angle-dependent reflectivity
//      e. Specular = D * G * F / (4 * NdotL * NdotV)
//      f. Diffuse = albedo / π (Lambertian)
//      g. Total = (Diffuse + Specular) * lightColor * attenuation * NdotL
//
// 4. INDIRECT LIGHTING (environment)
//    - Diffuse: Sample spherical harmonics with normal
//    - Specular: Sample reflection probe with reflection vector
//    - Apply environment BRDF (Fresnel + surface reduction)
//
// 5. FINAL COMPOSITION
//    - Color = Direct + Indirect + Emission
//    - Apply fog based on distance
//
// 6. ENERGY CONSERVATION
//    - What isn't reflected (specular) becomes diffuse
//    - Metals reflect their albedo color, so diffuse → 0
//    - Dielectrics reflect ~4%, rest goes to diffuse
//    - Roughness reduces specular intensity (spreads energy over hemisphere)
//
//=============================================================================

#endif // MY_CUSTOM_BRDF_INCLUDED

