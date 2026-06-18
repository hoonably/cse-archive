using UnityEngine;
using System.Collections.Generic;

/// <summary>
/// 간소화된 드론 제어 유닛
/// - 3개 드론이 협력하여 맵 탐색
/// - Branch 기반 단순 알고리즘
/// </summary>
public class DroneControlUnit : MonoBehaviour
{
    [Header("Drone Actuators")]
    public int droneInd;
    public Rigidbody rb;
    public List<ThrusterBehave> engine; 
    public List<BrakeBehave> brake;
    public List<ServoBehave> servo;     
    public List<IMU_Behave> IMU;
    public List<GPS_Behave> GPS;
    public List<LIDAR_behave> LIDAR;    // [0]:-Z(Back), [1]:-X(Left), [2]:+Z(Forward), [3]:+X(Right)

    public AccelBehave ab;

    // Constants
    [Header("Map & Hardware Constants")]
    public const float MAP_CUBE_SIZE = 12.0f;
    private const float OPEN_THRESHOLD = 4.9f;  // 벽 판별 임계값
    private const float WAYPOINT_RADIUS = 0.9f;  // 목표 도달 반경
    
    private const float SWIFT_THRUST = 1.0f;
    private const float SWIFT_BRAKE = 0.0f;

    // LIDAR 방향 (절대 좌표)
    private readonly Vector3[] globalLidarDirs = new Vector3[] 
    {
        Vector3.back,     // [0] -Z
        Vector3.left,     // [1] -X
        Vector3.forward,  // [2] +Z
        Vector3.right     // [3] +X
    };

    private readonly float[] globalLidarAngles = new float[]
    {
        180f, 270f, 0f, 90f
    };

    [System.Serializable]
    public enum DronePhase 
    {
        Centering,   // 중앙 정렬
        Standby,     // 3마리 다 모일 때까지 대기
        Move,        // 목표로 이동
        Wait,        // Branch에서 대기
        Idle         // 정지
    }

    [Header("Control State")]
    public DronePhase phase = DronePhase.Centering;
    private bool isWaiting = false;  // Wait 상태 로그 방지용
    
    [Header("Navigation")]
    public Vector3 currentTargetPos;      // 현재 목표 위치
    public Vector3 previousMoveDir;       // 이전 이동 방향 (물리적 진행 방향)
    public Vector3 currentExploringDirection;  // Branch에서 출발한 원래 방향 (MapManager 보고용)
    public Vector3 lastBranchPos;         // 마지막 Branch 위치
    
    private float targetEngineAngle;
    private float targetLidarAngle;
    private bool gyroInitialized = false;
    
    private float startupTime;

    // 속성
    public Vector3 CurrentPosition 
    {
        get 
        {
            if (GPS != null && GPS.Count > 0) return GPS[0].currentPos;
            return transform.position; 
        }
    }

    public Vector3 CurrentVelocity
    {
        get
        {
            if (IMU != null && IMU.Count > 0) return IMU[0].linearVelocity;
            return (rb != null) ? rb.linearVelocity : Vector3.zero;
        }
    }

    void Start()
    {
        if(rb == null) rb = GetComponent<Rigidbody>();
        startupTime = Time.time;

        rb.useGravity = false;
        rb.constraints = RigidbodyConstraints.FreezeRotation;
        
        previousMoveDir = Vector3.zero;
        currentExploringDirection = Vector3.zero;
        lastBranchPos = Vector3.zero;
    }

    void FixedUpdate()
    {
        FreezeRotation();
        PerformGyroLogic();
        
        // 시작 딜레이
        if (Time.time - startupTime < 0.5f) return;
        
        // 매 프레임 현재 위치 기록 (3대 모두 통과한 셀 추적)
        DroneMapManager.Instance.RecordTrajectory(CurrentPosition, droneInd);
        
        // 7번째 브랜치 진입 후 셀 기록 (중복 없이 순차 기록)
        DroneMapManager.Instance.RecordBranch7Cell(droneInd, CurrentPosition);
        
        switch (phase)
        {
            case DronePhase.Centering:
                PerformCentering();
                break;

            case DronePhase.Standby:   // [추가] 대기 상태 로직 연결
                PerformStandby();
                break;
                
            case DronePhase.Move:
                PerformMove();
                PerformPhysicsMovement();  // [추가] 실제 물리 이동 실행
                break;
                
            case DronePhase.Wait:
                PerformWait();
                break;
                
            case DronePhase.Idle:
                PerformIdle();
                break;
        }
    }

