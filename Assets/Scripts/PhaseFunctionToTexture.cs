using UnityEngine;
using System.IO;
#if UNITY_EDITOR
using UnityEditor;
#endif

public enum ColorChannel
{
    Red,
    Green,
    Blue,
    Alpha
}

[ExecuteAlways]
public class PhaseFunctionToTexture : MonoBehaviour
{
    [Header("Input")]
    public Texture2D targetTexture;
    
    [Tooltip("Which color channel to write the phase function to")]
    public ColorChannel targetChannel = ColorChannel.Red;

    public static readonly float[] phaseFunction = { 
    // Row 0-3: 0� - 21.2�
    1.000f, 0.982f, 0.963f, 0.943f, 0.921f, 0.898f, 0.874f, 0.850f,
    0.825f, 0.800f, 0.776f, 0.752f, 0.729f, 0.707f, 0.685f, 0.664f,
    0.644f, 0.625f, 0.607f, 0.590f, 0.573f, 0.558f, 0.543f, 0.529f,
    0.516f, 0.503f, 0.492f, 0.481f, 0.470f, 0.460f, 0.451f, 0.442f,
    // Row 4-7: 22.6� - 43.8�
    0.434f, 0.426f, 0.419f, 0.412f, 0.406f, 0.400f, 0.394f, 0.389f,
    0.384f, 0.379f, 0.375f, 0.371f, 0.367f, 0.363f, 0.360f, 0.357f,
    0.354f, 0.351f, 0.348f, 0.346f, 0.343f, 0.341f, 0.339f, 0.337f,
    0.335f, 0.333f, 0.331f, 0.330f, 0.328f, 0.327f, 0.325f, 0.324f,
    // Row 8-11: 45.2� - 66.4�
    0.322f, 0.321f, 0.320f, 0.319f, 0.318f, 0.317f, 0.316f, 0.315f,
    0.314f, 0.313f, 0.312f, 0.311f, 0.311f, 0.310f, 0.309f, 0.308f,
    0.308f, 0.307f, 0.306f, 0.306f, 0.305f, 0.305f, 0.304f, 0.303f,
    0.303f, 0.302f, 0.302f, 0.301f, 0.301f, 0.300f, 0.300f, 0.299f,
    // Row 12-15: 67.8� - 89.0�
    0.299f, 0.298f, 0.298f, 0.297f, 0.297f, 0.296f, 0.296f, 0.295f,
    0.295f, 0.294f, 0.294f, 0.293f, 0.293f, 0.292f, 0.291f, 0.291f,
    0.290f, 0.290f, 0.289f, 0.288f, 0.288f, 0.287f, 0.286f, 0.286f,
    0.285f, 0.284f, 0.283f, 0.283f, 0.282f, 0.281f, 0.280f, 0.279f,
    // Row 16-19: 90.4� - 111.5�
    0.279f, 0.278f, 0.277f, 0.276f, 0.275f, 0.274f, 0.273f, 0.272f,
    0.271f, 0.270f, 0.269f, 0.268f, 0.267f, 0.266f, 0.265f, 0.264f,
    0.263f, 0.262f, 0.261f, 0.260f, 0.259f, 0.258f, 0.257f, 0.257f,
    0.256f, 0.256f, 0.256f, 0.256f, 0.257f, 0.258f, 0.260f, 0.263f,
    // Row 20-23: 112.9� - 134.1� (back-scatter lobes)
    0.267f, 0.272f, 0.278f, 0.285f, 0.293f, 0.301f, 0.310f, 0.318f,
    0.324f, 0.328f, 0.330f, 0.329f, 0.326f, 0.320f, 0.312f, 0.303f,
    0.293f, 0.284f, 0.276f, 0.269f, 0.264f, 0.261f, 0.260f, 0.262f,
    0.266f, 0.272f, 0.279f, 0.286f, 0.291f, 0.294f, 0.294f, 0.291f,
    // Row 24-27: 135.5� - 156.7� (secondary lobe decay)
    0.286f, 0.279f, 0.271f, 0.263f, 0.255f, 0.248f, 0.242f, 0.237f,
    0.233f, 0.230f, 0.228f, 0.226f, 0.225f, 0.224f, 0.223f, 0.222f,
    0.222f, 0.221f, 0.220f, 0.220f, 0.219f, 0.218f, 0.218f, 0.217f,
    0.216f, 0.216f, 0.215f, 0.214f, 0.214f, 0.213f, 0.212f, 0.212f,
    // Row 28-31: 158.1� - 180�
    0.211f, 0.210f, 0.210f, 0.209f, 0.208f, 0.208f, 0.207f, 0.206f,
    0.206f, 0.205f, 0.204f, 0.204f, 0.203f, 0.202f, 0.202f, 0.201f,
    0.200f, 0.200f, 0.199f, 0.198f, 0.198f, 0.197f, 0.196f, 0.196f,
    0.195f, 0.194f, 0.194f, 0.193f, 0.192f, 0.192f, 0.191f, 0.190f
    };

