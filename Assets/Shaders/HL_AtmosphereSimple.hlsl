#ifndef ATMOSPHERE_SIMPLE_INCLUDED
#define ATMOSPHERE_SIMPLE_INCLUDED

// ============================================================================
// CONSTANTS AND DEFINES
// ============================================================================

#define ATMOSPHERE_INSCATTERING_SAMPLE_COUNT 100
#define ATMOSPHERE_MARCH_FRACTION_PER_STEP  1.0 / (ATMOSPHERE_INSCATTERING_SAMPLE_COUNT - 1.0)
#define ATMOSPHERE_MAX_DISTANCE 10000.0
#define ATMOSPHERE_RAYLEIGH_CHANNEL_WEIGHT 0.3333333
#define ATMOSPHERE_MIE_ABSORPTION_SCALE 0.01
#define ATMOSPHERE_MARCH_OFFSET 0.01

// ============================================================================
// TEXTURES AND SAMPLERS
// ============================================================================

sampler2D _CameraOpaqueTexture;
sampler2D _CameraDepthTexture;
sampler2D _OpticalDepthTexture;

// ============================================================================
// CAMERA PARAMETERS
// ============================================================================

float _Camera_Near;
float _Camera_Far;
float _EarthRadius;

// ============================================================================
// SAMPLING PARAMETERS
// ============================================================================

uint _NumInScatteringSample;
uint _NumOpticalDepthSample;

// ============================================================================
// RAYLEIGH SCATTERING PARAMETERS
// ============================================================================

float _Rs_Thickness;
float _Rs_DensityFalloff;
float _Rs_Absorbsion_1;
float _Rs_DensityMultiplier_1;
float _Rs_ChannelSplit_1;
float4 _Rs_ScatterWeight_1;
float4 _Rs_InsColor_1;

float _Rs_Absorbsion_2;
float _Rs_DensityMultiplier_2;
float _Rs_ChannelSplit_2;
float4 _Rs_ScatterWeight_2;
float4 _Rs_InsColor_2;

// ============================================================================
// MIE SCATTERING PARAMETERS
// ============================================================================

float _Ms_Thickness;
float _Ms_DensityFalloff;
float _Ms_Absorbsion_1;
float _Ms_DensityMultiplier_1;
float _Ms_Anisotropic_1;
float4 _Ms_InsColor_1;

float _Ms_Absorbsion_2;
float _Ms_DensityMultiplier_2;
float _Ms_Anisotropic_2;
float4 _Ms_InsColor_2;

// ============================================================================
// SPHERE MASK PARAMETERS
// ============================================================================

float3 _SphereMaskCenter;
float _SphereMaskRadius;
float _SphereMaskBlend;

// ============================================================================
// RENDERING FLAGS
// ============================================================================

bool _VolumeOnly = false;

// ============================================================================
// INCLUDES
// ============================================================================

#include "../INCLUDE/HL_AtmosphereHelper.hlsl"

// ============================================================================
// STRUCTURES
// ============================================================================

struct AtmosphereVertexInput
{
    float4 positionOS : POSITION;
    uint vertexID : SV_VertexID;
    float2 uv : TEXCOORD0;
};

struct AtmosphereVertexOutput
{
    float2 uv : TEXCOORD0;
    float4 positionCS : SV_POSITION;
    float3 viewDirection : TEXCOORD1;
};

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

/**
 * Converts non-linear depth to linear eye depth
 * @param depth Non-linear depth value
 * @return Linear eye depth
 */
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

/**
 * Samples optical depth from pre-baked texture
 * @param rayOrigin Origin of the ray
 * @param rayDirection Direction of the ray
 * @return Optical depth data (x: rayleigh sun, y: rayleigh view, z: mie sun, w: mie view)
 */
float4 SampleOpticalDepth(float3 rayOrigin, float3 rayDirection)
{
    float3 earthCenter = float3(0.0, -_EarthRadius, 0.0);
    float3 relativeDistanceToCenter = rayOrigin - earthCenter;
    float distanceAboveGround = length(relativeDistanceToCenter) - _EarthRadius;
    float heightNormalized = distanceAboveGround / _Rs_Thickness;
    
    float zenithAngle = dot(normalize(relativeDistanceToCenter), rayDirection);
    float angleNormalized = 1.0 - (zenithAngle * 0.5 + 0.5);
    
    return tex2D(_OpticalDepthTexture, float2(angleNormalized, heightNormalized));
}

