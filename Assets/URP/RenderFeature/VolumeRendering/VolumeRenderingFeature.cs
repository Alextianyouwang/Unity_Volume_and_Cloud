using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class VolumeRenderingFeature : ScriptableRendererFeature
{

    private ObjectMetaData[] _allObjects;
    VolumeRenderingPass m_ScriptablePass;

    public override void Create()
    {
        _allObjects = FindObjectsOfType<ObjectMetaData>();
        m_ScriptablePass = new VolumeRenderingPass();
        m_ScriptablePass.renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
    }
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(m_ScriptablePass);
    }
}

public class VolumeRenderingPass : ScriptableRenderPass
{

    public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
    {
    }

    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
    }
    public override void OnCameraCleanup(CommandBuffer cmd)
    {
    }
}


