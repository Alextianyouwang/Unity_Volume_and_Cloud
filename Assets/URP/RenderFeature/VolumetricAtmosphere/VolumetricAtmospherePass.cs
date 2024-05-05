using UnityEngine;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering;

public class VolumetricAtmospherePass : ScriptableRenderPass
{
    private ProfilingSampler _profilingSampler;
    private RTHandle _rtColor, _rtTempColor;
    private Material _blitMat;

    public VolumetricAtmospherePass(string name, Material mat)
    {
        _profilingSampler = new ProfilingSampler(name);
        _blitMat = mat;
    }
    public void SetTarget(RTHandle colorHandle)
    {
        _rtColor = colorHandle;
    }
    public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
    {
        RenderTextureDescriptor camTargetDesc = renderingData.cameraData.cameraTargetDescriptor;
        camTargetDesc.depthBufferBits = 0;
        RenderingUtils.ReAllocateIfNeeded(ref _rtTempColor, camTargetDesc, FilterMode.Bilinear, TextureWrapMode.Clamp, name: "_TempColor");
        ConfigureTarget(_rtColor);
    }

    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        CommandBuffer cmd = CommandBufferPool.Get();
        VolumetricAtmosphereComponent settings = VolumeManager.instance.stack.GetComponent<VolumetricAtmosphereComponent>();
        if (settings == null)
            return;
        if (!settings.IsActive())
            return;
        using (new ProfilingScope(cmd, _profilingSampler))
        {
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
            if (_blitMat != null)
            {
                _blitMat.SetTexture("_DepthTexture", renderingData.cameraData.renderer.cameraDepthTargetHandle);
                _blitMat.SetFloat("_Camera_Near", renderingData.cameraData.camera.nearClipPlane);
                _blitMat.SetFloat("_Camera_Far", renderingData.cameraData.camera.farClipPlane);
                _blitMat.SetFloat("_AtmosphereHeight", settings.AtmosphereHeight.value);
                _blitMat.SetFloat("_EarthRadius", settings.EarthRadius.value);
                _blitMat.SetFloat("_AtmosphereDensityFalloff", settings.AtmosphereDensityFalloff.value);
                _blitMat.SetFloat("_ScatterIntensity", settings.UniformAbsorbsion.value);
                _blitMat.SetFloat("_AnisotropicScattering", settings.AnisotropicLevel.value);
                _blitMat.SetFloat("_AtmosphereDensityMultiplier", settings.AtmosphereDensityMultiplier.value);
                _blitMat.SetFloat("_RayleighStrength", settings.RayleighScattering.value);
                _blitMat.SetColor("_RayleighScatterWeight", settings.RayleighAbsorbsionWeightPerChannel.value);
                _blitMat.SetColor("_InsColor", settings.InscatteringTint.value);
                _blitMat.SetInt("_NumOpticalDepthSample", settings.OpticalDepthSamples.value);
                _blitMat.SetInt("_NumInScatteringSample", settings.InScatteringSamples.value);

                if (_rtColor != null)
                {
                    Blitter.BlitCameraTexture(cmd, _rtColor, _rtTempColor, _blitMat, 0);
                    Blitter.BlitCameraTexture(cmd, _rtTempColor, _rtColor);

                }
            }
        }
        context.ExecuteCommandBuffer(cmd);
        cmd.Clear();
        CommandBufferPool.Release(cmd);
    }

    public override void OnCameraCleanup(CommandBuffer cmd) { }
    public void Dispose()
    {
        _rtColor?.Release();
        _rtTempColor?.Release();
    }
}
