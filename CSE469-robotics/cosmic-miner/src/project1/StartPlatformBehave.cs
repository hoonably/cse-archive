using UnityEngine;

public class StartPlatformBehave : MonoBehaviour
{
    public TimerBehave tb;
    private void OnTriggerExit(Collider other)
    {
        if (other.CompareTag("Player") && other.GetComponent<ControlUnit>())
        {
            tb.leaveStartingPoint();
        }
    }
}
