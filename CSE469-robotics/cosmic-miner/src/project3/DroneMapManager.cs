using UnityEngine;
using System.Collections.Generic;

/// <summary>
/// 전역 공유 맵을 담당하는 싱글톤 매니저
/// Branch 좌표와 4방향 상태를 관리
/// + (좌표, count) 기반으로 모든 드론이 방문한 cell trajectory 기록
/// </summary>
public class DroneMapManager : MonoBehaviour
{
    // ===================== Singleton =====================
    private static DroneMapManager _instance;
    public static DroneMapManager Instance
    {
        get
        {
            if (_instance == null)
            {
                _instance = FindFirstObjectByType<DroneMapManager>();
                if (_instance == null)
                {
                    GameObject go = new GameObject("DroneMapManager");
                    _instance = go.AddComponent<DroneMapManager>();
                    DontDestroyOnLoad(go);
                }
            }
            return _instance;
        }
    }

    // ===================== Constants =====================
    public const float MAP_CUBE_SIZE = 12.0f;

    // ===================== Direction State =====================
    public enum DirectionState
    {
        Unknown,
        Exploring1,
        Exploring2,
        Exploring3,
        DeadEnd,
        Trunk,
        CameFrom
    }

    // ===================== Branch Info =====================
    public class BranchInfo
    {
        public int branchId;
        public Vector3 position;

        // 도착 순서 기록 (기존 로직 유지)
        public int[] arrivedDrones;

        // 방향 상태
        public Dictionary<Vector3, DirectionState> directionStates;

        public BranchInfo(int id, Vector3 pos)
        {
            branchId = id;
            position = pos;
            arrivedDrones = new int[] { -1, -1, -1 };

            directionStates = new Dictionary<Vector3, DirectionState>
            {
                { Vector3.forward, DirectionState.Unknown },
                { Vector3.back,    DirectionState.Unknown },
                { Vector3.left,    DirectionState.Unknown },
                { Vector3.right,   DirectionState.Unknown }
            };
        }

        // 🔴 절대 삭제하지 않음 (DroneControlUnit 호환)
        public bool RegisterDroneArrival(int droneId)
        {
            for (int i = 0; i < arrivedDrones.Length; i++)
                if (arrivedDrones[i] == droneId)
                    return false;

            for (int i = 0; i < arrivedDrones.Length; i++)
            {
                if (arrivedDrones[i] == -1)
                {
                    arrivedDrones[i] = droneId;
                    return true;
                }
            }
            return false;
        }
    }

    // ===================== Branch Storage =====================
    private List<BranchInfo> branches = new List<BranchInfo>();
    private Dictionary<Vector3, int> positionToBranchId = new Dictionary<Vector3, int>();

    // ===================== 7th Branch Path Tracking =====================
    // 각 드론별 7번째 브랜치 이후 방문 경로 (중복 없이 순차 기록)
    private Dictionary<int, List<Vector3>> branch7DronePaths = new Dictionary<int, List<Vector3>>();
    // 각 드론별 7번째 브랜치 진입 여부
    private Dictionary<int, bool> droneEnteredBranch7 = new Dictionary<int, bool>();
    // 각 드론별 이미 방문한 셀 (중복 체크용)
    private Dictionary<int, HashSet<Vector3>> branch7VisitedCells = new Dictionary<int, HashSet<Vector3>>();
    // 7번째 브랜치 시작 위치 저장
    private Vector3? branch7StartPosition = null;

    // ===================== Ready Sync =====================
    public bool[] droneReadyStatus = new bool[3];

    public void RegisterDroneReady(int droneIndex)
    {
        if (droneIndex >= 0 && droneIndex < 3)
            droneReadyStatus[droneIndex] = true;
    }

    public bool IsAllReady
    {
        get
        {
            foreach (bool ready in droneReadyStatus)
                if (!ready) return false;
            return true;
        }
    }

    // =====================================================
    // ============ ✅ (좌표, count) TRAJECTORY ============
    // =====================================================

    // cell 별 방문한 드론 집합 (중복 방지)
    private Dictionary<Vector3, HashSet<int>> cellVisitMap
        = new Dictionary<Vector3, HashSet<int>>();

    // count == 3 되는 순간의 trajectory (순서 보존)
    private List<Vector3> finalTrajectory
        = new List<Vector3>();
    
    // ⭐ 첫 번째 셀 스킵 플래그
    private bool firstCellSkipped = false;

    /// <summary>
    /// ControlUnit이 다음 목표 셀을 가져가기 (FIFO 큐 방식)
    /// </summary>
    public bool TryGetNextTrajectoryCell(out Vector3 nextCell)
    {
        if (finalTrajectory.Count > 0)
        {
            nextCell = finalTrajectory[0];
            finalTrajectory.RemoveAt(0);  // 소모
            
            // 🔍 디버그: 전달되는 좌표 확인
            Debug.Log($"<color=cyan>[DroneMapManager]</color> TryGetNextTrajectoryCell: Grid={GetGridPos(nextCell)} | WorldPos=({nextCell.x:F1}, {nextCell.z:F1}) | Remaining={finalTrajectory.Count}");
            
            return true;
        }
        nextCell = Vector3.zero;
        return false;
    }

