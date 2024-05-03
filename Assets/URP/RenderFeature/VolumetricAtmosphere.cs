using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
public class VolumetricAtmospherePass : ScriptableRenderPass
{

    private VolumetricAtmosphereSetting _settings;
    private ProfilingSampler _profilingSampler;
    private RTHandle _rtColor;
    private Material _blitMat;

    public VolumetricAtmospherePass(VolumetricAtmosphereSetting settings, string name, Material mat)
    {
        _settings = settings;
        _profilingSampler = new ProfilingSampler(name);
        _blitMat = mat;
    }
    public void SetTarget(RTHandle colorHandle)
    {
        _rtColor = colorHandle;
    }
    public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
    {
        ConfigureTarget(_rtColor);
    }

    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        CommandBuffer cmd = CommandBufferPool.Get();
        using (new ProfilingScope(cmd, _profilingSampler))
        {
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
            if (_blitMat != null)
            {
                _blitMat.SetTexture("_DepthTexture", renderingData.cameraData.renderer.cameraDepthTargetHandle);
                _blitMat.SetFloat("_Camera_Near", renderingData.cameraData.camera.nearClipPlane);
                _blitMat.SetFloat("_Camera_Far", renderingData.cameraData.camera.farClipPlane);
                _blitMat.SetFloat("_AtmosphereHeight", _settings.AtmosphereHeight);
                _blitMat.SetFloat("_EarthRadius", _settings.EarthRadius);
                _blitMat.SetFloat("_AtmosphereDensityFalloff", _settings.AtmosphereDensityFalloff);
                _blitMat.SetVector("_WaveLength", _settings.WaveLength);
                _blitMat.SetFloat("_ScatterIntensity", _settings.ScatterIntensity);
                _blitMat.SetFloat("_FinalColorMultiplier", _settings.FinalColorMultiplier);
                _blitMat.SetFloat("_AnisotropicScattering", _settings.AnisotropicScatterig);
                _blitMat.SetInt("_NumOpticalDepthSample", _settings.OpticalDepthSamples);
                _blitMat.SetInt("_NumInScatteringSample", _settings.InScatteringSamples);

                if (_rtColor != null)
                {
                    Blitter.BlitCameraTexture(cmd, _rtColor, _rtColor, _blitMat, 0);
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
    }
}

[System.Serializable]
public class VolumetricAtmosphereSetting
{
    public bool showInSceneView = true;
    public RenderPassEvent _event = RenderPassEvent.AfterRenderingOpaques;


    public float AtmosphereHeight = 10;
    public float EarthRadius = 10000;
    [Range(1, 10)]
    public float AtmosphereDensityFalloff = 1;
    [Range(0, 10)]
    public float ScatterIntensity = 1;
    [Range(0, 3)]
    public float FinalColorMultiplier = 1;
    [Range(1, 30)]
    public int OpticalDepthSamples = 10;
    [Range(1, 30)]
    public int InScatteringSamples = 10;
    [Range(0, 1)]
    public float AnisotropicScatterig = 0;
    public Vector3 WaveLength = new Vector3(700, 530, 440);
}

public class VolumetricAtmosphere : ScriptableRendererFeature
{
    public VolumetricAtmosphereSetting _settings = new VolumetricAtmosphereSetting();
    private VolumetricAtmospherePass _volumePass;
    private Material _blitMat;
    public override void Create()
    {
        if (_blitMat == null) 
            _blitMat = CoreUtils.CreateEngineMaterial(Shader.Find("Hidden/S_Atmosphere"));

        _volumePass = new VolumetricAtmospherePass(_settings, name, _blitMat);
        _volumePass.renderPassEvent = _settings._event;
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        CameraType cameraType = renderingData.cameraData.cameraType;
        if (cameraType == CameraType.Preview) return; 
        if (!_settings.showInSceneView && cameraType == CameraType.SceneView) return;
        renderer.EnqueuePass(_volumePass);
    }
    public override void SetupRenderPasses(ScriptableRenderer renderer, in RenderingData renderingData)
    {
        CameraType cameraType = renderingData.cameraData.cameraType;
        if (cameraType == CameraType.Preview) return;
        if (!_settings.showInSceneView && cameraType == CameraType.SceneView) return;
        _volumePass.ConfigureInput(ScriptableRenderPassInput.Color);
        _volumePass.SetTarget(renderer.cameraColorTargetHandle);
    }
    protected override void Dispose(bool disposing)
    {
        _volumePass.Dispose();
        CoreUtils.Destroy(_blitMat);
    }
}