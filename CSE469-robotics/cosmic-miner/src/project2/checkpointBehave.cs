using UnityEngine;

public class checkpointBehave : MonoBehaviour
{
    public bool isTriggered = false;
    public MeshRenderer model_light;
    public Material mat_off;
    public Material mat_on;

    // 자기 자신의 위치 저장
    public Vector3 checkpointPos;

    void Start()
    {
        model_light.material = mat_off;

        // 시작 시 자신의 위치 저장
        checkpointPos = transform.position;
    }

    //private void OnTriggerEnter(Collider other)
    //{
    //    if (other.CompareTag("Player") && other.GetComponent<DroneControlUnit>())
    //    {
    //        model_light.material = mat_on;
    //        isTriggered = true;
    //    }
    //}

    // 외부에서 호출해서 불 켜는 함수
    public void lit()
    {
        model_light.material = mat_on;
        isTriggered = true;
    }
}
