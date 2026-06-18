using UnityEngine;

/// <summary>
/// FOV Mesh를 전용 카메라로 RenderTexture에 그려서
/// FogOfWar용 "시야 마스크" 텍스처를 만드는 스크립트.
/// worldMin/worldMax는 RectTransform으로부터 자동 계산됨.
/// </summary>
[ExecuteAlways]
public class FovMaskRenderer : MonoBehaviour
{
    [Header("참조")]
    public Camera fovCamera;
    public Material revealMaterial;

    [Header("마스크 텍스처 설정")]
    public int textureSize = 1024;

    [Header("자동 계산된 맵 범위 (RectTransform 기반)")]
    public Vector2 worldMin;   // x = minX, y = minZ
    public Vector2 worldMax;   // x = maxX, y = maxZ

    RenderTexture fovMaskRT;
    RectTransform rt;  // RectTransform reference

    void Awake()
    {
        rt = GetComponent<RectTransform>();
        UpdateWorldBoundsFromRect();
        CreateOrResizeRT();
        SetupCamera();
        BindToRevealMaterial();
    }

    void Update()
    {
        UpdateWorldBoundsFromRect();
        SetupCamera();
    }

    // ==============================
    //  RectTransform 기반 worldMin/max 자동 계산
    // ==============================
    void UpdateWorldBoundsFromRect()
    {
        if (rt == null) return;

        Vector3[] corners = new Vector3[4];
        rt.GetWorldCorners(corners); // 좌하, 좌상, 우상, 우하

        float minX = corners[0].x;
        float maxX = corners[0].x;
        float minZ = corners[0].z;
        float maxZ = corners[0].z;

        for (int i = 1; i < 4; i++)
        {
            Vector3 c = corners[i];
            if (c.x < minX) minX = c.x;
            if (c.x > maxX) maxX = c.x;
            if (c.z < minZ) minZ = c.z;
            if (c.z > maxZ) maxZ = c.z;
        }

        worldMin = new Vector2(minX, minZ);
        worldMax = new Vector2(maxX, maxZ);
    }

    // ==============================
    // RenderTexture 생성/갱신
    // ==============================
    void CreateOrResizeRT()
    {
        float width = Mathf.Abs(worldMax.x - worldMin.x);
        float height = Mathf.Abs(worldMax.y - worldMin.y);
        if (height <= 0f) height = 1f;
        float worldAspect = width / height; // X/Z 비율

        int texHeight = textureSize;
        int texWidth = Mathf.Max(1, Mathf.RoundToInt(textureSize * worldAspect));

        if (fovMaskRT != null &&
            (fovMaskRT.width != texWidth || fovMaskRT.height != texHeight))
        {
            fovMaskRT.Release();
            DestroyImmediate(fovMaskRT);
            fovMaskRT = null;
        }

        if (fovMaskRT == null)
        {
            fovMaskRT = new RenderTexture(texWidth, texHeight, 24, RenderTextureFormat.ARGB32);
            fovMaskRT.name = "FOV Mask RT";
            fovMaskRT.Create();
        }

        if (fovCamera != null)
            fovCamera.targetTexture = fovMaskRT;
    }

    // ==============================
    // 카메라 세팅 (월드 영역 전체를 커버)
    // ==============================
    void SetupCamera()
    {
        if (fovCamera == null) return;

        float width = Mathf.Abs(worldMax.x - worldMin.x);
        float height = Mathf.Abs(worldMax.y - worldMin.y);

        // 월드 중심
        float centerX = (worldMin.x + worldMax.x) * 0.5f;
        float centerZ = (worldMin.y + worldMax.y) * 0.5f;

        // 카메라는 위에서(XZ 평면) 내려다보는 형태
        fovCamera.transform.position = new Vector3(centerX, fovCamera.transform.position.y, centerZ);
        fovCamera.transform.rotation = Quaternion.Euler(90f, 0f, 0f);

        fovCamera.orthographic = true;

        // 세로 기준(높이)에 맞춰서 orthographicSize 를 설정
        // orthographicSize = world 높이의 반
        fovCamera.orthographicSize = height * 0.5f;

        // 가로/세로 비율에 맞게 카메라 aspect 를 맞춰주려면,
        // RenderTexture 해상도도 world 비율에 맞게 만들면 됨 (아래 CreateOrResizeRT 참고)
    }


    // ==============================
    // Reveal 머티리얼에 FOV 마스크 텍스처 바인딩
    // ==============================
    void BindToRevealMaterial()
    {
        if (revealMaterial != null && fovMaskRT != null)
        {
            revealMaterial.SetTexture("_FovMask", fovMaskRT);
        }
    }

    // ==============================
    // RT 정리
    // ==============================
    void OnDisable()
    {
        if (fovMaskRT != null)
        {
            if (fovCamera && fovCamera.targetTexture == fovMaskRT)
                fovCamera.targetTexture = null;

            fovMaskRT.Release();
            DestroyImmediate(fovMaskRT);
            fovMaskRT = null;
        }
    }
}
