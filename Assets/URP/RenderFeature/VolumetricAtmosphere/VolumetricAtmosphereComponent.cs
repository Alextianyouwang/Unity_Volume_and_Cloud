using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

[VolumeComponentMenuForRenderPipeline("Custom/Volumetric Atmosphere", typeof(UniversalRenderPipeline))]
public class VolumetricAtmosphereComponent : VolumeComponent, IPostProcessComponent
{
    public BoolParameter Enabled = new BoolParameter(false, BoolParameter.DisplayType.Checkbox, true);

    [Header("Configuration")]
    public FloatParameter AtmosphereHeight = new FloatParameter(50f, false);
    public FloatParameter EarthRadius = new FloatParameter(5000f, false);

    public ClampedFloatParameter AtmosphereDensityFalloff = new ClampedFloatParameter(1f,1f,10f, false);
    public ClampedFloatParameter AtmosphereDensityMultiplier = new ClampedFloatParameter(1f, 0f, 3f, false);

    [Header("Shading")]
    [ColorUsage(true, true)]
    public ColorParameter InscatteringTint = new ColorParameter(new Color(0.3f,0.3f,0.3f),true,false, true);
    public ClampedFloatParameter UniformAbsorbsion = new ClampedFloatParameter(0.1f, 0f, 1f, false);
    public ClampedFloatParameter RayleighScattering = new ClampedFloatParameter(1f, 0f, 1f, false);
    public ColorParameter RayleighAbsorbsionWeightPerChannel = new ColorParameter(new Color(0.01f, 0.05f, 0.2f), false,false,true);

    public ClampedFloatParameter AnisotropicLevel = new ClampedFloatParameter(0.1f, 0f, 1f, false);

    [Header("Quality")]
    public ClampedIntParameter OpticalDepthSamples = new ClampedIntParameter(10, 1, 30, false);
    public ClampedIntParameter InScatteringSamples = new ClampedIntParameter(30, 1, 30, false);

    public bool IsTileCompatible()
    {
        return true;
    }

    public bool IsActive()
    {
        return Enabled.value;
    }
}
