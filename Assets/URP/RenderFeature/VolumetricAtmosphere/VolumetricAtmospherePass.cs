using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.RenderGraphModule.Util;
using UnityEngine.Rendering.Universal;

public class VolumetricAtmospherePass : ScriptableRenderPass
{
    private Material _blitMat;
    private RenderTexture _opticDepthTex_external;
    private ComputeShader _baker;
    private VolumetricAtmosphereBlendingComponent _volumeSettings;
    private bool _realtime;
    private bool _needsBake;

    public VolumetricAtmospherePass(string name)
    {
        profilingSampler = new ProfilingSampler(name);
    }

    public void SetData(ComputeShader baker, RenderTexture opticalDepthTex, Material blitMat, bool realtime)
    {
        _baker = baker;
        _opticDepthTex_external = opticalDepthTex;
        _blitMat = blitMat;
        _volumeSettings = VolumeManager.instance.stack.GetComponent<VolumetricAtmosphereBlendingComponent>();
        _realtime = realtime;

        // Check if bake is needed BEFORE render graph recording
        _needsBake = CheckIfBakeNeeded();
        if (_needsBake)
        {
            BakeOpticalDepthTexture();
        }
    }

    public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
    {
        // Early out if not ready
        if (_blitMat == null) return;
        if (_volumeSettings == null) return;
        if (!_volumeSettings.IsActive()) return;

        UniversalResourceData resourcesData = frameData.Get<UniversalResourceData>();
        UniversalCameraData cameraData = frameData.Get<UniversalCameraData>();

        // Create destination texture
        TextureHandle tempColor;
        TextureDesc targetDesc = renderGraph.GetTextureDesc(resourcesData.cameraColor);
        targetDesc.name = "AtmosphereBlitBuffer";
        targetDesc.clearBuffer = false;
        tempColor = renderGraph.CreateTexture(targetDesc);

        // Set material parameters
        SetMaterialParameters(cameraData);

        // Blit pass
        RenderGraphUtils.BlitMaterialParameters param = new(resourcesData.activeColorTexture, tempColor, _blitMat, 0);
        renderGraph.AddBlitPass(param, "Volumetric Atmosphere Pass");
        resourcesData.cameraColor = tempColor;
    }

    private void SetMaterialParameters(UniversalCameraData cameraData)
    {
        _blitMat.SetVector("_SphereMaskCenter", _volumeSettings.BlendCenter.value);
        _blitMat.SetFloat("_SphereMaskRadius", _volumeSettings.BlendRaidus.value);
        _blitMat.SetFloat("_SphereMaskBlend", _volumeSettings.BlendFalloff.value);

        LocalKeyword enableRealtime = new LocalKeyword(_blitMat.shader, "_USE_REALTIME");
        if (_realtime)
            _blitMat.EnableKeyword(enableRealtime);
        else
            _blitMat.DisableKeyword(enableRealtime);

        _blitMat.SetTexture("_OpticalDepthTexture", _opticDepthTex_external);
        _blitMat.SetFloat("_Camera_Near", cameraData.camera.nearClipPlane);
        _blitMat.SetFloat("_Camera_Far", cameraData.camera.farClipPlane);
        _blitMat.SetFloat("_EarthRadius", _volumeSettings.EarthRadius.value);
        _blitMat.SetInt("_NumOpticalDepthSample", _volumeSettings.OpticalDepthSamples.value);
        _blitMat.SetInt("_NumInScatteringSample", _volumeSettings.InscatteringSamples.value);

        _blitMat.SetFloat("_SphereMaskDistortBlend", _volumeSettings.BlendDistortFalloff.value);
        _blitMat.SetFloat("_DistorsionStrength", _volumeSettings.BlendDistortStrength.value);

        // Rayleigh Scattering
        LocalKeyword enableRayleigh = new LocalKeyword(_blitMat.shader, "_USE_RAYLEIGH");
        if (_volumeSettings.EnableRayleighScattering.value)
            _blitMat.EnableKeyword(enableRayleigh);
        else
            _blitMat.DisableKeyword(enableRayleigh);
        _blitMat.SetFloat("_Rs_Thickness", _volumeSettings.AtmosphereHeight.value);
        _blitMat.SetFloat("_Rs_DensityFalloff", _volumeSettings.AtmosphereDensityFalloff.value);

        _blitMat.SetFloat("_Rs_Absorbsion_1", _volumeSettings.AtmosphereUniformAbsorbsion_1.value);
        _blitMat.SetFloat("_Rs_DensityMultiplier_1", _volumeSettings.AtmosphereDensityMultiplier_1.value);
        _blitMat.SetFloat("_Rs_ChannelSplit_1", _volumeSettings.AtmosphereChannelSplit_1.value);
        _blitMat.SetColor("_Rs_ScatterWeight_1", _volumeSettings.AtmosphereAbsorbsionWeightPerChannel_1.value);
        _blitMat.SetColor("_Rs_InsColor_1", _volumeSettings.AtmosphereInscatteringTint_1.value);

        _blitMat.SetFloat("_Rs_Absorbsion_2", _volumeSettings.AtmosphereUniformAbsorbsion_2.value);
        _blitMat.SetFloat("_Rs_DensityMultiplier_2", _volumeSettings.AtmosphereDensityMultiplier_2.value);
        _blitMat.SetFloat("_Rs_ChannelSplit_2", _volumeSettings.AtmosphereChannelSplit_2.value);
        _blitMat.SetColor("_Rs_ScatterWeight_2", _volumeSettings.AtmosphereAbsorbsionWeightPerChannel_2.value);
        _blitMat.SetColor("_Rs_InsColor_2", _volumeSettings.AtmosphereInscatteringTint_2.value);

        // Mie Scattering
        LocalKeyword enableMie = new LocalKeyword(_blitMat.shader, "_USE_MIE");
        if (_volumeSettings.EnableMieScattering.value)
            _blitMat.EnableKeyword(enableMie);
        else
            _blitMat.DisableKeyword(enableMie);
        _blitMat.SetFloat("_Ms_Thickness", _volumeSettings.AerosolsHeight.value);
        _blitMat.SetFloat("_Ms_DensityFalloff", _volumeSettings.AerosolsDensityFalloff.value);

        _blitMat.SetFloat("_Ms_Absorbsion_1", _volumeSettings.AerosolsUniformAbsorbsion_1.value);
        _blitMat.SetFloat("_Ms_DensityMultiplier_1", _volumeSettings.AerosolsDensityMultiplier_1.value);
        _blitMat.SetFloat("_Ms_Anisotropic_1", _volumeSettings.AerosolsAnistropic_1.value);
        _blitMat.SetColor("_Ms_InsColor_1", _volumeSettings.AerosolsInscatteringTint_1.value);

        _blitMat.SetFloat("_Ms_Absorbsion_2", _volumeSettings.AerosolsUniformAbsorbsion_2.value);
        _blitMat.SetFloat("_Ms_DensityMultiplier_2", _volumeSettings.AerosolsDensityMultiplier_2.value);
        _blitMat.SetFloat("_Ms_Anisotropic_2", _volumeSettings.AerosolsAnistropic_2.value);
        _blitMat.SetColor("_Ms_InsColor_2", _volumeSettings.AerosolsInscatteringTint_2.value);

        _blitMat.SetInt("_VolumeOnly", _volumeSettings.VolumePassOnly.value ? 1 : 0);
    }

