using UnityEngine;

public class ObjectMetaData : MonoBehaviour
{
    public Bounds ObjectBounds;

    private BoxCollider _collider;
    private void OnEnable()
    {
        _collider = GetComponent<BoxCollider>();
        ObjectBounds = _collider.bounds;
    }
}