    private void FreezeRotation()
    {
        rb.angularVelocity = Vector3.zero;
        transform.rotation = Quaternion.identity;
    }

    private void PerformGyroLogic()
    {
        if (!gyroInitialized)
        {
            if (servo.Count > 0 && servo[0].transform.childCount > 0)
                targetEngineAngle = servo[0].transform.GetChild(0).eulerAngles.y;
            else
                targetEngineAngle = 90f;

            if (servo.Count > 1 && servo[1].transform.childCount > 0)
                targetLidarAngle = servo[1].transform.GetChild(0).eulerAngles.y;
            else
                targetLidarAngle = 0f;

            gyroInitialized = true;
        }

        if (servo.Count > 0)
        {
            float bodyAngle = transform.eulerAngles.y;
            float neededLocalAngle0 = Mathf.DeltaAngle(bodyAngle, targetEngineAngle);
            servo[0].controlVal = Mathf.Repeat(neededLocalAngle0, 360f);
        }

        if (servo.Count > 1)
        {
            float engineAngle = 0f;
            if (servo[0].transform.childCount > 0)
                engineAngle = servo[0].transform.GetChild(0).eulerAngles.y;
            else
                engineAngle = targetEngineAngle;

            float neededLocalAngle1 = Mathf.DeltaAngle(engineAngle, targetLidarAngle);
            servo[1].controlVal = Mathf.Repeat(neededLocalAngle1, 360f);
        }
    }

    // ==================== Phase 로직 ====================

    /// <summary>
    /// Centering: 중앙으로 이동 (물리 버전)
    /// </summary>
    private void PerformCentering()
    {
        Vector3 currentPos = CurrentPosition;
        Vector3 gridCenter = DroneMapManager.Instance.SnapToGrid(currentPos);
        
        Vector3 dirToCenter = gridCenter - currentPos;
        dirToCenter.y = 0f;
        float distToCenter = dirToCenter.magnitude;
        
        // 1. 방향 설정 (P-Control을 위해 targetEngineAngle 업데이트)
        if (distToCenter > 0.1f)
        {
            float requiredAngle = Mathf.Atan2(dirToCenter.x, dirToCenter.z) * Mathf.Rad2Deg;
            targetEngineAngle = requiredAngle - 90f;
        }

        // 2. 물리 이동 로직
        if (distToCenter < 0.5f)
        {
            SetThrust(0f);
            FullBrake();

            // 속도가 충분히 줄었으면 다음 단계로
            if (CurrentVelocity.magnitude < 0.5f)
            {
                currentTargetPos = gridCenter;

                // [수정 전] 바로 출발하던 코드
                // DecideNextDirection(); 

                // [수정 후] 매니저에게 보고하고 대기 모드로 전환
                DroneMapManager.Instance.RegisterDroneReady(droneInd);
                phase = DronePhase.Standby;
            }
        }
        else
        {
            // 이동 중
            SetThrust(SWIFT_THRUST); // 1.0f
            
            // 중앙으로 갈 때는 직진 안정성을 위해 좌우 브레이크 펴고, 앞뒤는 접음
            // (ApplyAerodynamicBrakes의 3번째 인자가 앞뒤 브레이크)
            ApplyAerodynamicBrakes(1.0f, 1.0f, 0f); 

            // [삭제됨] Lateral velocity kill (벡터 투영 치팅 코드 삭제)
            
            // Centering 상태에서도 서보를 돌려야 하므로 P-Control 직접 호출
            if (servo.Count > 0)
            {
                float currentYaw = servo[0].controlVal;
                float angleError = Mathf.DeltaAngle(currentYaw, targetEngineAngle);
                servo[0].controlVal = currentYaw + (angleError * 3.0f * Time.fixedDeltaTime * 10f);
            }
        }
    }

    /// <summary>
    /// [추가] 모든 드론이 준비될 때까지 제자리 대기
    /// </summary>
    private void PerformStandby()
    {
        // 1. 움직이지 않게 꽉 잡고 있기
        SetThrust(0f);
        FullBrake();
        
        // 서보 모터(방향)는 정면(Trunk 방향 등)을 바라보게 두거나 현재 상태 유지
        // (필요하다면 여기서 targetEngineAngle을 시작 방향으로 미리 돌려놔도 됨)

        // 2. 매니저에게 "다 준비됐나요?" 물어보기
        if (DroneMapManager.Instance.IsAllReady)
        {
            // 3. 다 준비됐으면 출발!
            Debug.Log($"[Drone{droneInd}] All Systems Go! Starting Mission.");
            DecideNextDirection(); // 이때 phase가 Move로 바뀝니다.
        }
    }

