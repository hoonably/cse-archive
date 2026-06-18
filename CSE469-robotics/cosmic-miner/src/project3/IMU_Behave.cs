using UnityEngine;

public class IMU_Behave : MonoBehaviour
{
    // ===== Public readouts (world frame) =====
    public Vector3 accel;       // m/s^2, filtered linear acceleration
    public Vector3 ang_accel;   // rad/s^2, filtered angular acceleration

    public Vector3 linearVelocity;   // m/s, IMU point linear velocity (world)
    public Vector3 angularVelocity;  // rad/s, angular velocity (world)

    private Rigidbody rootRb;
    private ForceManager fm;

    public Vector3 gravity;
    public Vector3 angularAccel;

    void Start()
    {
        rootRb = GetComponentInParent<Rigidbody>();

        accel = Vector3.zero;
        ang_accel = Vector3.zero;

        fm = rootRb.GetComponent<ForceManager>();
    }

    void FixedUpdate()
    {
        float dt = Time.fixedDeltaTime;
        if (dt <= 0f) return;

        if (rootRb == null)
        {
            linearVelocity = Vector3.zero;
            angularVelocity = Vector3.zero;
            accel = Vector3.zero;
            ang_accel = Vector3.zero;
            return;
        }

        // 1) 속도 / 각속도
        linearVelocity = rootRb.linearVelocity;
        angularVelocity = rootRb.angularVelocity;

        // 2) 차분으로 raw 가속도 계산
        accel = fm.sumForce / rootRb.mass;
        ang_accel = fm.sumTorque / rootRb.inertiaTensor.y;

        if (rootRb.GetComponent<ControlUnit>() && rootRb.GetComponent<ControlUnit>().ab != null)
        {
            AccelBehave ab = rootRb.GetComponent<ControlUnit>().ab;
            gravity = ab.accel;
            gravity.y = 0f;
            angularAccel = ab.accel;
            angularAccel.x = 0f;
            angularAccel.z = 0f;
        }
        else if (rootRb.GetComponent<DroneControlUnit>() && rootRb.GetComponent<DroneControlUnit>().ab != null)
        {
            AccelBehave ab = rootRb.GetComponent<DroneControlUnit>().ab;
            gravity = ab.accel;
            gravity.y = 0f;
            angularAccel = ab.accel;
            angularAccel.x = 0f;
            angularAccel.z = 0f;
        }
    }

}
