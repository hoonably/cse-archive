using System.Collections.Generic;
using System.IO;
using UnityEngine;

public class PositionLogger : MonoBehaviour
{
    // 인스펙터에서 채울 오브젝트 리스트
    public GPS_Behave gps;
    private List<GameObject> targets = new List<GameObject>();

    // 저장될 파일 이름 (원하면 인스펙터에서 바꿀 수 있게 public)
    public string fileName = "object_positions.csv";

    void Start()
    {

        // 1) CSV 헤더 + 데이터 준비
        // 예: "Name,X,Z\nCube,0.12,-3.5\n..."
        System.Text.StringBuilder sb = new System.Text.StringBuilder();
        sb.AppendLine("Name,X,Z");

        sb.AppendLine($"{gps.gameObject.name},{gps.transform.position.x},{gps.transform.position.z}");
        for (int i = 0; i < gps.checkpoints.Count; i++)
        {
            targets.Add(gps.checkpoints[i].gameObject);
        }

        foreach (GameObject go in targets)
        {
            if (go == null) continue; // 빈 슬롯 안전 처리

            Vector3 p = go.transform.position;
            string line = $"{go.name},{p.x},{p.z}";
            sb.AppendLine(line);
        }

        string csvText = sb.ToString();

        // 2) 파일 경로 결정
        // Application.dataPath 는 프로젝트의 Assets 폴더 절대경로
        string path = Path.Combine(Application.dataPath, fileName);

        // 3) 파일로 저장
        try
        {
            File.WriteAllText(path, csvText);
            Debug.Log($"[PositionLogger] CSV saved to: {path}");
        }
        catch (System.Exception e)
        {
            Debug.LogError($"[PositionLogger] Failed to write CSV: {e}");
        }

        // 4) 콘솔에도 출력 (원하면 주석 처리 가능)
        Debug.Log("[PositionLogger] CSV content:\n" + csvText);
    }
}