    // Cached values for dirty checking
    private float _cached_numOpticalDepthSample;
    private float _cached_rs_thickness;
    private float _cached_rs_densityFalloff;
    private float _cached_ms_thickness;
    private float _cached_ms_densityFalloff;
    private float _cached_earthRadius;

    private bool CheckIfBakeNeeded()
    {
        if (_volumeSettings == null) return false;

        bool needsBake = (
            _cached_numOpticalDepthSample != _volumeSettings.OpticalDepthSamples.value
            || _cached_rs_thickness != _volumeSettings.AtmosphereHeight.value
            || _cached_rs_densityFalloff != _volumeSettings.AtmosphereDensityFalloff.value
            || _cached_ms_thickness != _volumeSettings.AerosolsHeight.value
            || _cached_ms_densityFalloff != _volumeSettings.AerosolsDensityFalloff.value
            || _cached_earthRadius != _volumeSettings.EarthRadius.value
        );

        // Update cached values
        _cached_numOpticalDepthSample = _volumeSettings.OpticalDepthSamples.value;
        _cached_rs_thickness = _volumeSettings.AtmosphereHeight.value;
        _cached_rs_densityFalloff = _volumeSettings.AtmosphereDensityFalloff.value;
        _cached_ms_thickness = _volumeSettings.AerosolsHeight.value;
        _cached_ms_densityFalloff = _volumeSettings.AerosolsDensityFalloff.value;
        _cached_earthRadius = _volumeSettings.EarthRadius.value;

        return needsBake;
    }

    private void BakeOpticalDepthTexture()
    {
        if (_baker == null) return;
        if (_opticDepthTex_external == null) return;

        int res = _opticDepthTex_external.width;
        if (res <= 8) return;

        _baker.SetTexture(0, "_LookupRT", _opticDepthTex_external);
        _baker.SetInt("_Resolusion", res);
        _baker.SetInt("_NumOpticalDepthSample", _volumeSettings.OpticalDepthSamples.value);
        _baker.SetFloat("_RS_Thickness", _volumeSettings.AtmosphereHeight.value);
        _baker.SetFloat("_RS_DensityFalloff", _volumeSettings.AtmosphereDensityFalloff.value);
        _baker.SetFloat("_MS_Thickness", _volumeSettings.AerosolsHeight.value);
        _baker.SetFloat("_MS_DensityFalloff", _volumeSettings.AerosolsDensityFalloff.value);
        _baker.SetFloat("_EarthRadius", _volumeSettings.EarthRadius.value);
        _baker.Dispatch(0, Mathf.CeilToInt(res / 8f), Mathf.CeilToInt(res / 8f), 1);
    }
}
