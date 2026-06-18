using UnityEngine;

public class AccelBehave : MonoBehaviour
{
    public Vector3 accel;
    public void OnTriggerStay(Collider other)
    {
        Vector3 grav = accel;
        grav.y = 0f;
        Vector3 torque = Vector3.up * accel.y;

        if (other.CompareTag("Player") && (other.GetComponent<ControlUnit>() || other.GetComponent<DroneControlUnit>()))
        {
            Rigidbody rb = other.GetComponent<Rigidbody>();
            rb.AddForce(rb.mass * grav, ForceMode.Force);
            rb.AddTorque(torque * rb.inertiaTensor.y, ForceMode.Force);

            if (other.GetComponent<ForceManager>())
            {
                other.GetComponent<ForceManager>().AddForce(rb.mass * grav, rb.gameObject);
            }
        }
    }
}