    /// <summary>
    /// Move: 목표로 이동 (물리 엔진 버전)
    /// </summary>
    private void PerformMove()
    {
        // [삭제됨] SetThrust, SetBrakes 직접 호출 부분 삭제 (PerformPhysicsMovement가 담당)
        // [삭제됨] rb.linearVelocity = ... 강제 속도 제어 삭제

        Vector3 dirToTarget = currentTargetPos - CurrentPosition;
        dirToTarget.y = 0f;
        float distance = dirToTarget.magnitude;

        // 1. 목표 각도(targetEngineAngle) 지속 업데이트
        if (dirToTarget.sqrMagnitude > 0.001f)
        {
            float requiredAngle = Mathf.Atan2(dirToTarget.x, dirToTarget.z) * Mathf.Rad2Deg;
            targetEngineAngle = requiredAngle - 90f; // 서보 기준 각도 보정
        }

        // 2. Dead-end 감지 로직 (기존 유지)
        int forwardLidarIdx = GetLidarIndexFromDir(previousMoveDir);
        if (forwardLidarIdx != -1 && LIDAR.Count > forwardLidarIdx)
        {
            float frontDist = LIDAR[forwardLidarIdx].GetDistance(globalLidarDirs[forwardLidarIdx]);
            
            if (frontDist < OPEN_THRESHOLD)
            {
                List<Vector3> openDirs = new List<Vector3>();
                for (int i = 0; i < LIDAR.Count && i < globalLidarDirs.Length; i++)
                {
                    if (i == forwardLidarIdx) continue;
                    Vector3 cameFrom = -previousMoveDir;
                    if (Vector3.Dot(globalLidarDirs[i], cameFrom) > 0.9f) continue;
                    
                    float dist = LIDAR[i].GetDistance(globalLidarDirs[i]);
                    if (dist > OPEN_THRESHOLD) openDirs.Add(globalLidarDirs[i]);
                }
                
                if (openDirs.Count == 0)
                {
                    HandleDeadEnd();
                    return;
                }
                else if (openDirs.Count == 1) // 코너
                {
                    // 코너에서는 속도를 죽이지 않고 자연스럽게 목표만 바꿈
                    Vector3 newDir = openDirs[0];
                    previousMoveDir = newDir;
                    Vector3 currentPos = DroneMapManager.Instance.SnapToGrid(CurrentPosition);
                    currentTargetPos = currentPos + newDir * MAP_CUBE_SIZE;
                    
                    float angle = Mathf.Atan2(newDir.x, newDir.z) * Mathf.Rad2Deg;
                    targetEngineAngle = angle - 90f;
                    return;
                }
                else // Branch 발견
                {
                    // Branch에서는 정확한 판단을 위해 감속이 필요할 수 있으나, 일단 진행
                    Vector3 currentPos = DroneMapManager.Instance.SnapToGrid(CurrentPosition);
                    currentTargetPos = currentPos;
                    DecideNextDirection();
                    return;
                }
            }
        }

        // 3. 목표 도달 확인 + 속도 정렬
        if (distance < WAYPOINT_RADIUS)
        {
            Vector3 arrivedPos = DroneMapManager.Instance.SnapToGrid(CurrentPosition);
            currentTargetPos = arrivedPos;
            
            // ⭐ DecideNextDirection 전에 미리 다음 방향 예측하여 속도 정렬
            // (DecideNextDirection이 previousMoveDir 기반으로 결정하므로,
            //  현재는 이미 방향이 결정된 후에 호출됨)
            DecideNextDirection();
            
            // DecideNextDirection 후 currentTargetPos가 업데이트되었으면
            // 즉시 각도 정렬
            Vector3 dirToNext = currentTargetPos - arrivedPos;
            dirToNext.y = 0f;
            if (dirToNext.magnitude > 0.1f)
            {
                float nextAngle = Mathf.Atan2(dirToNext.x, dirToNext.z) * Mathf.Rad2Deg;
                targetEngineAngle = nextAngle - 90f;
            }
        }
    }

