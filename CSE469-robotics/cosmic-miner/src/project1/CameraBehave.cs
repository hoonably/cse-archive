using UnityEngine;

public class CameraBehave : MonoBehaviour
{
    public GameObject plane;
    public bool followAngle;
    private Vector3 displacement;
    private Quaternion angleDisplacement;

    void Start()
    {
        // 시작 시 plane과 카메라의 상대 위치/회전 저장
        displacement = this.transform.position - plane.transform.position;
        angleDisplacement = Quaternion.Inverse(plane.transform.rotation) * this.transform.rotation;
    }

    void LateUpdate() // 카메라 갱신은 LateUpdate 권장
    {
        if (followAngle)
        {
            // plane의 Y축 회전만 추출
            float yaw = plane.transform.eulerAngles.y;

            // Yaw만 있는 쿼터니언 생성
            Quaternion yawRot = Quaternion.Euler(0f, yaw, 0f);

            // 적용
            this.transform.rotation = yawRot * angleDisplacement;
            this.transform.position = plane.transform.position + yawRot * displacement;
        }

        else
        {
            // 위치만 따라가기
            this.transform.position = plane.transform.position + displacement;
        }
    }
}
