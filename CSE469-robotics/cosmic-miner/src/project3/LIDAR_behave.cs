using UnityEngine;
using System.Collections.Generic;

public class LIDAR_behave : MonoBehaviour
{
    public Vector3 angularSpeed = new Vector3(0, 50f, 0);
    private Transform child;

    [TooltipAttribute("do not change this value")]
    public float range;
    public LayerMask LIDAR_layermask;
    public Vector3 resoucePos;  // if resouce is in range, it will tell the position. if not, 0,0,0

    void Start()
    {
        if (transform.childCount > 0)
            child = transform.GetChild(0);

        GetComponentInChildren<FieldOfView>().viewRadius = range;
    }

    void Update()
    {
        if (child != null)
            child.Rotate(angularSpeed * Time.deltaTime, Space.Self);
        FindResource();
    }

    /// <summary>
    /// angleDeg: xz 평면 기준 +z를 0도로, 시계 방향 0~360도
    /// range: 레이 길이
    /// layerMask: 충돌할 레이어 마스크
    /// </summary>
    public float GetDistance(float angleDeg)
    {
        Vector3 origin = this.transform.position;
        // 0~360으로 정리
        angleDeg %= 360f;

        // +z를 0도로, y축 기준 시계방향 회전
        // Unity에서 Quaternion.Euler(0, +각도, 0)는 위에서 내려볼 때 시계 방향 회전입니다.
        Vector3 dir = Quaternion.Euler(0f, angleDeg, 0f) * Vector3.forward;

        // 디버그용 레이(씬 뷰에서만 보임)
        Debug.DrawRay(origin, dir * range, Color.red);

        if (Physics.Raycast(origin, dir, out RaycastHit hit, range, LIDAR_layermask, QueryTriggerInteraction.Ignore))
        {
            // 부딪힌 경우, 충돌 지점까지의 거리 반환
            return hit.distance;
        }

        // 아무것도 안 맞으면 최대 range 반환
        return range;
    }
    public float GetDistance(Vector3 dir)
    {
        Vector3 origin = this.transform.position;

        // 디버그용 레이(씬 뷰에서만 보임)
        Debug.DrawRay(origin, dir * range, Color.red);

        if (Physics.Raycast(origin, dir, out RaycastHit hit, range, LIDAR_layermask, QueryTriggerInteraction.Ignore))
        {
            // 부딪힌 경우, 충돌 지점까지의 거리 반환
            return hit.distance;
        }

        // 아무것도 안 맞으면 최대 range 반환
        return range;
    }

    public void FindResource()
    {
        Collider[] cols = Physics.OverlapSphere(this.transform.position, range);
        bool foundResource = false;
        foreach (var col in cols)
        {
            if (col.CompareTag("resource"))
            {
                resoucePos = col.transform.position;
                foundResource = true;
            }
        }

        if (!foundResource)
        {
            resoucePos = Vector3.zero;
        }
    }
}
