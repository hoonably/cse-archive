using UnityEngine;
using UnityEngine.UI;
using System.Collections.Generic;

public class FogOfWarPersistent2 : MonoBehaviour
{
    [Header("타겟 (여러 드론 시야 공유)")]
    public List<Transform> targets;   // 원래 target 대신 여러 개

    [Header("맵 월드 범위 (자동 계산)")]
    public Vector2 worldMin;   // x = minX, y = minZ
    public Vector2 worldMax;   // x = maxX, y = maxZ

    [Header("머티리얼")]
    public Material overlayMaterial;   // FogOfWarPersistent.shader
    public Material revealMaterial2;   // FogReveal2.shader

    [Header("텍스처 설정")]
    public int textureSize = 1024;

    [Header("Reveal 설정 (모든 드론 공통)")]
    public float radius = 0.05f;      // FogReveal2의 _Radius
    public float softness = 0.02f;    // FogReveal2의 _Softness

    RenderTexture fogRT;
    RenderTexture tempRT;

    [Header("월드 단위 시야 설정")]
    public float worldRadius = 10f;       // 인게임 거리 (예: 10유닛)
    public float worldSoftness = 2f;

    public static FogOfWarPersistent2 Instance { get; private set; }

    private void Awake()
    {
        // 이미 인스턴스가 존재하는데 새로 생기려 하면 파괴
        if (Instance != null && Instance != this)
        {
            Destroy(gameObject);
            return;
        }

        Instance = this;

        // 다른 씬으로 넘어가도 유지하려면 사용
        DontDestroyOnLoad(gameObject);
        UpdateWorldBoundsFromRect();
    }

    void OnValidate()
    {
        UpdateWorldBoundsFromRect();
    }

    /// <summary>
    /// 이 스크립트가 붙어있는 RectTransform을 기준으로
    /// worldMin/worldMax를 자동 계산 (x=월드 X, y=월드 Z)
    /// </summary>
    void UpdateWorldBoundsFromRect()
    {
        RectTransform rt = GetComponent<RectTransform>();
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

    void Start()
    {
        fogRT = new RenderTexture(textureSize, textureSize, 0, RenderTextureFormat.ARGB32);
        fogRT.wrapMode = TextureWrapMode.Clamp;
        fogRT.filterMode = FilterMode.Bilinear;

        tempRT = new RenderTexture(textureSize, textureSize, 0, RenderTextureFormat.ARGB32);
        tempRT.wrapMode = TextureWrapMode.Clamp;
        tempRT.filterMode = FilterMode.Bilinear;

        // 처음에는 전체가 어두운 상태
        var active = RenderTexture.active;
        RenderTexture.active = fogRT;
        GL.Clear(true, true, Color.black);
        RenderTexture.active = active;

        if (overlayMaterial != null)
        {
            overlayMaterial.SetTexture("_FogTex", fogRT);
        }

        if (revealMaterial2 != null)
        {
            revealMaterial2.SetFloat("_Radius", radius);
            revealMaterial2.SetFloat("_Softness", softness);
        }
        GetComponent<RawImage>().enabled = true;
    }

    void Update()
    {
        if (overlayMaterial == null || revealMaterial2 == null)
            return;
        if (targets == null || targets.Count == 0)
            return;

        float worldWidth = worldMax.x - worldMin.x;
        float worldHeight = worldMax.y - worldMin.y;
        if (worldHeight <= 0f) worldHeight = 0.0001f;

        // 월드 단위 → UV 단위 변환
        float radiusUV = worldRadius / worldHeight;
        float softnessUV = worldSoftness / worldHeight;

        revealMaterial2.SetFloat("_WorldAspect", worldWidth / worldHeight);
        revealMaterial2.SetFloat("_Radius", radiusUV);
        revealMaterial2.SetFloat("_Softness", softnessUV);

        // 이후에는 기존처럼 드론들 루프 돌면서 Center와 PrevTex만 세팅해서 Blit
        foreach (var t in targets)
        {
            if (t == null) continue;
            if (!t.gameObject.activeInHierarchy) continue;

            Vector3 pos = t.position;

            float u = Mathf.InverseLerp(worldMin.x, worldMax.x, pos.x);
            float v = Mathf.InverseLerp(worldMin.y, worldMax.y, pos.z);
            Vector4 center = new Vector4(u, v, 0, 0);

            revealMaterial2.SetVector("_Center", center);
            revealMaterial2.SetTexture("_PrevTex", fogRT);

            Graphics.Blit(fogRT, tempRT, revealMaterial2);
            var swap = fogRT; fogRT = tempRT; tempRT = swap;
        }

        overlayMaterial.SetTexture("_FogTex", fogRT);
    }

    void OnDestroy()
    {
        if (fogRT != null) fogRT.Release();
        if (tempRT != null) tempRT.Release();
    }
}
