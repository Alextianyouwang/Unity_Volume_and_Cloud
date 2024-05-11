using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

[Serializable, VolumeComponentMenuForRenderPipeline("Custom/Volumetric Atmosphere With Blending", typeof(UniversalRenderPipeline))]
public class VolumetricAtmosphereBlendingComponent : VolumeComponent, IPostProcessComponent
{
    public BoolParameter Enabled = new BoolParameter(false, BoolParameter.DisplayType.Checkbox, true);
    public ClampedIntParameter OpticalDepthSamples = new ClampedIntParameter(50, 1, 100, false);
    public ClampedIntParameter InscatteringSamples = new ClampedIntParameter(30, 1, 50, false);
    public BoolParameter EnableRayleighScattering = new BoolParameter(true, BoolParameter.DisplayType.Checkbox, true);
    public BoolParameter EnableMieScattering = new BoolParameter(true, BoolParameter.DisplayType.Checkbox, true);
    public BoolParameter VolumePassOnly = new BoolParameter(false, BoolParameter.DisplayType.Checkbox, true);
    public ObjectParameter<VolumetricAtmosphereSetting> VA_Setting1 = new ObjectParameter<VolumetricAtmosphereSetting>(new VolumetricAtmosphereSetting());
    public ObjectParameter<VolumetricAtmosphereSetting> VA_Setting2 = new ObjectParameter<VolumetricAtmosphereSetting>(new VolumetricAtmosphereSetting());

    public bool IsTileCompatible()
    {
        return true;
    }

    public bool IsActive()
    {
        return Enabled.value;
    }

    public VolumetricAtmosphereBlendingComponent() : base()
    {
        displayName = "Volumetric Atmosphere With Blending";
    }


}
