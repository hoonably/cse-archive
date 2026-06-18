using System.Collections.Generic;
using UnityEngine;

/// <summary>
/// 플레이어 주변으로 일정 각도 간격으로 Raycast를 쏴서
/// 볼 수 있는 영역을 폴리곤 Mesh로 만드는 스크립트.
/// (Top-down XZ 평면 기준)
/// </summary>
[RequireComponent(typeof(MeshFilter))]
public class FieldOfView : MonoBehaviour
{
    [Header("시야 설정")]
    [Tooltip("레이를 쏠 최대 거리(시야 반경)")]
    public float viewRadius = 10f;

    [Tooltip("360도를 몇 등분해서 Raycast할지")]
    public int rayCount = 256;

    [Tooltip("시야를 막는 벽/장애물 Layer")]
    public LayerMask obstacleMask;

    [Tooltip("Raycast 시작 높이 보정 (지형/벽 높이에 따라 살짝 위로 올리기 등)")]
    public float raycastHeightOffset = 0.5f;

    MeshFilter meshFilter;
    Mesh viewMesh;

    void Awake()
    {
        meshFilter = GetComponent<MeshFilter>();

        if (meshFilter.sharedMesh == null)
        {
            viewMesh = new Mesh();
            viewMesh.name = "FOV Mesh";
            meshFilter.sharedMesh = viewMesh;
        }
        else
        {
            viewMesh = meshFilter.sharedMesh;
        }
    }

    void LateUpdate()
    {
        GenerateFOVMesh();
    }

    void GenerateFOVMesh()
    {
        // 레이 개수 최소 보정
        int count = Mathf.Max(3, rayCount);

        float angleStep = 360f / count;

        Vector3 origin = transform.position + Vector3.up * raycastHeightOffset;

        List<Vector3> worldPoints = new List<Vector3>(count);

        // 0 ~ 360도까지 일정 간격으로 Raycast
        for (int i = 0; i < count; i++)
        {
            float angle = angleStep * i;
            float rad = angle * Mathf.Deg2Rad;

            Vector3 dir = new Vector3(Mathf.Cos(rad), 0f, Mathf.Sin(rad));

            Vector3 hitPoint;

            if (Physics.Raycast(origin, dir, out RaycastHit hit, viewRadius, obstacleMask, QueryTriggerInteraction.Ignore))
            {
                hitPoint = hit.point;
            }
            else
            {
                hitPoint = origin + dir * viewRadius;
            }

            worldPoints.Add(hitPoint);
        }

        // === Mesh 생성 ===
        int vertexCount = worldPoints.Count + 1; // 중심 + 외곽 점들

        Vector3[] vertices = new Vector3[vertexCount];
        int[] triangles = new int[(worldPoints.Count) * 3];

        // 로컬 기준 중심은 (0,0,0)
        vertices[0] = Vector3.zero;

        // 월드 좌표 → 로컬 좌표로 변환해서 Vertex에 저장
        for (int i = 0; i < worldPoints.Count; i++)
        {
            Vector3 localPoint = transform.InverseTransformPoint(worldPoints[i]);
            vertices[i + 1] = localPoint;
        }

        // 삼각형 인덱스 (부채꼴)
        // (0,1,2), (0,2,3), ..., (0, n-1, n)
        int triIndex = 0;
        for (int i = 1; i < vertexCount - 1; i++)
        {
            triangles[triIndex++] = 0;
            triangles[triIndex++] = i + 1;
            triangles[triIndex++] = i;
        }

        // 마지막 삼각형: (0, n, 1)
        triangles[triIndex++] = 0;
        triangles[triIndex++] = 1;
        triangles[triIndex++] = vertexCount - 1;

        viewMesh.Clear();
        viewMesh.vertices = vertices;
        viewMesh.triangles = triangles;
        viewMesh.RecalculateNormals();
        viewMesh.RecalculateBounds();
    }
}
