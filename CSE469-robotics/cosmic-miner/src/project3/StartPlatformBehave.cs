using UnityEngine;

public class StartPlatformBehave : MonoBehaviour
{
    public TimerBehave tb;
    private void OnTriggerStay(Collider other)
    {
        if (other.CompareTag("Player"))
        {
            tb.leaveStartingPoint();
        }
    }
}
