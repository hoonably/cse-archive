using UnityEngine;

public class AccelBehave : MonoBehaviour
{
    public Vector3 accel;
    public void OnTriggerStay(Collider other)
    {
        if (other.CompareTag("Player") && (other.GetComponent<ControlUnit>() || other.GetComponent<DroneControlUnit>()))
        {
            Rigidbody rb = other.GetComponent<Rigidbody>();
            rb.AddForce(rb.mass * accel,ForceMode.Force);
        }
    }
}
