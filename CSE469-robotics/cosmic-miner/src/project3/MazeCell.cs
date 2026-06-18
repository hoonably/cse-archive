using UnityEngine;

/// <summary>
/// 미로의 한 칸을 표현하는 셀 컴포넌트.
/// - Floor / WallRight(+X) / WallUp(+Y)를 자식으로 가지고,
/// - MazeGenerator에서 전달받은 정보로 활성/비활성 및 좌표를 설정한다.
/// </summary>
public class MazeCell : MonoBehaviour
{
    [Header("References")]
    [Tooltip("바닥 메쉬 오브젝트 (없으면 null 허용)")]
    public GameObject floor;

    [Tooltip("+X 방향(오른쪽) 벽 오브젝트")]
    public GameObject wallRight;

    [Tooltip("+Y 방향(위쪽) 벽 오브젝트")]
    public GameObject wallUp;

    [Header("Cell Info")]
    [Tooltip("그리드 상의 좌표 (x,y)")]
    public Vector2Int cellIndex;

    [Tooltip("이 셀이 길(통로)인지 여부")]
    public bool isPath = true;

    [Tooltip("씬에서 셀 간 간격(월드 좌표상의 셀 크기)")]
    public float cellSize = 12f;

    /// <summary>
    /// MazeGenerator에서 셀 생성 직후 호출해서 상태를 셋업.
    /// - index: 그리드 좌표
    /// - path: 이 셀이 길인지(1) 벽인지(0)
    /// - hasRightWall: +X 방향에 벽이 있어야 하는지
    /// - hasUpWall: +Y 방향에 벽이 있어야 하는지
    /// </summary>
    public void Setup(Vector2Int index, bool path, bool hasRightWall, bool hasUpWall, Vector3 offset, float maxGravity)
    {
        cellIndex = index;
        isPath = path;

        // 월드 위치 배치 (원하면 MazeGenerator 쪽에서 직접 배치해도 됨)
        transform.localPosition =
            new Vector3(index.x * cellSize, 0f, index.y * cellSize) + offset;

        // 바닥 활성화: 길이면 보이게, 벽이면 감추거나 다른 머티리얼을 써도 됨
        if (floor != null)
        {
            floor.SetActive(path);
        }

        // 벽 활성화
        if (wallRight != null)
        {
            wallRight.SetActive(hasRightWall);
        }

        if (wallUp != null)
        {
            wallUp.SetActive(hasUpWall);
        }

        Vector2 dir2D = Random.insideUnitCircle.normalized;
        float magnitude = Random.Range(0f, maxGravity);
        Vector3 nowGrav = new Vector3(dir2D.x, 0f, dir2D.y) * magnitude;
        GetComponentInChildren<AccelBehave>().accel = nowGrav;
        //var vel = GetComponentInChildren<ParticleSystem>().velocityOverLifetime;
        //vel.x = nowGrav.x;
        //vel.z = nowGrav.z;
    }

    public void noGravity()
    {
        //GetComponentInChildren<ParticleSystem>().Stop();
        GetComponentInChildren<AccelBehave>().accel = Vector3.zero;
    }

    /// <summary>
    /// 셀의 중앙 월드 좌표를 반환 (디버그/기즈모용 헬퍼)
    /// </summary>
    public Vector3 GetCenterWorldPos()
    {
        return transform.position;
    }

    /// <summary>
    /// 이 셀을 강조 표시하고 싶을 때(예: solutionPath 시각화) 사용할 수 있는 간단한 함수.
    /// floor에 MeshRenderer가 있을 때만 동작.
    /// </summary>
    public void SetHighlight(Color color)
    {
        if (floor == null) return;

        var renderer = floor.GetComponent<MeshRenderer>();
        if (renderer != null)
        {
            renderer.material.color = color;
        }
    }
}
