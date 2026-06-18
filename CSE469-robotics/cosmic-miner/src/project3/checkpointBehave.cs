using UnityEngine;

public class checkpointBehave : MonoBehaviour
{
    public bool isTriggered = false;
    public MeshRenderer model_light;
    public Material mat_off;
    public Material mat_on;

    // Start is called once before the first execution of Update after the MonoBehaviour is created
    void Start()
    {
        model_light.material = mat_off;
    }

    //private void OnTriggerEnter(Collider other)
    //{
    //    if (other.CompareTag("Player") && other.GetComponent<DroneControlUnit>())
    //    {
    //        model_light.material = mat_on;
    //        isTriggered = true;
    //    }
    //}

    public void lit()
    {
        model_light.material = mat_on;
        isTriggered = true;
    }
}
