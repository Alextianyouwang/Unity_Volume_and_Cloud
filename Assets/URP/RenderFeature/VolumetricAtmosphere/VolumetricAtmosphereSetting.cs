using System;
using UnityEngine;
using UnityEngine.Rendering;

[Serializable]
public class VolumetricAtmosphereSetting {
    [Header("Configuration")]
    public FloatParameter EarthRadius = new FloatParameter(5000f, false);


    [Header("Rayleigh Scattering")]
    public ClampedFloatParameter AtmosphereDensityFalloff = new ClampedFloatParameter(1f, 1f, 10f, false);
    public ClampedFloatParameter AtmosphereDensityMultiplier = new ClampedFloatParameter(1f, 0f, 3f, false);
    public ColorParameter AtmosphereInscatteringTint = new ColorParameter(Color.white, true, false, true);
    public ClampedFloatParameter AtmosphereUniformAbsorbsion = new ClampedFloatParameter(0.1f, 0f, 1f, false);
    public ColorParameter AtmosphereAbsorbsionWeightPerChannel = new ColorParameter(new Color(0.01f, 0.03f, 0.08f), false, false, true);
    public ClampedFloatParameter AtmosphereChannelSplit = new ClampedFloatParameter(1, 0f, 1f, false);

    [Header("Mie Scattering")]
    public FloatParameter AerosolsHeight = new FloatParameter(20f, false);
    public ClampedFloatParameter AerosolsDensityFalloff = new ClampedFloatParameter(1f, 1f, 10f, false);
    public ClampedFloatParameter AerosolsDensityMultiplier = new ClampedFloatParameter(1f, 0f, 3f, false);
    public ColorParameter AerosolsInscatteringTint = new ColorParameter(Color.white, true, false, true);
    public ClampedFloatParameter AerosolsUniformAbsorbsion = new ClampedFloatParameter(0.1f, 0f, 1f, false);
    public ClampedFloatParameter AerosolsAnistropic = new ClampedFloatParameter(0.7f, 0f, 1f, false);
}