// ============================================================================
// VERTEX SHADER
// ============================================================================

AtmosphereVertexOutput vert(AtmosphereVertexInput input)
{
    AtmosphereVertexOutput output;

#if SHADER_API_GLES
    float4 position = input.positionOS;
    float2 uv = input.uv;
#else
    float4 position = GetFullScreenTriangleVertexPosition(input.vertexID);
    float2 uv = GetFullScreenTriangleTexCoord(input.vertexID);
#endif

    output.positionCS = position;
    output.uv = uv;
    
    // Calculate view direction in world space
    float3 viewVector = mul(unity_CameraInvProjection, float4(uv.xy * 2.0 - 1.0, 0.0, -1.0)).xyz;
    output.viewDirection = mul(unity_CameraToWorld, float4(viewVector, 0.0)).xyz;
    
    return output;
}

// ============================================================================
// ATMOSPHERIC SCATTERING CALCULATION
// ============================================================================

/**
 * Calculates atmospheric scattering using pre-baked optical depth
 * @param rayOrigin Origin of the ray
 * @param rayDirection Direction of the ray
 * @param sunDirection Direction to the sun
 * @param distance Distance through the atmosphere
 * @param uv Screen UV coordinates
 * @param inscatteredLight Output: Inscattered light color
 * @param transmittance Output: Transmittance factor
 */
void CalculateAtmosphericScattering(
    float3 rayOrigin,
    float3 rayDirection,
    float3 sunDirection,
    float distance,
    float2 uv,
    out float3 inscatteredLight,
    out float3 transmittance)
{
    float stepSize = distance *  ATMOSPHERE_MARCH_FRACTION_PER_STEP;
    float3 samplePosition = rayOrigin;

    // Initialize scattering parameters
    float rayleighPhase =PhaseFunction(dot(sunDirection, rayDirection), 0.0);
    float miePhase = PhaseFunction(dot(sunDirection, rayDirection), _Ms_Anisotropic_1);
    float mieFinalPhase = 0.0;

    // Optical depth accumulators
    float rayleighViewRayOpticalDepth = 0.0;
    float mieViewRayOpticalDepth = 0.0;
    
    // Inscattered light accumulators
    float3 rayleighInscatterLight = 0.0;
    float3 mieInscatterLight = 0.0;
    
    // Scattering weight accumulators
    float3 rayleighFinalScatteringWeight = 0.0;
    float mieFinalScatteringWeight = 0.0;
    
    // Density multipliers
    float rayleighDensityMultiplier = _Rs_DensityMultiplier_1;
    float mieDensityMultiplier = _Ms_DensityMultiplier_1;
    
    // Scattering weights
    float3 rayleighScatteringWeight = lerp(
        length(_Rs_ScatterWeight_1.xyz) * ATMOSPHERE_RAYLEIGH_CHANNEL_WEIGHT,
        _Rs_ScatterWeight_1.xyz,
        _Rs_ChannelSplit_1
    ) * _Rs_Absorbsion_1;
    
    float mieScatteringWeight = _Ms_Absorbsion_1 * ATMOSPHERE_MIE_ABSORPTION_SCALE;
    

    // Main scattering loop
    [unroll]
    for (uint sampleIndex = 0; sampleIndex <= ATMOSPHERE_INSCATTERING_SAMPLE_COUNT; ++sampleIndex)
    {
        // Sample optical depth from pre-baked texture
        float4 opticalDepthData = SampleOpticalDepth(samplePosition, sunDirection);
        
        // Accumulate scattering weights
        rayleighFinalScatteringWeight += rayleighScatteringWeight * ATMOSPHERE_MARCH_FRACTION_PER_STEP * opticalDepthData.y * rayleighDensityMultiplier;
        mieFinalScatteringWeight += mieScatteringWeight * ATMOSPHERE_MARCH_FRACTION_PER_STEP * opticalDepthData.w * mieDensityMultiplier;
        
        // Accumulate phase function
        mieFinalPhase += miePhase * ATMOSPHERE_MARCH_FRACTION_PER_STEP;
        
        // Calculate local densities
        float rayleighLocalDensity = opticalDepthData.y * stepSize * rayleighDensityMultiplier;
        float rayleighSunRayOpticalDepth = opticalDepthData.x * rayleighDensityMultiplier;
        
        float mieLocalDensity = opticalDepthData.w * stepSize * mieDensityMultiplier;
        float mieSunRayOpticalDepth = opticalDepthData.z * mieDensityMultiplier;
        
        // Accumulate optical depths
        rayleighViewRayOpticalDepth += rayleighLocalDensity;
        mieViewRayOpticalDepth += mieLocalDensity;
        
        // Calculate transmittance
        float3 rayleighTau = (rayleighViewRayOpticalDepth + rayleighSunRayOpticalDepth) * rayleighScatteringWeight;
        float3 mieTau = (mieViewRayOpticalDepth + mieSunRayOpticalDepth) * mieScatteringWeight;
        float3 totalTransmittance = exp(-rayleighTau - mieTau);
        
        // Accumulate inscattered light
        rayleighInscatterLight += totalTransmittance * rayleighLocalDensity * _Rs_InsColor_1.xyz * rayleighScatteringWeight;
        mieInscatterLight += totalTransmittance * mieLocalDensity * _Ms_InsColor_1.xyz * mieScatteringWeight;
        
        // Advance sample position
        samplePosition += rayDirection * stepSize;
    }
    
    // Apply phase functions
    rayleighInscatterLight *= rayleighPhase;
    mieInscatterLight *= mieFinalPhase;
    
    // Calculate final scattering weight and transmittance
    float3 finalScatteringWeight = max(rayleighFinalScatteringWeight, mieFinalScatteringWeight);
    transmittance = exp(-rayleighViewRayOpticalDepth * finalScatteringWeight - mieViewRayOpticalDepth * finalScatteringWeight);
    
    // Combine inscattered light
    inscatteredLight = mieInscatterLight + rayleighInscatterLight;
}

