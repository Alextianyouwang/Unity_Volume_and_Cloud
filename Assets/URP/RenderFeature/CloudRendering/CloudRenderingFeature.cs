using UnityEngine;
using UnityEngine.Rendering.Universal;

namespace Experimental.Rendering.CloudRendering 
{
    public class CloudRenderingFeature : ScriptableRendererFeature
    {
        [SerializeField] private CloudRenderingFeatureSettings settings;
        private CloudRenderingFeaturePass _scriptablePass;

        public override void Create()
        {
            _scriptablePass = new CloudRenderingFeaturePass(name);
            _scriptablePass.renderPassEvent = RenderPassEvent.AfterRenderingTransparents;
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            _scriptablePass.SetupMembers(settings);
            renderer.EnqueuePass(_scriptablePass);
        }

        protected override void Dispose(bool disposing)
        {
            _scriptablePass.Dispose();
        }
    }
}
