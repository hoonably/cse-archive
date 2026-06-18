using UnityEngine;

public class CameraBehave : MonoBehaviour
{
    public GameObject target;
    public bool followAngle;
    private Vector3 displacement;
    private Quaternion angleDisplacement;

    void Start()
    {
        displacement = this.transform.position - target.transform.position;
        angleDisplacement = Quaternion.Inverse(target.transform.rotation) * this.transform.rotation;
    }

    void LateUpdate()
    {
        if(target == null)
        {
            Debug.LogWarning("Add target to CameraBehave in MainCamera");
            return;
        }

        if (followAngle)
        {
            float yaw = target.transform.eulerAngles.y;

            Quaternion yawRot = Quaternion.Euler(0f, yaw, 0f);

            this.transform.rotation = yawRot * angleDisplacement;
            this.transform.position = target.transform.position + yawRot * displacement;
        }

        else
        {
            this.transform.position = target.transform.position + displacement;
        }
    }
}