    /// <summary>
    /// 현재 남은 경로 개수
    /// </summary>
    public int TrajectoryCount => finalTrajectory.Count;


    /// <summary>
    /// 드론이 특정 cell을 실제로 통과했음을 기록
    /// - cell별로 방문 드론 집합 관리
    /// - 방문 수가 3이 되는 순간, trajectory 리스트에 "한 번만" 추가
    /// </summary>
    public void RecordTrajectory(Vector3 worldPos, int droneId)
    {
        Vector3 cellPos = SnapToGrid(worldPos);

        // cell 방문 기록 없으면 생성
        if (!cellVisitMap.TryGetValue(cellPos, out var visitedSet))
        {
            visitedSet = new HashSet<int>();
            cellVisitMap[cellPos] = visitedSet;
        }

        // 이미 이 드론이 이 cell 방문했으면 무시
        if (!visitedSet.Add(droneId))
            return;

        // 정확히 "이번에" 3이 되었을 때만 기록
        //! 두개만 가도 무조건
        if (visitedSet.Count == 2)
        {
            // ⭐ 첫 번째 셀은 출발 위치이므로 스킵
            if (!firstCellSkipped)
            {
                firstCellSkipped = true;
                Debug.Log($"<color=yellow>[Trajectory]</color> 첫 번째 셀 {GetGridPos(cellPos)} 스킵 (출발 위치)");
                return;
            }
            
            finalTrajectory.Add(cellPos);

            // 🔍 디버그: 추가된 좌표 확인
            Debug.Log(
                $"<color=lime>[Trajectory]</color> " +
                $"All drones passed cell {GetGridPos(cellPos)} | WorldPos=({cellPos.x:F1}, {cellPos.z:F1})"
            );

            PrintFinalTrajectory();
        }
    }

    private void PrintFinalTrajectory()
    {
        Debug.Log("<color=cyan>=== Final Trajectory (count == 3, ordered) ===</color>");

        foreach (Vector3 pos in finalTrajectory)
        {
            Debug.Log($"<color=yellow>Cell {GetGridPos(pos)}</color>");
        }

        Debug.Log("<color=cyan>============================================</color>");
    }

    // ===================== Unity =====================
    void Awake()
    {
        if (_instance != null && _instance != this)
        {
            Destroy(gameObject);
            return;
        }

        _instance = this;
        DontDestroyOnLoad(gameObject);
    }

    // ===================== Grid Utils =====================
    public Vector3 SnapToGrid(Vector3 worldPos)
    {
        float x = Mathf.Round(worldPos.x / MAP_CUBE_SIZE) * MAP_CUBE_SIZE;
        float z = Mathf.Round(worldPos.z / MAP_CUBE_SIZE) * MAP_CUBE_SIZE;
        return new Vector3(x, 0f, z);
    }

    private string GetGridPos(Vector3 worldPos)
    {
        int gridX = Mathf.RoundToInt(worldPos.x / MAP_CUBE_SIZE) + 10;
        int gridZ = Mathf.RoundToInt(worldPos.z / MAP_CUBE_SIZE) + 10;
        return $"({gridX},{gridZ})";
    }

    // ===================== Branch Management =====================
    public BranchInfo GetOrCreateBranch(Vector3 position)
    {
        Vector3 snapped = SnapToGrid(position);

        if (positionToBranchId.TryGetValue(snapped, out int id))
            return branches[id];

        int newId = branches.Count;
        BranchInfo newBranch = new BranchInfo(newId, snapped);
        branches.Add(newBranch);
        positionToBranchId[snapped] = newId;

        return newBranch;
    }

    public void SetDirectionState(Vector3 branchPos, Vector3 direction, DirectionState state)
    {
        BranchInfo branch = GetOrCreateBranch(branchPos);
        if (branch.directionStates.ContainsKey(direction))
            branch.directionStates[direction] = state;
    }

    public DirectionState GetDirectionState(Vector3 branchPos, Vector3 direction)
    {
        Vector3 snapped = SnapToGrid(branchPos);
        if (!positionToBranchId.ContainsKey(snapped))
            return DirectionState.Unknown;

        BranchInfo branch = branches[positionToBranchId[snapped]];
        return branch.directionStates.TryGetValue(direction, out var s)
            ? s
            : DirectionState.Unknown;
    }

    // ===================== Reports =====================
    public void ReportDeadEnd(Vector3 branchPos, Vector3 deadEndDirection, int droneId)
    {
        BranchInfo branch = GetOrCreateBranch(branchPos);
        SetDirectionState(branchPos, deadEndDirection, DirectionState.DeadEnd);

        foreach (var kvp in branch.directionStates)
        {
            if (kvp.Value == DirectionState.Unknown ||
                kvp.Value == DirectionState.Exploring1 ||
                kvp.Value == DirectionState.Exploring2 ||
                kvp.Value == DirectionState.Exploring3)
            {
                SetDirectionState(branchPos, kvp.Key, DirectionState.Trunk);
            }
        }
    }

