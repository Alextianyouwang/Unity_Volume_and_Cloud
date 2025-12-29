using System;
using UnityEngine;

namespace Experimental.Rendering.CloudRendering
{
    [Serializable]
    public class CloudRenderingFeatureSettings
    {
        public Material CloudRenderingMaterial;
        public Vector3 BoxMin;
        public Vector3 BoxMax;
    }
}