    /// <summary>
    /// Wait: Branch에서 대기 (Station Keeping)
    /// </summary>
    private void PerformWait()
    {
        // 1. Station Keeping (위치 사수)
        Vector3 currentPos = CurrentPosition;
        Vector3 branchCenter = DroneMapManager.Instance.SnapToGrid(currentPos);
        float distToCenter = Vector3.Distance(currentPos, branchCenter);

        // 허용 반경 (1.2m 정도면 적당)
        if (distToCenter > 1.2f) 
        {
            // 중심에서 밀려남 -> 복귀 추진
            Vector3 dirToCenter = branchCenter - currentPos;
            float requiredAngle = Mathf.Atan2(dirToCenter.x, dirToCenter.z) * Mathf.Rad2Deg;
            targetEngineAngle = requiredAngle - 90f;

            SetThrust(0.5f); // 살살 복귀
            // 복귀 중에는 앞뒤 브레이크 끔(0f)
            ApplyAerodynamicBrakes(1.0f, 1.0f, 0f); 
        }
        else
        {
            // 중심 도착 -> "풀 브레이크" (닻 내림)
            SetThrust(0f);
            FullBrake(); // 앞뒤좌우 모든 브레이크 전개!
        }

        // 2. 서보 모터 P-Control (방향 유지)
        if (servo.Count > 0)
        {
            float currentYaw = servo[0].controlVal;
            float angleError = Mathf.DeltaAngle(currentYaw, targetEngineAngle);
            servo[0].controlVal = currentYaw + (angleError * 2.0f * Time.fixedDeltaTime * 10f);
        }

        // 주기적으로 MapManager 확인
        Vector3 currentBranchPos = DroneMapManager.Instance.SnapToGrid(CurrentPosition);
        DroneMapManager.BranchInfo branch = DroneMapManager.Instance.GetOrCreateBranch(currentBranchPos);
        
        // 1순위: Trunk 확인
        foreach (var kvp in branch.directionStates)
        {
            if (kvp.Value == DroneMapManager.DirectionState.Trunk)
            {
                Vector3 chosenDir = kvp.Key;
                
                // LIDAR로 실제 열림 확인
                int lidarIdx = GetLidarIndexFromDir(chosenDir);
                if (lidarIdx == -1 || LIDAR.Count <= lidarIdx)
                    continue;
                
                float dist = LIDAR[lidarIdx].GetDistance(globalLidarDirs[lidarIdx]);
                if (dist <= OPEN_THRESHOLD)
                {
                    // Debug.LogWarning($"<color=red>[Drone{droneInd}]</color> Wait: {GetDirName(chosenDir)} marked as Trunk but BLOCKED");
                    continue;
                }
                
                currentExploringDirection = Vector3.zero;
                SetNextTarget(chosenDir);
                phase = DronePhase.Move;
                // Debug.Log($"<color=cyan>[Drone{droneInd}]</color> Wait -> Move (Trunk found: {GetDirName(chosenDir)})");
                return;
            }
        }
        
        // 2순위: Unknown 확인 (DeadEnd로 모두 막혔지만 Unknown 남은 경우)
        foreach (var kvp in branch.directionStates)
        {
            if (kvp.Value == DroneMapManager.DirectionState.Unknown)
            {
                // Unknown이 남아있으면 DecideNextDirection 재실행
                DecideNextDirection();
                // Debug.Log($"<color=cyan>[Drone{droneInd}]</color> Wait -> Explore (Unknown found after DeadEnd)");
                return;
            }
        }
    }

    /// <summary>
    /// Idle: 완전 정지
    /// </summary>
    private void PerformIdle()
    {
        SetThrust(0f);
        FullBrake(); // 모든 브레이크 전개하여 물리적 정지
        
        // 서보 유지
        if (servo.Count > 0)
        {
            float currentYaw = servo[0].controlVal;
            float angleError = Mathf.DeltaAngle(currentYaw, targetEngineAngle);
            servo[0].controlVal = currentYaw + (angleError * 2.0f * Time.fixedDeltaTime * 10f);
        }
    }

    // ==================== 핵심 의사결정 로직 ====================

