using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using UnityEditor.VersionControl;
using UnityEngine;
using Task = System.Threading.Tasks.Task;

public class CloudDrawer : MonoBehaviour
{
    public struct Sphere
    {
        public Vector3 center;
        public float radius;
    }

    public class SphereAnim
    {
        public Sphere sphere;
        private float time;
        public float endTime;
        public float targetRadius;
        public AnimationCurve animationCurve;

        public SphereAnim(float _endtime, float _targetRadius, AnimationCurve _animationCurve, Sphere _sphere)
        {
            endTime = _endtime;
            targetRadius = _targetRadius;
            animationCurve = _animationCurve;
            sphere = _sphere;
            sphere.center = Vector3.one * 10000f;
            sphere.radius = 0;
        }

        public void Spawn(Vector3 pos)
        {
            sphere.center = pos;
            sphere.radius = 0f;
            time = 0;
        }

        public async void ExecuteAnimation()
        {
            while (time < endTime)
            {
                time += Time.deltaTime;
                float percent = time / endTime;
                sphere.radius = animationCurve.Evaluate(percent) * targetRadius;
                await Task.Yield();
            }
          
            
        }
    }
    
    private SphereAnim[] activeSphereAnims;

    private Camera cam;
    private ComputeShader smokePainter;
    private ComputeBuffer sphereBuffer;
    public int maxSphereCount = 10;
    public AnimationCurve sphereRadiusCurve;
    
    public LayerMask mask;
    private int sphereIterator= 0;

    public ComputeBuffer GetSphereBuffer()
    {
        return sphereBuffer;
    }

    public int GetMaxSphereNumber()
    {
        return maxSphereCount;
    }

    private void Initialize()
    {
        activeSphereAnims = new SphereAnim[maxSphereCount];
        cam = GetComponent<Camera>();
        for(int i = 0; i < maxSphereCount; i ++)
        {
            activeSphereAnims[i] = new SphereAnim(2f,1.5f, sphereRadiusCurve, new Sphere());
        }
        smokePainter = (ComputeShader)Resources.Load("SmokePainter");
        sphereBuffer = new ComputeBuffer(maxSphereCount, sizeof(float) * 4);
    }

    private void OnDisable()
    {
        sphereBuffer.Release();
    }
    

    private void OnNewSphereCreated(Vector3 pos)
    {
        SphereAnim newSphere = activeSphereAnims[sphereIterator];
        newSphere.Spawn(pos);
        newSphere.ExecuteAnimation();
        sphereIterator += 1;
        sphereIterator %= maxSphereCount;

    }

    private void CheckShootNewSphere()
    {
        if (Input.GetMouseButtonDown(0))
        {
            Ray screenRay = cam.ScreenPointToRay(Input.mousePosition);
            RaycastHit hit;
            if (Physics.Raycast(screenRay, out hit, 1000,mask))
            {
                OnNewSphereCreated(hit.point);
            }

        }
    }

    private void SetUpComputeBuffer()
    {
        sphereBuffer.SetData(activeSphereAnims.Select(x=>x.sphere).ToArray(),0,0,maxSphereCount);
        
        
        
    }


    private void OnEnable()
    {
        Initialize();
    }

    void Update()
    {
        CheckShootNewSphere();
        
    }

    private void LateUpdate()
    {
        SetUpComputeBuffer();

    }

    private void OnDrawGizmos()
    {
        if (activeSphereAnims== null)
            return;
        for (int i = 0; i < maxSphereCount; i++)
        {
            
            SphereAnim a = activeSphereAnims[i];
            if (a == null)
                continue;
            Gizmos.DrawSphere(a.sphere.center,a.sphere.radius);
        }
    }
}
