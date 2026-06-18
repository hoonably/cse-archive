using UnityEngine;

public class IMU_Behave : MonoBehaviour
{
    // Public readouts (world frame)
    public Vector3 accel;       // m/s^2, linear acceleration of IMU
    public Vector3 ang_accel;   // rad/s^2, angular acceleration (time-derivative of angular velocity)

    public Vector3 linearVelocity;   // m/s, IMU point linear velocity in world frame
    public Vector3 angularVelocity;  // rad/s, IMU angular velocity in world frame

    private Rigidbody rootRb;        // nearest parent rigidbody

    // Previous-step samples for finite differencing
    private Vector3 prevLinearVelocity;
    private Vector3 prevAngularVelocity;
    private bool firstFrame = true;

    void Start()
    {
        // Find the closest Rigidbody in self or parents
        rootRb = GetComponentInParent<Rigidbody>();

        prevLinearVelocity = Vector3.zero;
        prevAngularVelocity = Vector3.zero;
        accel = Vector3.zero;
        ang_accel = Vector3.zero;
        firstFrame = true;
    }

    void FixedUpdate()
    {
        float dt = Time.fixedDeltaTime;
        if (dt <= 0f) return;

        // If no rigidbody found, output zeros safely
        if (rootRb == null)
        {
            linearVelocity = Vector3.zero;
            angularVelocity = Vector3.zero;

            if (firstFrame)
            {
                accel = Vector3.zero;
                ang_accel = Vector3.zero;
                firstFrame = false;
            }
            else
            {
                accel = (linearVelocity - prevLinearVelocity) / dt;
                ang_accel = (angularVelocity - prevAngularVelocity) / dt;
            }

            prevLinearVelocity = linearVelocity;
            prevAngularVelocity = angularVelocity;
            return;
        }

        // --- 1) Get rigidbody's base motion in world frame ---
        // Rigidbody linear velocity at its center of mass
        Vector3 rbVel = rootRb.linearVelocity;                // m/s (world)
        Vector3 rbAngVel = rootRb.angularVelocity;      // rad/s (world)

        // --- 2) Lift to this IMU's position ---
        // r = offset from RB CoM to this IMU in world coordinates
        Vector3 r = transform.position - rootRb.worldCenterOfMass;

        // Linear velocity of an offset point on a rigid body:
        // v_point = v_com + �� �� r
        Vector3 imuVel = rbVel + Vector3.Cross(rbAngVel, r);

        // Angular velocity at any point on a rigid body is the same as the body's angular velocity
        Vector3 imuAngVel = rbAngVel;

        // --- 3) Time derivatives (finite difference over fixed dt) ---
        Vector3 imuAccel;
        Vector3 imuAngAccel;

        if (firstFrame)
        {
            // No meaningful derivative on first frame
            imuAccel = Vector3.zero;
            imuAngAccel = Vector3.zero;
            firstFrame = false;
        }
        else
        {
            imuAccel = (imuVel - prevLinearVelocity) / dt;
            imuAngAccel = (imuAngVel - prevAngularVelocity) / dt;
        }

        // --- 4) Publish ---
        linearVelocity = imuVel;
        angularVelocity = imuAngVel;
        accel = imuAccel;
        ang_accel = imuAngAccel;

        // --- 5) Store for next step ---
        prevLinearVelocity = imuVel;
        prevAngularVelocity = imuAngVel;
    }
}