    [ContextMenu("Apply Phase Function To Texture")]
    public void ApplyPhaseFunction()
    {
        ApplyPhaseFunction(phaseFunction);
    }

    /// <summary>
    /// Applies a custom phase function array to the target texture.
    /// </summary>
    /// <param name="inputPhaseFunction">Array of 256 float values representing the phase function.</param>
    public void ApplyPhaseFunction(float[] inputPhaseFunction)
    {
        if (targetTexture == null)
        {
            Debug.LogError("Target Texture is null.");
            return;
        }

        if (inputPhaseFunction == null || inputPhaseFunction.Length != 256)
        {
            Debug.LogError("Phase function array must have exactly 256 values.");
            return;
        }

        if (targetTexture.width != 256 || targetTexture.height < 1)
        {
            Debug.LogError("Texture must be 256 pixels wide and at least 1 pixel tall.");
            return;
        }

#if UNITY_EDITOR
        // Ensure texture is readable
        string path = AssetDatabase.GetAssetPath(targetTexture);
        if (!string.IsNullOrEmpty(path))
        {
            TextureImporter importer = AssetImporter.GetAtPath(path) as TextureImporter;
            if (importer != null && !importer.isReadable)
            {
                importer.isReadable = true;
                importer.textureCompression = TextureImporterCompression.Uncompressed;
                importer.SaveAndReimport();
            }
        }

        for (int x = 0; x < 256; x++)
        {
            float v = Mathf.Clamp01(inputPhaseFunction[x]);
            Color existingColor = targetTexture.GetPixel(x, 0);
            Color newColor = ApplyValueToChannel(existingColor, v, targetChannel);
            targetTexture.SetPixel(x, 0, newColor);
        }

        targetTexture.Apply(updateMipmaps: false, makeNoLongerReadable: false);

        byte[] png = targetTexture.EncodeToPNG();
        File.WriteAllBytes(path, png);

        AssetDatabase.ImportAsset(path, ImportAssetOptions.ForceUpdate);
        AssetDatabase.Refresh();

        EditorUtility.SetDirty(targetTexture);
        AssetDatabase.SaveAssets();

        Debug.Log("Phase function successfully written to texture.");
#else
        // Runtime-only: just apply to texture memory (won't persist)
        for (int x = 0; x < 256; x++)
        {
            float v = Mathf.Clamp01(inputPhaseFunction[x]);
            Color existingColor = targetTexture.GetPixel(x, 0);
            Color newColor = ApplyValueToChannel(existingColor, v, targetChannel);
            targetTexture.SetPixel(x, 0, newColor);
        }

        targetTexture.Apply(updateMipmaps: false, makeNoLongerReadable: false);
        Debug.Log("Phase function applied to texture (runtime only, not saved to disk).");
#endif
    }

    private Color ApplyValueToChannel(Color color, float value, ColorChannel channel)
    {
        switch (channel)
        {
            case ColorChannel.Red:
                color.r = value;
                break;
            case ColorChannel.Green:
                color.g = value;
                break;
            case ColorChannel.Blue:
                color.b = value;
                break;
            case ColorChannel.Alpha:
                color.a = value;
                break;
        }
        return color;
    }
}