using UnityEngine;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering;

public class VolumetricAtmospherePass : ScriptableRenderPass
{
    private ProfilingSampler _profilingSampler;
    private RTHandle _rtColor, _rtTempColor;
    private Material _blitMat;
    private RenderTexture _opticDepthTex;

    public VolumetricAtmospherePass(string name, Material mat)
    {
        _profilingSampler = new ProfilingSampler(name);
        _blitMat = mat;
    }
    public void SetTarget(RTHandle colorHandle, RenderTexture opticDepthTex)
    {
        _rtColor = colorHandle;
        _opticDepthTex = opticDepthTex;
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
        using (new ProfilingScope(cmd, _profilingSampler))
        {
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
            if (_blitMat != null)
            {
                _blitMat.SetTexture("_CameraOpaqueTexture", renderingData.cameraData.renderer.cameraColorTargetHandle);
                _blitMat.SetTexture("_CameraDepthTexture", renderingData.cameraData.renderer.cameraDepthTargetHandle);
                _blitMat.SetTexture("_OpticalDepthTexture", _opticDepthTex);
                _blitMat.SetFloat("_Camera_Near", renderingData.cameraData.camera.nearClipPlane);
                _blitMat.SetFloat("_Camera_Far", renderingData.cameraData.camera.farClipPlane);
                _blitMat.SetFloat("_EarthRadius", settings.EarthRadius.value);
                _blitMat.SetInt("_NumOpticalDepthSample", settings.OpticalDepthSamples.value);
                _blitMat.SetInt("_NumInScatteringSample", settings.InscatteringSamples.value);

                LocalKeyword enableRayleigh = new LocalKeyword(_blitMat.shader, "_USE_RAYLEIGH");
                if (settings.EnableRayleighScattering.value)
                    _blitMat.EnableKeyword(enableRayleigh);
                else
                    _blitMat.DisableKeyword(enableRayleigh);
                _blitMat.SetFloat("_Rs_Thickness", settings.AtmosphereHeight.value);
                _blitMat.SetFloat("_Rs_DensityFalloff", settings.AtmosphereDensityFalloff.value);
                _blitMat.SetFloat("_Rs_Absorbsion", settings.AtmosphereUniformAbsorbsion.value);
                _blitMat.SetFloat("_Rs_DensityMultiplier", settings.AtmosphereDensityMultiplier.value);
                _blitMat.SetFloat("_Rs_ChannelSplit", settings.AtmosphereChannelSplit.value);
                _blitMat.SetColor("_Rs_ScatterWeight", settings.AtmosphereAbsorbsionWeightPerChannel.value);
                _blitMat.SetColor("_Rs_InsColor", settings.AtmosphereInscatteringTint.value);
   

                LocalKeyword enableMie = new LocalKeyword(_blitMat.shader, "_USE_MIE");
                if (settings.EnableMieScattering.value)
                    _blitMat.EnableKeyword(enableMie);
                else
                    _blitMat.DisableKeyword(enableMie);
                _blitMat.SetFloat("_Ms_Thickness", settings.AerosolsHeight.value);
                _blitMat.SetFloat("_Ms_DensityFalloff", settings.AerosolsDensityFalloff.value);
                _blitMat.SetFloat("_Ms_Absorbsion", settings.AerosolsUniformAbsorbsion.value);
                _blitMat.SetFloat("_Ms_DensityMultiplier", settings.AerosolsDensityMultiplier.value);
                _blitMat.SetFloat("_Ms_Anisotropic", settings.AerosolsAnistropic.value);
                _blitMat.SetColor("_Ms_InsColor", settings.AerosolsInscatteringTint.value);

                _blitMat.SetInt("_VolumeOnly", settings.VolumePassOnly.value?1:0);
                Blitter.BlitCameraTexture(cmd, _rtColor, _rtTempColor, _blitMat, 0);
                Blitter.BlitCameraTexture(cmd, _rtTempColor, _rtColor);
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