    public void ReportNewBranchFound(Vector3 previousBranchPos, Vector3 cameFromDirection, int droneId)
    {
        SetDirectionState(previousBranchPos, cameFromDirection, DirectionState.Trunk);
    }

    // ===================== 7th Branch Path Tracking =====================
    
    /// <summary>
    /// 현재 브랜치 개수 반환
    /// </summary>
    public int BranchCount => branches.Count;

    /// <summary>
    /// 드론이 7번째 브랜치 시작점에 진입했음을 등록
    /// </summary>
    public void RegisterBranch7Entry(int droneId, Vector3 branchPos)
    {
        if (branches.Count != 7) return;
        
        Vector3 snapped = SnapToGrid(branchPos);
        
        // 7번째 브랜치 시작 위치 저장 (최초 1회)
        if (branch7StartPosition == null)
        {
            branch7StartPosition = snapped;
            Debug.Log($"<color=magenta>[Branch7]</color> 7번째 브랜치 시작점 설정: {GetGridPos(snapped)}");
        }
        
        // 이미 등록된 드론인지 확인
        if (droneEnteredBranch7.ContainsKey(droneId) && droneEnteredBranch7[droneId])
            return;
        
        // 드론 등록
        droneEnteredBranch7[droneId] = true;
        branch7DronePaths[droneId] = new List<Vector3>();
        branch7VisitedCells[droneId] = new HashSet<Vector3>();
        
        Debug.Log($"<color=magenta>[Branch7]</color> Drone{droneId} 7번째 브랜치 진입 등록 at {GetGridPos(snapped)}");
    }

    /// <summary>
    /// 드론의 셀 방문 기록 (7번째 브랜치 진입 후, 시작점 다음부터 기록)
    /// </summary>
    public void RecordBranch7Cell(int droneId, Vector3 worldPos)
    {
        // 7번째 브랜치 진입 전이면 무시
        if (!droneEnteredBranch7.ContainsKey(droneId) || !droneEnteredBranch7[droneId])
            return;
        
        Vector3 cellPos = SnapToGrid(worldPos);
        
        // 시작점은 기록하지 않음
        if (branch7StartPosition.HasValue && cellPos == branch7StartPosition.Value)
            return;
        
        // 이미 방문한 셀이면 무시 (중복 방지, dead end 복귀 시에도 추가 안함)
        if (branch7VisitedCells[droneId].Contains(cellPos))
            return;
        
        // 새 셀 기록
        branch7VisitedCells[droneId].Add(cellPos);
        branch7DronePaths[droneId].Add(cellPos);
        
        // 디버그 출력
        PrintBranch7DronePathDebug(droneId);
    }

    /// <summary>
    /// 특정 드론의 7번째 브랜치 경로 디버그 출력
    /// </summary>
    private void PrintBranch7DronePathDebug(int droneId)
    {
        if (!branch7DronePaths.ContainsKey(droneId)) return;
        
        List<Vector3> path = branch7DronePaths[droneId];
        string coordList = "";
        foreach (var pos in path)
        {
            coordList += GetGridPos(pos) + " -> ";
        }
        if (coordList.Length > 4)
            coordList = coordList.Substring(0, coordList.Length - 4); // 마지막 " -> " 제거
        
        Debug.Log($"<color=magenta>[Branch7]</color> Drone{droneId} path = [{coordList}]");
    }

    /// <summary>
    /// 특정 드론의 7번째 브랜치 경로 반환
    /// </summary>
    public List<Vector3> GetBranch7Path(int droneId)
    {
        if (branch7DronePaths.ContainsKey(droneId))
            return new List<Vector3>(branch7DronePaths[droneId]);
        return new List<Vector3>();
    }

    /// <summary>
    /// 드론이 7번째 브랜치에 진입했는지 확인
    /// </summary>
    public bool HasEnteredBranch7(int droneId)
    {
        return droneEnteredBranch7.ContainsKey(droneId) && droneEnteredBranch7[droneId];
    }

    /// <summary>
    /// 특정 드론의 7번째 브랜치 경로를 finalTrajectory에 추가
    /// </summary>
    public void AppendBranch7PathToTrajectory(int droneId)
    {
        if (!branch7DronePaths.ContainsKey(droneId))
        {
            Debug.LogWarning($"<color=red>[Branch7]</color> Drone{droneId}의 경로가 없습니다.");
            return;
        }
        
        List<Vector3> path = branch7DronePaths[droneId];
        if (path.Count == 0)
        {
            Debug.LogWarning($"<color=red>[Branch7]</color> Drone{droneId}의 경로가 비어있습니다.");
            return;
        }
        
        // finalTrajectory에 추가
        foreach (var cell in path)
        {
            finalTrajectory.Add(cell);
        }
        
        Debug.Log($"<color=magenta>[Branch7]</color> Drone{droneId} 경로({path.Count}개 셀)를 finalTrajectory에 추가함");
        PrintFinalTrajectory();
    }
}
