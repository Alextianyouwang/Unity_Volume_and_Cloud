using System.Collections;
using System.Collections.Generic;
using System.IO;
using UnityEditor;
using UnityEngine;

[ExecuteInEditMode]
public class VA_LookupTableBaker : MonoBehaviour
{
    private ComputeShader _baker;
    private Texture2D _rt;
    public int Resolusion = 512;
    public float Height = 100;
    public float Falloff = 1.0f;
    public float Multiplier = 1.0f;
    private void OnEnable()
    {
        _baker = (ComputeShader)Resources.Load("CS_VA_LookuptableBaker");
        Setup();
    }

    private void Setup() 
    {
        _rt = new Texture2D(512, 512,UnityEngine.Experimental.Rendering.GraphicsFormat.R8G8B8A8_UNorm,UnityEngine.Experimental.Rendering.TextureCreationFlags.None);
        _rt.filterMode = FilterMode.Point;
        if (_baker == null)
            return;

        _baker.SetTexture(0,"_LookupRT", _rt);
        _baker.SetInt("_Resolusion", Resolusion);
        _baker.SetInt("_NumOpticalDepthSample", 30);
        _baker.SetFloat("_Height", Height);
        _baker.SetFloat("_Falloff", Falloff);
        _baker.SetFloat("_Multiplier", Multiplier);
        _baker.Dispatch(0, Mathf.CeilToInt(Resolusion / 8), Mathf.CeilToInt(Resolusion / 8),1);
        
        StartCoroutine(WaitInvoke());

    }

    IEnumerator WaitInvoke() 
    {
        yield return new WaitForSeconds(0.1f);
        SaveTexture(_rt, "RT_Folder", "RT_Test");
    }

    public void SaveTexture(Texture2D image, string path, string name)
    {
        byte[] bytes = image.EncodeToPNG();
        File.WriteAllBytes(Path.Combine(Application.dataPath, path, name + ".png"), bytes);
        Debug.Log($"Saved camera capture to: {path}");
        AssetDatabase.Refresh();
    }

}
