using UnityEngine;

public class FinishPlatformBehave : MonoBehaviour
{
    public TimerBehave tb;
    private void OnTriggerEnter(Collider other)
    {
        if (other.CompareTag("Player") && other.GetComponent<ControlUnit>())
        {
            tb.arriveFinishPoint();
        }
    }
}
