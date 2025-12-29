using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.RenderGraphModule.Util;
using UnityEngine.Rendering.Universal;

public class VolumeRenderingFeature : ScriptableRendererFeature
{
    [SerializeField] private VolumeRenderingSettings settings;
    public bool showInSceneView = true;
    public RenderPassEvent renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;

    private ObjectMetaData[] _allObjects;
    private VolumeRenderingPass _scriptablePass;

    public override void Create()
    {
        _allObjects = FindObjectsOfType<ObjectMetaData>();
        _scriptablePass = new VolumeRenderingPass(name);
        _scriptablePass.renderPassEvent = renderPassEvent;
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (!ReadyToEnqueue(renderingData)) return;
        _scriptablePass.SetupMembers(settings, _allObjects);
        renderer.EnqueuePass(_scriptablePass);
    }

    private bool ReadyToEnqueue(RenderingData renderingData)
    {
        CameraType cameraType = renderingData.cameraData.cameraType;
        if (cameraType == CameraType.Preview) return false;
        if (!showInSceneView && cameraType == CameraType.SceneView) return false;
        if (settings == null || settings.VolumeRenderingMaterial == null) return false;
        return true;
    }

    protected override void Dispose(bool disposing)
    {
        // Cleanup if needed
    }
}

[System.Serializable]
public class VolumeRenderingSettings
{
    public Material VolumeRenderingMaterial;
}

public class VolumeRenderingPass : ScriptableRenderPass
{
    private Material _volumeRenderMaterial;
    private ObjectMetaData[] _objects;

    public VolumeRenderingPass(string name)
    {
        profilingSampler = new ProfilingSampler(name);
    }

    public void SetupMembers(VolumeRenderingSettings settings, ObjectMetaData[] objects)
    {
        _volumeRenderMaterial = settings?.VolumeRenderingMaterial;
        _objects = objects;
    }

    public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
    {
        if (_volumeRenderMaterial == null) return;

        UniversalResourceData resourcesData = frameData.Get<UniversalResourceData>();
        UniversalCameraData cameraData = frameData.Get<UniversalCameraData>();

        // Create destination texture
        TextureHandle destination;
        TextureDesc targetDesc = renderGraph.GetTextureDesc(resourcesData.cameraColor);
        targetDesc.name = "_VolumeRenderingBuffer";
        targetDesc.clearBuffer = false;
        destination = renderGraph.CreateTexture(targetDesc);

        // Set material properties for objects if needed
        if (_objects != null && _objects.Length > 0)
        {
            // Example: Pass object bounds data to shader
            // You can extend this based on your rendering needs
        }

        // Blit with the volume rendering material
        RenderGraphUtils.BlitMaterialParameters param = new(resourcesData.activeColorTexture, destination, _volumeRenderMaterial, 0);
        renderGraph.AddBlitPass(param, "Volume Rendering Pass");
        resourcesData.cameraColor = destination;
    }
}