    /// <summary>
    /// 다음 이동 방향 결정 (Branch 도착 시 통합 우선순위 로직)
    /// </summary>
    private void DecideNextDirection()
    {
        Vector3 currentPos = DroneMapManager.Instance.SnapToGrid(CurrentPosition);
        
        // Branch 판정
        if (!IsBranch(out int availableDirs))
        {
            // Branch가 아님 - 직진
            if (previousMoveDir == Vector3.zero)
            {
                // 최초 시작 - 열린 방향 찾기
                FindInitialDirection();
            }
            else
            {
                // 직진 계속
                SetNextTarget(previousMoveDir);
                phase = DronePhase.Move;
            }
            return;
        }
        
        // Branch 도착
        DroneMapManager.BranchInfo branch = DroneMapManager.Instance.GetOrCreateBranch(currentPos);
        
        // 7번째 브랜치 진입 등록 (branches.Count == 7일 때만 활성화)
        if (DroneMapManager.Instance.BranchCount == 7)
        {
            DroneMapManager.Instance.RegisterBranch7Entry(droneInd, currentPos);
        }
        
        // 드론 도착 등록 (1~3등만)
        branch.RegisterDroneArrival(droneInd);
        
        // 새 Branch 발견 보고 (이전 Branch와 다른 위치일 때만)
        if (lastBranchPos != Vector3.zero && Vector3.Distance(currentPos, lastBranchPos) > 0.1f)
        {
            if (currentExploringDirection != Vector3.zero)
            {
                DroneMapManager.Instance.ReportNewBranchFound(lastBranchPos, currentExploringDirection, droneInd);
                // Debug.Log($"<color=cyan>[Drone{droneInd}]</color> Reported Trunk: Branch={lastBranchPos}, Direction={GetDirName(currentExploringDirection)}");
            }
        }
        
        lastBranchPos = currentPos;
        Vector3 cameFrom = -previousMoveDir;
        
        // 온 방향을 CameFrom으로 마킹 (단, DeadEnd/Trunk는 보존)
        if (cameFrom != Vector3.zero)
        {
            DroneMapManager.DirectionState currentState = branch.directionStates.ContainsKey(cameFrom) 
                ? branch.directionStates[cameFrom] 
                : DroneMapManager.DirectionState.Unknown;
                
            // DeadEnd나 Trunk가 아닌 경우만 CameFrom으로 마킹
            if (currentState != DroneMapManager.DirectionState.DeadEnd && 
                currentState != DroneMapManager.DirectionState.Trunk)
            {
                DroneMapManager.Instance.SetDirectionState(currentPos, cameFrom, DroneMapManager.DirectionState.CameFrom);
            }
        }
        
        // 0단계: 필터링 (CameFrom & DeadEnd & Exploring1/2/3 제외)
        List<Vector3> availableDirections = new List<Vector3>();
        foreach (var kvp in branch.directionStates)
        {
            Vector3 dir = kvp.Key;
            DroneMapManager.DirectionState state = kvp.Value;
            
            // CameFrom 제외 (절대 재진입 불가)
            if (state == DroneMapManager.DirectionState.CameFrom)
                continue;
            
            // DeadEnd 제외
            if (state == DroneMapManager.DirectionState.DeadEnd)
                continue;
            
            // 다른 드론이 Exploring 중인 방향 제외
            if (state == DroneMapManager.DirectionState.Exploring1 ||
                state == DroneMapManager.DirectionState.Exploring2 ||
                state == DroneMapManager.DirectionState.Exploring3)
                continue;
            
            // LIDAR로 실제 열림 확인 (Unknown, Trunk 모두)
            int lidarIdx = GetLidarIndexFromDir(dir);
            if (lidarIdx != -1 && LIDAR.Count > lidarIdx)
            {
                float dist = LIDAR[lidarIdx].GetDistance(globalLidarDirs[lidarIdx]);
                if (dist > OPEN_THRESHOLD)
                {
                    availableDirections.Add(dir);
                }
            }
        }
        
        // 1단계: Unknown 탐색
        List<Vector3> unknownDirs = new List<Vector3>();
        foreach (Vector3 dir in availableDirections)
        {
            if (branch.directionStates[dir] == DroneMapManager.DirectionState.Unknown)
            {
                unknownDirs.Add(dir);
            }
        }
        
        if (unknownDirs.Count > 0)
        {
            // Unknown 선택 (우선순위: 왼쪽 → 위쪽 → 오른쪽 → 아래쪽)
            Vector3 chosen = ChooseByPriority(unknownDirs, previousMoveDir);
            
            // 드론별 Exploring 상태 설정
            DroneMapManager.DirectionState exploringState = DroneMapManager.DirectionState.Exploring1;
            if (droneInd == 1) exploringState = DroneMapManager.DirectionState.Exploring2;
            else if (droneInd == 2) exploringState = DroneMapManager.DirectionState.Exploring3;
            
            DroneMapManager.Instance.SetDirectionState(currentPos, chosen, exploringState);
            currentExploringDirection = chosen;  // 출발 방향 기록!
            SetNextTarget(chosen);
            phase = DronePhase.Move;
            isWaiting = false;
            Debug.Log(FormatLog(currentPos, $"{GetGridPos(currentPos)} → 탐색: {GetDirName(chosen)}"));
            return;
        }
        
        // 2단계: Trunk 합류
        foreach (Vector3 dir in availableDirections)
        {
            if (branch.directionStates[dir] == DroneMapManager.DirectionState.Trunk)
            {
                currentExploringDirection = Vector3.zero;  // Trunk 따라가는 중 (탐색 아님)
                SetNextTarget(dir);
                phase = DronePhase.Move;
                isWaiting = false;
                Debug.Log(FormatLog(currentPos, $"{GetGridPos(currentPos)} → Trunk 합류: {GetDirName(dir)}"));
                return;
            }
        }
        
        // 3단계: Wait
        phase = DronePhase.Wait;

        if (!isWaiting)
        {
            isWaiting = true;
            Debug.Log(FormatLog(currentPos, $"{GetGridPos(currentPos)} → 대기 (Unknown/Trunk 없음)"));
        }
    }

