using UnityEngine;

[ExecuteAlways]
public class RaycastPhaseCapture : MonoBehaviour
{
    [Header("Raycast Settings")]
    [Tooltip("Maximum ray distance")]
    public float rayLength = 100f;
    
    [Tooltip("Layers to raycast against")]
    public LayerMask raycastMask = ~0;
    
    [Header("References")]
    [Tooltip("Reference to PhaseFunctionToTexture component for baking")]
    public PhaseFunctionToTexture phaseFunctionBaker;
    
    [Header("Debug")]
    [Tooltip("Last captured phase function values (read-only)")]
    public float[] capturedPhaseFunction = new float[256];
    
    [Tooltip("Draw debug rays in scene view")]
    public bool drawDebugRays = true;
    
    [Tooltip("Duration to show debug rays")]
    public float debugRayDuration = 2f;

    public float referenceDistance = 2f;

    /// <summary>
    /// Fires 256 rays in a 180° arc from -X through +Z to +X direction.
    /// Fires a reference ray 1° towards -Z and normalizes all values.
    /// Then passes the result to PhaseFunctionToTexture for baking.
    /// </summary>
    [ContextMenu("Capture And Bake Phase Function")]
    public void CaptureAndBakePhaseFunction()
    {
        Vector3 origin = transform.position;
        float[] distances = new float[256];
        
        // Fire 256 rays covering 180 degrees arc
        // From -X (angle = 180°) through +Z (angle = 90°) to +X (angle = 0°)
        // In Unity's coordinate system: X is right, Z is forward
        for (int i = 0; i < 256; i++)
        {
            // Calculate angle: i=0 -> 180° (-X), i=255 -> 0° (+X)
            // This gives us 256 rays evenly distributed across 180°
            float angle = Mathf.PI - (i * Mathf.PI / 255f);
            
            // Direction in XZ plane (Y=0 for horizontal rays)
            Vector3 direction = new Vector3(Mathf.Cos(angle), 0f, Mathf.Sin(angle)).normalized;
            
            if (Physics.Raycast(origin, direction, out RaycastHit hit, rayLength, raycastMask))
            {
                distances[i] = hit.distance;
                
                if (drawDebugRays)
                {
                    Debug.DrawRay(origin, direction * hit.distance, Color.green, debugRayDuration);
                }
            }
            else
            {
                // No hit - use max ray length
                distances[i] = rayLength;
                
                if (drawDebugRays)
                {
                    Debug.DrawRay(origin, direction * rayLength, Color.red, debugRayDuration);
                }
            }
        }
        
        // Estimate area and volume using triangular sectors between adjacent rays
        // Area of triangle = 0.5 * r1 * r2 * sin(angle_between)
        // Volume uses Pappus's theorem: V = 2π * centroid_z * area
        float angleBetweenRays = Mathf.PI / 255f; // Angle between adjacent rays
        float sinAngleBetween = Mathf.Sin(angleBetweenRays);
        float estimatedArea = 0f;
        float weightedCentroidZSum = 0f;
        
        for (int i = 0; i < 255; i++)
        {
            // Angles for this segment
            float angle1 = Mathf.PI - (i * Mathf.PI / 255f);
            float angle2 = Mathf.PI - ((i + 1) * Mathf.PI / 255f);
            
            // Z coordinates of hit points (distance from X-axis)
            float z1 = distances[i] * Mathf.Sin(angle1);
            float z2 = distances[i + 1] * Mathf.Sin(angle2);
            
            // Centroid Z of triangle (origin, P1, P2) = (0 + z1 + z2) / 3
            float triangleCentroidZ = (z1 + z2) / 3f;
            
            // Area of this triangle
            float triangleArea = 0.5f * distances[i] * distances[i + 1] * sinAngleBetween;
            
            estimatedArea += triangleArea;
            weightedCentroidZSum += triangleCentroidZ * triangleArea;
        }
        
        // Calculate overall centroid Z (weighted average)
        float centroidZ = (estimatedArea > 0f) ? (weightedCentroidZSum / estimatedArea) : 0f;
        
        // Pappus's theorem: Volume = 2π * centroid_distance_from_axis * area
        float estimatedVolume = 2f * Mathf.PI * centroidZ * estimatedArea;
        
        Debug.Log($"Estimated shape area: {estimatedArea:F4} square units");
        Debug.Log($"Estimated volume (revolved around X-axis): {estimatedVolume:F4} cubic units");

        // Normalize all distances by reference distance (values will be 0-1 range)
        for (int i = 0; i < 256; i++)
        {
            distances[i] = Mathf.Clamp01(distances[i] / referenceDistance);
        }
        
        // Store for inspection
        capturedPhaseFunction = distances;
        
  
        
        // Pass to phase function baker and initiate bake
        if (phaseFunctionBaker != null)
        {
            phaseFunctionBaker.ApplyPhaseFunction(distances);
            Debug.Log("Phase function baked to texture successfully.");
        }
        else
        {
            Debug.LogWarning("PhaseFunctionToTexture reference is not set. " +
                           "Captured data stored in capturedPhaseFunction array.");
        }
    }
    
    /// <summary>
    /// Only captures the phase function without baking.
    /// </summary>
    [ContextMenu("Capture Phase Function Only")]
    public void CapturePhaseFunction()
    {
        Vector3 origin = transform.position;
        float[] distances = new float[256];
        
        for (int i = 0; i < 256; i++)
        {
            float angle = Mathf.PI - (i * Mathf.PI / 255f);
            Vector3 direction = new Vector3(Mathf.Cos(angle), 0f, Mathf.Sin(angle)).normalized;
            
            if (Physics.Raycast(origin, direction, out RaycastHit hit, rayLength, raycastMask))
            {
                distances[i] = hit.distance;
                
                if (drawDebugRays)
                {
                    Debug.DrawRay(origin, direction * hit.distance, Color.green, debugRayDuration);
                }
            }
            else
            {
                distances[i] = rayLength;
                
                if (drawDebugRays)
                {
                    Debug.DrawRay(origin, direction * rayLength, Color.red, debugRayDuration);
                }
            }
        }
        
        // Estimate area and volume using triangular sectors between adjacent rays
        float angleBetweenRays = Mathf.PI / 255f;
        float sinAngleBetween = Mathf.Sin(angleBetweenRays);
        float estimatedArea = 0f;
        float weightedCentroidZSum = 0f;
        
        for (int i = 0; i < 255; i++)
        {
            float angle1 = Mathf.PI - (i * Mathf.PI / 255f);
            float angle2 = Mathf.PI - ((i + 1) * Mathf.PI / 255f);
            
            float z1 = distances[i] * Mathf.Sin(angle1);
            float z2 = distances[i + 1] * Mathf.Sin(angle2);
            
            float triangleCentroidZ = (z1 + z2) / 3f;
            float triangleArea = 0.5f * distances[i] * distances[i + 1] * sinAngleBetween;
            
            estimatedArea += triangleArea;
            weightedCentroidZSum += triangleCentroidZ * triangleArea;
        }
        
        float centroidZ = (estimatedArea > 0f) ? (weightedCentroidZSum / estimatedArea) : 0f;
        float estimatedVolume = 2f * Mathf.PI * centroidZ * estimatedArea;
        
        Debug.Log($"Estimated shape area: {estimatedArea:F4} square units");
        Debug.Log($"Estimated volume (revolved around X-axis): {estimatedVolume:F4} cubic units");
        
        for (int i = 0; i < 256; i++)
        {
            distances[i] = Mathf.Clamp01(distances[i] / referenceDistance);
        }
        
        capturedPhaseFunction = distances;
    }
}


