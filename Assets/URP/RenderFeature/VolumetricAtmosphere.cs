using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class VolumetricAtmosphere : ScriptableRendererFeature
{

    public class CustomRenderPass : ScriptableRenderPass
    {

        private Settings settings;
        private FilteringSettings filteringSettings;
        private ProfilingSampler _profilingSampler;
        private List<ShaderTagId> shaderTagsList = new List<ShaderTagId>();
        private RTHandle rtCustomColor, rtTempColor, rtDepth;

        public CustomRenderPass(Settings settings, string name)
        {
            this.settings = settings;
            filteringSettings = new FilteringSettings(RenderQueueRange.opaque, settings.layerMask);

            // Use default tags
            shaderTagsList.Add(new ShaderTagId("SRPDefaultUnlit"));
            shaderTagsList.Add(new ShaderTagId("UniversalForward"));
            shaderTagsList.Add(new ShaderTagId("UniversalForwardOnly"));

            _profilingSampler = new ProfilingSampler(name);
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            var colorDesc = renderingData.cameraData.cameraTargetDescriptor;
            colorDesc.depthBufferBits = 0;

            // Set up temporary color buffer (for blit)
            RenderingUtils.ReAllocateIfNeeded(ref rtTempColor, colorDesc, name: "_TempColorTexture");

            // Set up custom color target buffer (to render objects into)
            if (settings.colorTargetDestinationID != "")
            {
                RenderingUtils.ReAllocateIfNeeded(ref rtCustomColor, colorDesc, name: settings.colorTargetDestinationID);
            }
            else
            {
                // colorDestinationID is blank, use camera target instead
                rtCustomColor = renderingData.cameraData.renderer.cameraColorTargetHandle;
            }

            // Using camera's depth target (that way we can ZTest with scene objects still)
            rtDepth = renderingData.cameraData.renderer.cameraDepthTargetHandle;

            ConfigureTarget(rtCustomColor, rtDepth);
            ConfigureClear(ClearFlag.Color, new Color(0, 0, 0, 0));
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get();
            using (new ProfilingScope(cmd, _profilingSampler))
            {
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();

                SortingCriteria sortingCriteria = renderingData.cameraData.defaultOpaqueSortFlags;
                DrawingSettings drawingSettings = CreateDrawingSettings(shaderTagsList, ref renderingData, sortingCriteria);
                if (settings.overrideMaterial != null)
                {
                    drawingSettings.overrideMaterialPassIndex = settings.overrideMaterialPass;
                    drawingSettings.overrideMaterial = settings.overrideMaterial;
                }
                context.DrawRenderers(renderingData.cullResults, ref drawingSettings, ref filteringSettings);

                if (settings.colorTargetDestinationID != "")
                    cmd.SetGlobalTexture(settings.colorTargetDestinationID, rtCustomColor);

                if (settings.blitMaterial != null)
                {
                    RTHandle camTarget = renderingData.cameraData.renderer.cameraColorTargetHandle;
                    settings.blitMaterial.SetTexture("_DepthTexture", rtDepth);
                    settings.blitMaterial.SetFloat("_Camera_Near", renderingData.cameraData.camera.nearClipPlane);
                    settings.blitMaterial.SetFloat("_Camera_Far", renderingData.cameraData.camera.farClipPlane);
                    settings.blitMaterial.SetFloat("_AtmosphereHeight", settings.AtmosphereHeight);
                    settings.blitMaterial.SetFloat("_EarthRadius", settings.EarthRadius);
                    settings.blitMaterial.SetFloat("_AtmosphereDensityFalloff", settings.AtmosphereDensityFalloff);
                    settings.blitMaterial.SetVector("_WaveLength", settings.WaveLength);
                    settings.blitMaterial.SetFloat("_ScatterIntensity", settings.ScatterIntensity);
                    settings.blitMaterial.SetFloat("_FinalColorMultiplier", settings.FinalColorMultiplier);
                    settings.blitMaterial.SetFloat("_AnisotropicScattering", settings.AnisotropicScatterig);
                    settings.blitMaterial.SetInt("_NumOpticalDepthSample", settings.OpticalDepthSamples);
                    settings.blitMaterial.SetInt("_NumInScatteringSample", settings.InScatteringSamples);

                    if (camTarget != null && rtTempColor != null)
                    {
                        Blitter.BlitCameraTexture(cmd, camTarget, rtTempColor, settings.blitMaterial, 0);
                        Blitter.BlitCameraTexture(cmd, rtTempColor, camTarget);
                    }
                }
            }
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
            CommandBufferPool.Release(cmd);
        }

        public override void OnCameraCleanup(CommandBuffer cmd) {
        }
        public void Dispose()
        {
            if (settings.colorTargetDestinationID != "")
                rtCustomColor?.Release();
            rtTempColor?.Release();
            rtDepth?.Release();
        }
    }
    [System.Serializable]
    public class Settings
    {
        public bool showInSceneView = true;
        public RenderPassEvent _event = RenderPassEvent.AfterRenderingOpaques;

        [Header("Draw Renderers Settings")]
        public LayerMask layerMask = 1;
        public Material overrideMaterial;
        public int overrideMaterialPass;
        public string colorTargetDestinationID = "";

        [Header("Blit Settings")]
        public Material blitMaterial;

        
        public float AtmosphereHeight = 10;
        public float EarthRadius = 10000;
        [Range (0,10)]
        public float AtmosphereDensityFalloff = 1;
        [Range (0,10)]
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

    public Settings settings = new Settings();

    // Feature Methods

    private CustomRenderPass _volumePass;

    public override void Create()
    {
        _volumePass = new CustomRenderPass(settings, name);
        _volumePass.renderPassEvent = settings._event;
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        CameraType cameraType = renderingData.cameraData.cameraType;
        if (cameraType == CameraType.Preview) return; // Ignore feature for editor/inspector previews & asset thumbnails
        if (!settings.showInSceneView && cameraType == CameraType.SceneView) return;
        renderer.EnqueuePass(_volumePass);
    }

    protected override void Dispose(bool disposing)
    {
        _volumePass.Dispose();
    }
}