// ============================================================================
// FRAGMENT SHADER
// ============================================================================

float4 frag(AtmosphereVertexOutput input) : SV_Target
{
    // Initialize ray parameters
    float3 rayOrigin = _WorldSpaceCameraPos;
    float3 rayDirection = normalize(input.viewDirection);
    
    // Sample scene depth
    float sceneDepthNonLinear = tex2D(_CameraDepthTexture, input.uv).x;
    float sceneDepth = ConvertToLinearEyeDepth(sceneDepthNonLinear);
    
    // Get main light direction
    Light mainLight = GetMainLight();
    
    // Calculate intersection with atmosphere sphere
    float3 earthCenter = float3(0.0, -_EarthRadius, 0.0);
    float2 hitInfo = RaySphere(earthCenter, _EarthRadius + _Rs_Thickness, rayOrigin, rayDirection);
    float distanceThroughVolume = min(hitInfo.y, max(sceneDepth - hitInfo.x, 0.0));
    
    // Sample scene color
    float4 sceneColor = tex2D(_CameraOpaqueTexture, input.uv);
    
    // Early exit if no volume intersection
    if (distanceThroughVolume <= 0.0)
    {
        return sceneColor;
    }
    
    // Calculate atmospheric scattering
    float3 inscatteredLight = 0.0;
    float3 transmittance = 0.0;
    
    float3 marchStart = rayOrigin + rayDirection * (hitInfo.x + ATMOSPHERE_MARCH_OFFSET);
    CalculateAtmosphericScattering(
        marchStart,
        rayDirection,
        mainLight.direction,
        distanceThroughVolume,
        input.uv,
        inscatteredLight,
        transmittance
    );
    
    // Combine with scene color
    float3 finalColor = _VolumeOnly ? inscatteredLight : inscatteredLight + transmittance * sceneColor.xyz;
    
    return float4(finalColor, 1.0);
}

#endif // ATMOSPHERE_SIMPLE_INCLUDED