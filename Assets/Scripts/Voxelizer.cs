using System;
using System.Collections;
using System.Collections.Generic;
using System.Dynamic;
using System.Net.NetworkInformation;
using UnityEngine;

public class Voxelizer : MonoBehaviour
{
    private ComputeShader voxelize;
    private Shader voxelDebugger;
    public GameObject sceneToFill;
    private Bounds sceneBound;

    private ComputeBuffer voxelBuffer, argBuffer;
    private float voxelSize = 0.5f;
    private int totalVoxel;
    private Vector3 voxelResolution;
    public Mesh debugMesh;
    private Material debugMaterial;

    private void CombineBound(GameObject parentObj)
    {
        foreach (Transform t in parentObj.transform)
        {
            if (t.GetComponent<Renderer>())
                sceneBound.Encapsulate(t.GetComponent<Renderer>().bounds);
        }
    }

    private int GetTotalVoxel(Vector3 boundSize, float voxelSize, out Vector3 res)
    {
        int x = Mathf.CeilToInt(boundSize.x);
        int y = Mathf.CeilToInt(boundSize.y);
        int z = Mathf.CeilToInt(boundSize.z);
        res = new Vector3(x/voxelSize, y/voxelSize, z/voxelSize);
        return (int)(res.x * res.y * res.z);
    }

    private void OnEnable()
    {
        voxelize = (ComputeShader)Resources.Load("CS_Voxel");
        voxelDebugger = Shader.Find("Hidden/S_VoxelVisualizer");
        CombineBound(sceneToFill);
        totalVoxel = GetTotalVoxel(sceneBound.size, voxelSize,out voxelResolution);

        argBuffer = new ComputeBuffer(1, 5 * sizeof(int), ComputeBufferType.IndirectArguments);
        uint[] args = { 0, 0, 0, 0, 0 };
        args[0] = (uint)debugMesh.GetIndexCount(0);
        args[1] = (uint)totalVoxel;
        args[2] = (uint)debugMesh.GetIndexStart(0);
        args[3] = (uint)debugMesh.GetBaseVertex(0);
        argBuffer.SetData(args);

        debugMaterial = new Material(voxelDebugger);

        debugMaterial.SetVector("_VoxelResolution",voxelResolution);
        debugMaterial.SetVector("_BoundsExtent",sceneBound.extents);
        debugMaterial.SetFloat("_VoxelSize",voxelSize);
    }

    private void OnDisable()
    {
        argBuffer.Release();
        //voxelBuffer.Dispose();
    }

    void Start()
    {
        
    }

    void Update()
    {
        Graphics.DrawMeshInstancedIndirect(debugMesh,0,debugMaterial,sceneBound,argBuffer);

    }
    
    private void OnDrawGizmos()
    {
        sceneBound.size = Vector3.zero;
        sceneBound.center = Vector3.zero;
        if (!sceneToFill)
            return;
        CombineBound(sceneToFill);
        Gizmos.color = Color.red;
        Gizmos.DrawWireCube(sceneBound.center,sceneBound.size);
    }
}
