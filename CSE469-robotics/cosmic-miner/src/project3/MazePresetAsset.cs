using UnityEngine;

[CreateAssetMenu(fileName = "MazePreset", menuName = "Maze/Maze Preset")]
public class MazePresetAsset : ScriptableObject
{
    public int width;
    public int height;

    public Vector2Int start;
    public Vector2Int goal;

    // 길/벽 정보: 0 = 벽, 1 = 길
    // 길이는 width * height
    public int[] map;

    // 간선(openRight[x,y]): (x,y) ↔ (x+1,y) 연결 여부
    // 길이는 (width - 1) * height
    public bool[] openRight;

    // 간선(openUp[x,y]): (x,y) ↔ (x,y+1) 연결 여부
    // 길이는 width * (height - 1)
    public bool[] openUp;

    // 선택: 정답 경로 (디버그용)
    public Vector2Int[] solutionPath;
}