    /// <summary>
    /// Dead-end 처리
    /// </summary>
    private void HandleDeadEnd()
    {
        Vector3 currentPos = DroneMapManager.Instance.SnapToGrid(CurrentPosition);
        Debug.Log(FormatLog(lastBranchPos, $"{GetGridPos(currentPos)} Dead-end 발견: {GetDirName(currentExploringDirection)}"));
        
        // MapManager에 DeadEnd 보고
        if (lastBranchPos != Vector3.zero && currentExploringDirection != Vector3.zero)
        {
            DroneMapManager.Instance.ReportDeadEnd(lastBranchPos, currentExploringDirection, droneInd);
        }
        
        // ⭐ Branch7 진입 후 Dead-end 발견 시 완전 정지
        if (DroneMapManager.Instance.HasEnteredBranch7(droneInd))
        {
            Debug.Log($"<color=red>[Drone{droneInd}]</color> Branch7 이후 Dead-end 발견 → 완전 정지!");
            phase = DronePhase.Standby;  // 대기 상태로 전환
            rb.linearVelocity = Vector3.zero;
            return;
        }
        
        // 유턴하여 Branch로 복귀
        // [삭제됨] rb.linearVelocity = Vector3.zero;  <-- 삭제!
        // PerformPhysicsMovement가 각도 차이를 감지하고 알아서 FullBrake를 잡습니다.

        Vector3 reverseDir = -previousMoveDir;
        SetNextTarget(reverseDir);
        
        currentExploringDirection = Vector3.zero;
        phase = DronePhase.Move;
    }

    /// <summary>
    /// Branch 판정
    /// </summary>
    private bool IsBranch(out int availableCount)
    {
        availableCount = 0;
        Vector3 cameFrom = -previousMoveDir;
        
        for (int i = 0; i < LIDAR.Count && i < globalLidarDirs.Length; i++)
        {
            float dist = LIDAR[i].GetDistance(globalLidarDirs[i]);
            
            if (dist > OPEN_THRESHOLD)
            {
                // 온 방향 제외
                if (previousMoveDir != Vector3.zero && Vector3.Dot(globalLidarDirs[i], cameFrom) > 0.9f)
                    continue;
                
                availableCount++;
            }
        }
        
        // Branch 조건: 온 방향 제외 2개 이상 방향
        return availableCount >= 2;
    }

    /// <summary>
    /// 최초 시작 시 열린 방향 찾기
    /// </summary>
    private void FindInitialDirection()
    {
        for (int i = 0; i < LIDAR.Count && i < globalLidarDirs.Length; i++)
        {
            float dist = LIDAR[i].GetDistance(globalLidarDirs[i]);
            
            if (dist > OPEN_THRESHOLD)
            {
                Vector3 dir = globalLidarDirs[i];
                SetNextTarget(dir);
                phase = DronePhase.Move;
                // Debug.Log($"<color=green>[Drone{droneInd}]</color> Initial direction: {GetDirName(dir)}");
                return;
            }
        }
        
        // 모든 방향이 막혀있음
        phase = DronePhase.Idle;
    }

    /// <summary>
    /// Global 절대좌표 기준 우선순위: Left(-X) -> Right(+X) -> Forward(+Z) -> Back(-Z)
    /// </summary>
    private Vector3 ChooseByPriority(List<Vector3> candidates, Vector3 prevDir)
    {
        // 절대 좌표 기준 우선순위
        Vector3[] priority = new Vector3[]
        {
            Vector3.left,     // -X (1순위)
            Vector3.right,    // +X (2순위)
            Vector3.forward,  // +Z (3순위)
            Vector3.back      // -Z (4순위)
        };
        
        foreach (Vector3 priorDir in priority)
        {
            foreach (Vector3 candidate in candidates)
            {
                // 절대 좌표 비교 (0.9 임계값)
                if (Vector3.Dot(candidate, priorDir) > 0.9f)
                {
                    return candidate;
                }
            }
        }
        
        // 매칭 실패 시 첫 번째 반환
        return candidates[0];
    }

