using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class VolumetricAtmosphereFeature : ScriptableRendererFeature
{
    public bool showInSceneView = true;
    public RenderPassEvent _event = RenderPassEvent.AfterRenderingTransparents;

    private VolumetricAtmospherePass _volumePass;
    private Material _blitMat;
    public override void Create()
    {
        if (_blitMat == null) 
            _blitMat = CoreUtils.CreateEngineMaterial(Shader.Find("Hidden/S_Atmosphere"));

        _volumePass = new VolumetricAtmospherePass( name, _blitMat);
        _volumePass.renderPassEvent = _event;
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (!ReadyToEnqueue(renderingData)) return;
        renderer.EnqueuePass(_volumePass);
    }
    public override void SetupRenderPasses(ScriptableRenderer renderer, in RenderingData renderingData)
    {
        if (!ReadyToEnqueue(renderingData)) return;
        _volumePass.SetTarget(renderer.cameraColorTargetHandle);
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
        _volumePass.Dispose();
        if (!Application.isPlaying)
            CoreUtils.Destroy(_blitMat);
    }
}