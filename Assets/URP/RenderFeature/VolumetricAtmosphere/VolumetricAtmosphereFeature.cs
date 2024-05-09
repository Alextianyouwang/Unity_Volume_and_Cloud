using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class VolumetricAtmosphereFeature : ScriptableRendererFeature
{
    public bool showInSceneView = true;
    public RenderPassEvent _event = RenderPassEvent.AfterRenderingTransparents;

    private VolumetricAtmospherePass _volumePass;
    private Material _blitMat;


    private ComputeShader _baker;
    private RenderTexture _rt;
    public int Resolusion = 512;
    public float EarthRadius = 5000;

    public float AtmosphereHeight = 100;
    public float AtmosphereDensityFalloff = 1.0f;

    public float AerosolsHeight = 20;
    public float AerosolsDensityFalloff = 1.0f;
    public override void Create()
    {
        if (_blitMat == null) 
            _blitMat = CoreUtils.CreateEngineMaterial(Shader.Find("Hidden/S_Atmosphere"));

        _volumePass = new VolumetricAtmospherePass( name, _blitMat);
        _volumePass.renderPassEvent = _event;

        _rt = new RenderTexture(Resolusion, Resolusion, 0, RenderTextureFormat.ARGB64, 0);
        _rt.filterMode = FilterMode.Point;
        _rt.enableRandomWrite = true;
        _rt.format = RenderTextureFormat.ARGBFloat;
        
        _baker = (ComputeShader)Resources.Load("CS_VA_LookuptableBaker");
        _baker.SetTexture(0, "_LookupRT", _rt);
        _baker.SetInt("_Resolusion", Resolusion);
        _baker.SetInt("_NumOpticalDepthSample", 50);
        _baker.SetFloat("_RS_Thickness", AtmosphereHeight);
        _baker.SetFloat("_RS_Falloff", AtmosphereDensityFalloff);
        _baker.SetFloat("_MS_Thickness", AerosolsHeight);
        _baker.SetFloat("_MS_Falloff", AerosolsDensityFalloff);
        _baker.SetFloat("_EarthRadius", EarthRadius);
        _baker.Dispatch(0, Mathf.CeilToInt(Resolusion / 8), Mathf.CeilToInt(Resolusion / 8), 1);

    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (!ReadyToEnqueue(renderingData)) return;
        renderer.EnqueuePass(_volumePass);


    }
    public override void SetupRenderPasses(ScriptableRenderer renderer, in RenderingData renderingData)
    {
        if (!ReadyToEnqueue(renderingData)) return;
        _volumePass.SetTarget(renderer.cameraColorTargetHandle,_rt);
    }
    bool ReadyToEnqueue(RenderingData renderingData) 
    {
        CameraType cameraType = renderingData.cameraData.cameraType;
        if (cameraType == CameraType.Preview) return false;
        if (!showInSceneView && cameraType == CameraType.SceneView) return false;
        VolumetricAtmosphereComponent settings = VolumeManager.instance.stack.GetComponent<VolumetricAtmosphereComponent>();
        if (settings == null) return false;
        if (!settings.IsActive()) return false;
        return true;
    }
    protected override void Dispose(bool disposing)
    {
        _rt.Release();
        _volumePass.Dispose();
        if (!Application.isPlaying)
            CoreUtils.Destroy(_blitMat);
    }
}