    /// <summary>
    /// 다음 목표 설정
    /// </summary>
    private void SetNextTarget(Vector3 direction)
    {
        Vector3 currentPos = DroneMapManager.Instance.SnapToGrid(CurrentPosition);
        currentTargetPos = currentPos + direction * MAP_CUBE_SIZE;
                
        // [삭제됨] 방향 전환 시 관성 제거 코드 삭제
        // if (direction != previousMoveDir) { rb.linearVelocity = Vector3.zero; } <-- 삭제!
        // 이제 물리 엔진의 관성과 브레이크로 자연스럽게 회전합니다.
        
        previousMoveDir = direction;
        
        // 엔진 각도 설정
        float angle = Mathf.Atan2(direction.x, direction.z) * Mathf.Rad2Deg;
        targetEngineAngle = angle - 90f;
    }

    // ==================== 유틸리티 ====================

    private int GetLidarIndexFromDir(Vector3 dir)
    {
        int bestIdx = -1;
        float maxDot = -2f;
        for(int i=0; i<globalLidarDirs.Length; i++)
        {
            float dot = Vector3.Dot(globalLidarDirs[i], dir);
            if (dot > maxDot)
            {
                maxDot = dot;
                bestIdx = i;
            }
        }
        return (maxDot > 0.9f) ? bestIdx : -1;
    }

    private string GetDirName(Vector3 dir)
    {
        if (dir == Vector3.back) return "Back(-Z)";
        if (dir == Vector3.left) return "Left(-X)";
        if (dir == Vector3.forward) return "Forward(+Z)";
        if (dir == Vector3.right) return "Right(+X)";
        return dir.ToString();
    }
    
    /// <summary>
    /// 좌표를 그리드 인덱스로 변환 (출발점 = (10, 10))
    /// </summary>
    private string GetGridPos(Vector3 worldPos)
    {
        int gridX = Mathf.RoundToInt(worldPos.x / MAP_CUBE_SIZE) + 10;
        int gridZ = Mathf.RoundToInt(worldPos.z / MAP_CUBE_SIZE) + 10;
        return $"({gridX},{gridZ})";
    }
    
    /// <summary>
    /// Branch 색상 (0~6번)
    /// </summary>
    private string GetBranchColor(int branchId)
    {
        string[] colors = new string[] { "cyan", "yellow", "magenta", "green", "orange", "white", "gray" };
        return colors[Mathf.Clamp(branchId, 0, 6)];
    }
    
    /// <summary>
    /// Drone 색상 (0~2번)
    /// </summary>
    private string GetDroneColor(int droneId)
    {
        string[] colors = new string[] { "lime", "aqua", "magenta" };
        return colors[Mathf.Clamp(droneId, 0, 2)];
    }
    
    /// <summary>
    /// 포맷팅된 로그 문자열 생성
    /// </summary>
    private string FormatLog(Vector3 branchPos, string message)
    {
        DroneMapManager.BranchInfo branch = DroneMapManager.Instance.GetOrCreateBranch(branchPos);
        string branchColor = GetBranchColor(branch.branchId);
        string droneColor = GetDroneColor(droneInd);
        return $"<color={branchColor}>[{branch.branchId} branch]</color> <color={droneColor}>[Drone{droneInd}]</color> {message}";
    }

    private void SetThrust(float val)
    {
        if (engine.Count > 0) engine[0].controlVal = val;
    }

    private void SetBrakes(float val)
    {
        foreach(var b in brake) b.controlVal = val;
    }

    // ==================== 충돌 처리 ====================

    private void OnCollisionEnter(Collision collision)
    {
        // 충돌 처리
    }

    public void OnTriggerEnter(Collider other)
    {
        if (other.GetComponent<AccelBehave>())
        {
            ab = other.GetComponent<AccelBehave>();
        }
    }

    //! ==================== [새로 추가] 물리 제어 로직 ====================

