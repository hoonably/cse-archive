using UnityEngine;

public class StartPlatformBehave : MonoBehaviour
{
    public TimerBehave tb;
    private void OnTriggerExit(Collider other)
    {
        if (other.CompareTag("Player"))
        {
            var controlUnit = other.GetComponent<ControlUnit>();
            var droneControlUnit = other.GetComponent<DroneControlUnit>();
            
            if (controlUnit || droneControlUnit)
            {
                tb.leaveStartingPoint();
                
                if (droneControlUnit)
                {
                    droneControlUnit.leaveStartingPoint();
                }
            }
        }
    }
}