    /// <summary>
    /// 브레이크 통합 제어
    /// - leftVal/rightVal: 좌우 코너링용 (0~1)
    /// - frontBackVal: 전후 제동용 (0~1) -> 정지할 때만 사용
    /// </summary>
    private void ApplyAerodynamicBrakes(float leftVal, float rightVal, float frontBackVal)
    {
        // 1. 좌우 브레이크 (0,2: Left / 1,3: Right) - 인덱스 체크 포함
        if (brake.Count > 0) brake[0].controlVal = leftVal; 
        if (brake.Count > 1) brake[1].controlVal = rightVal;
        if (brake.Count > 2) brake[2].controlVal = leftVal; 
        if (brake.Count > 3) brake[3].controlVal = rightVal; 

        // 2. 앞뒤 브레이크 (4,5번 인덱스로 가정)
        // 전진/후진 할 때는 접고(0), 멈출 때만 폅니다(1).
        if (brake.Count > 4) brake[4].controlVal = frontBackVal;
        if (brake.Count > 5) brake[5].controlVal = frontBackVal;
        if (brake.Count > 6) brake[6].controlVal = frontBackVal;
    }

    /// <summary>
    /// 급정거용: 모든 브레이크 풀가동 (앞뒤좌우 100%)
    /// </summary>
    private void FullBrake()
    {
        ApplyAerodynamicBrakes(1.0f, 1.0f, 1.0f);
    }

    // P-Control + Differential Braking + IMU 기반 측면 속도 보정
    private void PerformPhysicsMovement()
    {
        // 1. 목표 각도 오차 계산
        float currentYaw = (servo.Count > 0) ? servo[0].controlVal : 0f;
        float angleError = Mathf.DeltaAngle(currentYaw, targetEngineAngle);

        // 2. 서보 모터 P-Control
        float Kp = 3.0f; 
        float servoOutput = currentYaw + (angleError * Kp * Time.fixedDeltaTime * 10f);
        if (servo.Count > 0) servo[0].controlVal = servoOutput;

        // 3. IMU 기반 측면 속도 보정 (외력 대응)
        float lateralDragBoost = 0f;
        if (IMU != null && IMU.Count > 0)
        {
            Vector3 localVel = transform.InverseTransformDirection(IMU[0].linearVelocity);
            Vector3 localAccel = transform.InverseTransformDirection(IMU[0].accel);
            
            // 측면 속도(x축) + 측면 가속도 감지
            float lateralVel = localVel.x;
            float lateralAccel = localAccel.x;
            float lateralDrift = Mathf.Abs(lateralVel) + Mathf.Abs(lateralAccel) * 0.3f;
            
            // 측면 속도가 클수록 좌우 브레이크 강화 (최대 +0.5)
            lateralDragBoost = Mathf.Clamp(lateralDrift * 0.4f, 0f, 0.5f);
        }

        // 4. 스로틀 & 브레이크 제어
        float absError = Mathf.Abs(angleError);
        bool is180Turn = absError > 120f;

        // [설정] 주행 중 좌우 기본 저항 (안정성 확보) + 측면 속도 보정
        float defaultDrag = 1.0f; 

        if (is180Turn)
        {
            // [상황 A: 180도 유턴]
            if (absError > 10f) 
            {
                SetThrust(0f);
                FullBrake(); // 모든 브레이크 펴서 제자리 회전
            }
            else 
            {
                SetThrust(1.0f); 
                // 출발: 좌우는 안정성 위해 펴고, 앞뒤는 속도 위해 접음(0f)
                ApplyAerodynamicBrakes(defaultDrag, defaultDrag, 0f); 
            }
        }
        else
        {
            // [상황 B: 직진 및 코너링]
            float baseThrust = 1.0f;
            float leftBrake = defaultDrag;
            float rightBrake = defaultDrag;
            float frontBackBrake = 0f; // 달릴 때는 앞뒤 브레이크 해제

            if (absError > 5f) // 코너링 중
            {
                baseThrust = 0.8f; 
                
                // 코너링 시 오버슈팅 방지를 위해 앞뒤 브레이크를 살짝 쓸 수도 있음 (선택사항)
                // frontBackBrake = 0.2f; 

                if (angleError > 0) 
                {
                    // 우회전: 오른쪽 꽉 잡기
                    rightBrake = 1.0f; 
                    leftBrake = defaultDrag; 
                }
                else 
                {
                    // 좌회전: 왼쪽 꽉 잡기
                    leftBrake = 1.0f;
                    rightBrake = defaultDrag;
                }
            }
            
            SetThrust(baseThrust);
            ApplyAerodynamicBrakes(leftBrake, rightBrake, frontBackBrake);
        }
    }
}
