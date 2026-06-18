using UnityEngine;
using UnityEngine.InputSystem;
using System.Collections;
using System.Collections.Generic;
using TMPro;

public class path
{
    public List<GameObject> checkpoints;
}

public enum ControlMode
{
    Manual,
    Auto
}

public class ControlUnit : MonoBehaviour
{
    // ===================== ARDUINO INPUT =====================
    [Header("Raw ADC (0..1023)")]
    public ushort A0;
    public ushort A1;
    public ushort A2;
    public ushort A3;
    public ushort A4;
    public ushort A5;

    [Header("Buttons (pressed = true)")]
    public bool D2;
    public bool D3;
    public bool D4;
    public bool D5;
    public bool D6;

    // ===================== INPUT =====================
    // Keyboard removed - Arduino only

    // ===================== MODE =====================
    [Header("Control Mode")]
    public ControlMode currentMode = ControlMode.Auto;  // 시작은 Auto
    
    private ControlMode previousMode;
    
    [Header("Manual Control Settings")]
    public float manualThrustPower = 0.5f;
    public float manualRotationSpeed = 90f;

    [Header("Throttle State")]
    public float currentThrottle = 0f;
    public float throttleChangeSpeed = 0.8f;
    
    // ===================== AUTO MODE STATE =====================
    [Header("Auto Mode Navigation")]
    public Vector3 autoTargetPos;
    private const float MAP_CUBE_SIZE = 12.0f;
    private const float AUTO_ARRIVAL_THRESHOLD = 4.5f;  // ⭐ 1.8f → 4.5f (빙글빙글 방지)
    private bool autoModeInitialized = false;
    private float autoStartTime = 0f;  // 자동 모드 시작 시간
    private const float ALIGNMENT_DURATION = 2.0f;  // 초기 정렬 시간 (2초)

    // ===================== ACTUATORS =====================
    [Header("Robot Actuators")]
    public Rigidbody rb;
    public List<ThrusterBehave> engine;
    public List<BrakeBehave> brake;
    public List<ServoBehave> servo;
    public List<IMU_Behave> IMU;
    public List<GPS_Behave> GPS;
    public List<LIDAR_behave> LIDAR;
    public List<DroneSilo_behave> Silo;
    public CameraBehave cb;
    public AccelBehave ab;
    public FogOfWarPersistent2 fog2; // FOW 컴포넌트
    public TMP_Text UI_text;
    public List<path> pathList;

    // ===================== SERVO TARGET =====================
    [Header("Servo Targets (Global Degrees)")]
    public float targetEngineAngle;  // Auto 모드 전용
    private float manualTargetAngle; // Manual 모드 전용
    
    [Header("Servo Rotation Settings")]
    public float servoRotationSpeed = 180f;
    
    // ===================== GYRO =====================
    private bool gyroInitialized = false;
    
    // ===================== ENGINE CONTROL =====================
    private bool prevD2 = false;
    // dronesSpawned 플래그는 이제 루틴의 단일 실행 여부를 결정합니다.
    private bool dronesSpawned = false;
    // 드론 출발 대기: 3대 모두 준비 완료 시 점화
    private bool dronesAllReady = false;
    
    // ===================== DEBUG =====================
    private float debugTimer = 0f;
    private const float debugInterval = 1f;

    // ===================== PATH =====================
    public GameObject pathpoint;
    public Transform Map;
    private const int pathpointCount = 100;
    private List<GameObject> pathpointList = new();
    private List<GameObject> activePathPoints = new();

    // ===================== SINGLETON =====================
    private static ControlUnit instance;

    public static int GetTotalActiveDroneCount()
    {
        if (instance == null || instance.Silo == null) return 0;

        int count = 0;
        foreach (var silo in instance.Silo)
        {
            if (silo == null) continue;
            foreach (var d in silo.droneList)
                if (d != null && d.activeSelf) count++;
        }
        return count;
    }

    // ===================== UNITY =====================
    void Awake()
    {
        instance = this;
    }

    void Start()
    {
        rb.useGravity = false;
        rb.constraints = RigidbodyConstraints.FreezeRotation;

        // Path points
        for (int i = 0; i < pathpointCount; i++)
        {
            GameObject p = Instantiate(pathpoint, Map);
            p.SetActive(false);
            pathpointList.Add(p);
        }
        
        // ⭐ 모드 강제 설정 (Inspector 값 무시)
        currentMode = ControlMode.Auto;
        previousMode = currentMode;
        
        // Auto 모드 초기 위치 설정
        if (GPS != null && GPS.Count > 0)
        {
            Vector3 startPos = GPS[0].currentPos;
            autoTargetPos = SnapToGrid(startPos);
        }
        
        Debug.Log($"<color=white>[ControlUnit]</color> 초기화 완료. 현재 모드: {currentMode}"); 

        // 배치 루틴이 단 한 번 실행되도록 Start에서 호출 (딜레이 포함)
        StartCoroutine(StartDeploymentAfterDelay(0.1f)); 
    }

    void FixedUpdate()
    {
        // 드론 출발 대기: 3대 모두 준비될 때까지 엔진 OFF
        if (!dronesAllReady)
        {
            if (DroneMapManager.Instance != null && DroneMapManager.Instance.IsAllReady)
            {
                dronesAllReady = true;
                Debug.Log($"<color=red>[★ IGNITION ★]</color> 3대 드론 모두 출발 - ControlUnit 엔진 점화!");
            }
            else
            {
                // 드론 출발 전: 엔진 OFF, 브레이크 ON
                SetThrust(0f);
                FullBrake();
                return;
            }
        }
        
        // 모드 전환 감지 및 로그
        if (currentMode != previousMode)
        {
            Debug.Log($"<color=yellow>[Mode Change]</color> {previousMode} -> {currentMode} 전환됨.");
            previousMode = currentMode;
        }
        
        // 수동 모드에서 조이스틱 입력 처리
        if (currentMode == ControlMode.Manual)
        {
            HandleJoystickInput();
        }

        // 자이로 로직 (외력 상쇄) - Servo 회전 로직이 여기 포함됨
        PerformGyroLogic();

        // Servo 직접 제어
        ControlServoDirectly();

        if (currentMode == ControlMode.Auto)
        {
            HandleAutoControl();
            FreezeRotation();
        }
        else if (currentMode == ControlMode.Manual)
        {
            HandleManualControl();
        }
        
        // 디버그: 1초마다 IMU와 보정값 출력
        DebugIMUValues();
        
        // 상태 디버깅 (1초마다)
        DebugStateLog(); 
    }

    // D4/D3/D2 버튼 이전 상태 (엣지 감지용)
    private bool prevD4 = false;
    private bool prevD3 = false;
    private bool prevD2_branch = false;

    void Update()
    {
        // D4 버튼: Drone0의 Branch7 경로를 finalTrajectory에 추가
        if (D4 && !prevD4)
        {
            DroneMapManager.Instance.AppendBranch7PathToTrajectory(0);
            Debug.Log("<color=magenta>[ControlUnit]</color> D4 버튼: Drone0 경로 추가");
        }
        prevD4 = D4;
        
        // D3 버튼: Drone1의 Branch7 경로를 finalTrajectory에 추가
        if (D3 && !prevD3)
        {
            DroneMapManager.Instance.AppendBranch7PathToTrajectory(1);
            Debug.Log("<color=magenta>[ControlUnit]</color> D3 버튼: Drone1 경로 추가");
        }
        prevD3 = D3;
        
        // D2 버튼: Drone2의 Branch7 경로를 finalTrajectory에 추가
        if (D2 && !prevD2_branch)
        {
            DroneMapManager.Instance.AppendBranch7PathToTrajectory(2);
            Debug.Log("<color=magenta>[ControlUnit]</color> D2 버튼: Drone2 경로 추가");
        }
        prevD2_branch = D2;
    }
    
    private IEnumerator StartDeploymentAfterDelay(float delay)
    {
        yield return new WaitForSeconds(delay); 
        
        if (!dronesSpawned)
        {
             Debug.Log($"<color=red>[FORCE START]</color> {delay:F1}초 대기 후 순차적 드론 배치 루틴 강제 실행 시작.");
             // SequentialDeploymentRoutine이 완료되면 dronesSpawned는 자동으로 true가 됩니다.
             StartCoroutine(SequentialDeploymentRoutine());
        }
    }


    // ===================== JOYSTICK INPUT =====================
    private void HandleJoystickInput()
    {
        if (servo == null || servo.Count == 0) return;
        
        // 1. ADC 값 (0~1023)을 -1 ~ +1로 정규화
        float x = (A0 - 512f) / 512f;
        float y = (A1 - 512f) / 512f;
        
        // 2. 데드존 처리 (±0.1 범위 = 10% 데드존)
        x = Mathf.Abs(x) < 0.1f ? 0f : x;
        y = Mathf.Abs(y) < 0.1f ? 0f : y;
        
        // 3. 조이스틱 입력 여부 확인
        bool hasJoystickInput = (Mathf.Abs(x) > 0.01f || Mathf.Abs(y) > 0.01f);
        
        if (hasJoystickInput)
        {
            // 수동 입력: 조이스틱 방향으로 제어
            float ang = Mathf.Atan2(y, x) * Mathf.Rad2Deg;  // -180..180
            manualTargetAngle = ang;
        }
        // 조이스틱 중립 시에는 manualTargetAngle 유지
    }

    // ===================== GYRO LOGIC (Manual 전용) =====================
    private void PerformGyroLogic()
    {
        // Auto 모드에서는 실행하지 않음
        if (currentMode != ControlMode.Manual) return;
        if (servo == null || servo.Count == 0) return;
        
        // 초기화
        if (!gyroInitialized)
        {
            if (servo.Count > 0 && servo[0].transform.childCount > 0)
                manualTargetAngle = servo[0].transform.GetChild(0).eulerAngles.y;
            else
                manualTargetAngle = 90f;

            gyroInitialized = true;
        }

        // Manual 모드 Servo 제어
        if (servo.Count > 0)
        {
            float bodyAngle = transform.eulerAngles.y;
            float neededLocalAngle0 = Mathf.DeltaAngle(bodyAngle, manualTargetAngle);
            
            if (IMU != null && IMU.Count > 0)
            {
                Vector3 localAngularVel = transform.InverseTransformDirection(IMU[0].angularVelocity);
                float yawRate = localAngularVel.y * Mathf.Rad2Deg;
                float angularCompensation = -yawRate * Time.fixedDeltaTime * 10f;
                neededLocalAngle0 += angularCompensation;
            }
            
            // Servo[0] (모선 추진 방향) 제어
            servo[0].controlVal = Mathf.Repeat(neededLocalAngle0, 360f);
        }
    }

    // ===================== SERVO CONTROL =====================
    private void ControlServoDirectly()
    {
        // 서보 직접 제어 로직은 순차적 배치 코루틴에서 담당하거나, 모선 추진 Servo[0]은 Gyro Logic에서 제어합니다.

        // ⭐ 배치 루틴이 끝나면 Servo 2~7은 더 이상 조작하지 않습니다. ⭐
    }

    // ===================== AUTO =====================
    private void HandleAutoControl()
    {
        if (GPS == null || GPS.Count == 0 || DroneMapManager.Instance == null) return;
        
        Vector3 currentPos = GPS[0].currentPos;
        
        // 초기화: 첫 번째 trajectory 가져오기
        if (!autoModeInitialized)
        {
            // 첫 번째 trajectory cell 가져오기 시도
            if (DroneMapManager.Instance.TryGetNextTrajectoryCell(out Vector3 firstCell))
            {
                autoTargetPos = firstCell;
                autoModeInitialized = true;
                autoStartTime = Time.time;  // ⭐ 시작 시간 기록
                
                // ⭐ 즉시 목표 방향으로 각도 정렬
                Vector3 dirToFirst = firstCell - currentPos;
                dirToFirst.y = 0f;
                if (dirToFirst.magnitude > 0.1f)
                {
                    float firstAngle = Mathf.Atan2(dirToFirst.x, dirToFirst.z) * Mathf.Rad2Deg;
                    targetEngineAngle = Mathf.Repeat(firstAngle - 90f, 360f);
                    Debug.Log($"<color=green>[ControlUnit Auto]</color> 초기화 완료. 첫 목표: {GetGridPos(currentPos)} → {GetGridPos(firstCell)} | 초기 각도: {targetEngineAngle:F1}° (남은: {DroneMapManager.Instance.TrajectoryCount})");
                }
            }
            else
            {
                // trajectory 아직 없음 - 대기
                SetThrust(0f);
                FullBrake();
                return;
            }
        }
        
        // finalTrajectory 기반 경로 추적
        float distToTarget = Vector3.Distance(currentPos, autoTargetPos);
        
        // 🔍 디버그: 도달 판정 확인 (더 상세히)
        if (Time.frameCount % 60 == 0)  // 1초마다
        {
            Debug.Log($"<color=yellow>[ARRIVAL CHECK]</color> Dist={distToTarget:F1}m | Threshold={AUTO_ARRIVAL_THRESHOLD:F1}m | Current={GetGridPos(currentPos)} ({currentPos.x:F1}, {currentPos.z:F1}) | Target={GetGridPos(autoTargetPos)} ({autoTargetPos.x:F1}, {autoTargetPos.z:F1}) | Remaining={DroneMapManager.Instance.TrajectoryCount}");
        }
        
        // 목표 도달 판정 + 속도 정렬
        if (distToTarget < AUTO_ARRIVAL_THRESHOLD)
        {
            Debug.Log($"<color=green>[ARRIVED]</color> 목표 도달! Dist={distToTarget:F1}m < {AUTO_ARRIVAL_THRESHOLD:F1}m | {GetGridPos(currentPos)} → {GetGridPos(autoTargetPos)}");
            
            // 다음 trajectory cell 가져오기
            if (DroneMapManager.Instance.TryGetNextTrajectoryCell(out Vector3 nextCell))
            {
                autoTargetPos = nextCell;
                
                // ⭐ 다음 경로로 전환만 하고, 각도는 아래 로직에서 업데이트
                Debug.Log($"<color=magenta>[ControlUnit Auto]</color> 다음 경로: {GetGridPos(currentPos)} → {GetGridPos(nextCell)} (남은 경로: {DroneMapManager.Instance.TrajectoryCount})");
            }
            else
            {
                // trajectory 비어있음 - Station Keeping (셀 중심 위치 사수)
                Vector3 cellCenter = SnapToGrid(currentPos);
                float distToCenter = Vector3.Distance(currentPos, cellCenter);
                
                if (distToCenter > 1.2f)
                {
                    // 중심에서 밀려남 → 복귀 추진
                    Vector3 dirToCenter = cellCenter - currentPos;
                    dirToCenter.y = 0f;
                    float returnAngle = Mathf.Atan2(dirToCenter.x, dirToCenter.z) * Mathf.Rad2Deg;
                    targetEngineAngle = Mathf.Repeat(returnAngle - 90f, 360f);  // ⭐ 0~360 정규화
                    
                    SetThrust(0.5f);
                    ApplyAerodynamicBrakes(1.0f, 1.0f, 0f);
                }
                else
                {
                    // 중심 도착 → 풀 브레이크
                    SetThrust(0f);
                    FullBrake();
                }
                return;
            }
        }
        
        // 목표 각도 업데이트 (⭐ 목표 지점까지 3m 이상 남았을 때만)
        Vector3 dirToTarget = autoTargetPos - currentPos;
        dirToTarget.y = 0f;
        
        if (distToTarget > 3.0f && dirToTarget.sqrMagnitude > 0.001f)
        {
            float requiredAngle = Mathf.Atan2(dirToTarget.x, dirToTarget.z) * Mathf.Rad2Deg;
            targetEngineAngle = Mathf.Repeat(requiredAngle+180, 360f);
            
            // ⭐ 외력 보정 추가 (Manual 모드 로직 적용)
            if (IMU != null && IMU.Count > 0)
            {
                Vector3 localVel = transform.InverseTransformDirection(IMU[0].linearVelocity);
                Vector3 localAccel = transform.InverseTransformDirection(IMU[0].accel);
                
                // 측면 외력 감지 (속도 + 가속도 예측)
                float lateralDrift = localVel.x + localAccel.x * 0.4f;
                
                // 측면 외력 반대 방향으로 보정 (직진 유지)
                // 보정 강도 감소 (10f → 3f) + 최대 ±15° 제한
                float driftCompensation = Mathf.Clamp(-lateralDrift * 20f, -5f, 5f);
                targetEngineAngle += driftCompensation;
                targetEngineAngle = Mathf.Repeat(targetEngineAngle, 360f);
            }
        }
        
        // DroneControlUnit과 동일한 물리 제어
        PerformAutoPhysicsMovement();
    }

    // ===================== DEPLOYMENT LOGIC =====================

    /// <summary>
    /// 여러 서보의 각도를 설정하고 물리적인 회전이 완료될 때까지 대기합니다.
    /// </summary>
    private IEnumerator MoveServosAndWait(List<int> servoIndices, List<float> targetAngles, float delay = 2.0f)
    {
        if (servo == null || servo.Count == 0) 
        {
            Debug.LogError("<color=red>[Servo]</color> Servo 리스트가 비어있거나 null입니다.");
            yield break;
        }

        string logMessage = "Servo Movement: ";
        for (int i = 0; i < servoIndices.Count; i++)
        {
            int index = servoIndices[i];
            float angle = targetAngles[i];
            
            if (index >= 0 && index < servo.Count)
            {
                servo[index].controlVal = angle;
                logMessage += $"S{index} -> {angle}° / ";
            }
            else
            {
                logMessage += $"S{index} (INVALID) / ";
                Debug.LogWarning($"<color=red>[Servo]</color> 유효하지 않은 Servo 인덱스 ({index})를 건너뜁니다. Servo 리스트 크기: {servo.Count}");
            }
        }
        
        Debug.Log($"<color=blue>[Servo]</color> {logMessage.TrimEnd(' ', '/')}. 대기 시간: {delay:F1}초");
        yield return new WaitForSeconds(delay);
    }
    
    /// <summary>
    /// 지정된 Silo에서 첫 번째 비활성 드론을 하나만 활성화하고 Fog Target을 등록합니다.
    /// </summary>
    private bool SpawnOneDroneFromSilo(int siloIndex)
    {
        if (Silo == null || Silo.Count <= siloIndex || Silo[siloIndex] == null)
        {
            Debug.LogError($"<color=red>[ControlUnit]</color> Silo Index {siloIndex}가 유효하지 않습니다. (Count: {Silo?.Count}). Silo 리스트 크기 및 할당 확인 필요.");
            return false;
        }

        DroneSilo_behave silo = Silo[siloIndex];
        
        Debug.Log($"<color=cyan>[Silo Debug]</color> Silo Index {siloIndex}에서 소환 시도. (Silo Name: {silo.gameObject.name}, Drone Count: {silo.droneNo})");


        for (int i = 0; i < silo.droneNo; i++)
        {
            if (i < silo.droneList.Count && silo.droneList[i] != null && !silo.droneList[i].activeSelf)
            {
                GameObject drone = silo.droneList[i];
                // DroneControlUnit dcu = drone.GetComponent<DroneControlUnit>(); 
                
                drone.transform.position = silo.spawnPoint.position;
                drone.transform.rotation = silo.spawnPoint.rotation;
                
                // SetActive(true) 시 DroneControlUnit.Start()가 호출됨
                drone.SetActive(true); 

                // Fog of War Target 등록 로직
                LIDAR_behave[] droneLIDAR = drone.GetComponentsInChildren<LIDAR_behave>();
                
                if (fog2 != null)
                {
                    bool lidarRegistered = false;
                    
                    foreach (LIDAR_behave lidar in droneLIDAR)
                    {
                        if (lidar != null)
                        {
                            // Targets 리스트에 LIDAR Transform 등록
                            fog2.targets.Add(lidar.transform);
                            Debug.Log($"<color=cyan>[FOW]</color> Drone {drone.name}: LIDAR Transform ({lidar.transform.name}) 등록 완료.");
                            lidarRegistered = true;
                        }
                    }

                    if (!lidarRegistered)
                    {
                        Debug.LogError($"<color=red>[FOW ERROR]</color> Drone {drone.name}에 LIDAR_behave 컴포넌트가 없습니다! Fog Target 등록 실패.");
                    }
                }
                else
                {
                    Debug.LogError($"<color=red>[FOW ERROR]</color> ControlUnit의 'Fog2' 필드가 null입니다. 인스펙터에 FogOfWarPersistent2 인스턴스를 할당해야 합니다.");
                }
                
                Debug.Log($"<color=green>[ControlUnit]</color> Silo {siloIndex}에서 드론 #{i} ({drone.name}) 활성화 성공.");
                return true; // 드론 하나만 소환 성공
            }
        }
        
        Debug.LogWarning($"<color=orange>[ControlUnit]</color> Silo {siloIndex} ({silo.gameObject.name})에 활성화할 수 있는 드론이 없습니다.");
        return false;
    }

    /// <summary>
    /// 요청된 순서에 따라 서보를 제어하고 드론을 순차적으로 배치합니다. (단 한 번 실행)
    /// </summary>
    private IEnumerator SequentialDeploymentRoutine()
    {
        const float SERVO_DEPLOY_DELAY = 2.0f; // 서보 동작 시간
        const float SPAWN_INTERVAL = 0.5f; // 드론 사출 후 대기 시간
        
        // ⭐ dronesSpawned는 Start()에서 체크되었으므로, 코루틴은 한 번만 실행됨

        Debug.Log($"<color=yellow>--- [START] 드론 배치 루틴 단일 실행 시작 ---</color>");

        // 1. Silo 0 배포 로직 (Servo 2, 3, 4)
        Debug.Log("<color=yellow>--- 1. Silo 0 배포 시작 (Servo 2, 3, 4) ---</color>");
        
        // 1-1. 서보 전개
        yield return StartCoroutine(MoveServosAndWait(
            new List<int> { 2, 3, 4 }, 
            new List<float> { 270f, 180f, 270f }, 
            SERVO_DEPLOY_DELAY
        ));

        // 1-2. 드론 사출 (Index 0)
        bool spawned0 = SpawnOneDroneFromSilo(0);
        yield return new WaitForSeconds(SPAWN_INTERVAL);
        
        // 1-3. 서보 회수 (조작 금지 요청에 따라 0도로 복귀)
        yield return StartCoroutine(MoveServosAndWait(
            new List<int> { 2, 3, 4 }, 
            new List<float> { 0f, 0f, 0f }, 
            SERVO_DEPLOY_DELAY
        ));


        // 2. Silo 1 배포 로직 (Servo 5, 6, 7)
        Debug.Log("<color=yellow>--- 2. Silo 1 배포 시작 (Servo 5, 6, 7) ---</color>");
        
        // 2-1. 서보 전개
        yield return StartCoroutine(MoveServosAndWait(
            new List<int> { 5, 6, 7 }, 
            new List<float> { 270f, 180f, 270f }, 
            SERVO_DEPLOY_DELAY
        ));

        // 2-2. 드론 사출 (Index 1)
        bool spawned1 = SpawnOneDroneFromSilo(1);
        yield return new WaitForSeconds(SPAWN_INTERVAL);
        
        // 2-3. 서보 회수 (조작 금지 요청에 따라 0도로 복귀)
        yield return StartCoroutine(MoveServosAndWait(
            new List<int> { 5, 6, 7 }, 
            new List<float> { 0f, 0f, 0f }, 
            SERVO_DEPLOY_DELAY
        ));


        // 3. Silo 2 배포 로직 (즉시)
        Debug.Log("<color=yellow>--- 3. Silo 2 배포 시작 (즉시) ---</color>");
        bool spawned2 = SpawnOneDroneFromSilo(2); // Index 2
        yield return new WaitForSeconds(SPAWN_INTERVAL); 

        
        Debug.Log("<color=red>★★★ [CONTROL NOTE]</color> 드론 배치 완료. 서보 2~7 조작은 중단됩니다. ★★★");

        // 배치 완료 후, dronesSpawned 플래그를 true로 설정하여 재실행을 막음
        dronesSpawned = true; 
    }

    // ===================== MANUAL =====================
    private void HandleManualControl()
    {
        // Manual 모드: maxThrust=1.0 고정, 조이스틱으로 방향 제어, 브레이크로 외력 흡수
        const float maxThrust = 1.0f;
        
        float x = (A0 - 512f) / 512f;
        float y = (A1 - 512f) / 512f;
        x = Mathf.Abs(x) < 0.1f ? 0f : x;
        y = Mathf.Abs(y) < 0.1f ? 0f : y;
        bool hasJoystickInput = (Mathf.Abs(x) > 0.01f || Mathf.Abs(y) > 0.01f);
        
        float thrustPower = maxThrust;
        float leftBrake = 0f;
        float rightBrake = 0f;
        
        // 조이스틱 중립 시 IMU 기반 브레이크로 외력 흡수
        if (!hasJoystickInput && IMU != null && IMU.Count > 0)
        {
            Vector3 localVel = transform.InverseTransformDirection(IMU[0].linearVelocity);
            
            // 측면 속도 감지
            float lateralVel = localVel.x;
            
            // 측면 속도 방향에 따라 비대칭 브레이크 적용
            if (Mathf.Abs(lateralVel) > 0.1f)
            {
                if (lateralVel > 0)  // 오른쪽으로 밀림 → 오른쪽 브레이크 강화
                {
                    rightBrake = Mathf.Clamp01(Mathf.Abs(lateralVel) * 0.5f);
                }
                else  // 왼쪽으로 밀림 → 왼쪽 브레이크 강화
                {
                    leftBrake = Mathf.Clamp01(Mathf.Abs(lateralVel) * 0.5f);
                }
            }
            
            // 속도 기반 스로틀 감소 (최대값은 maxThrust)
            float speed = new Vector2(localVel.x, localVel.z).magnitude;
            thrustPower = Mathf.Clamp(speed * 0.5f, 0f, maxThrust);
        }
        
        // 엔진 제어
        foreach (var eng in engine)
            eng.controlVal = thrustPower;
        
        // 브레이크 제어 (좌우 비대칭, 앞뒤는 해제)
        ApplyAerodynamicBrakes(leftBrake, rightBrake, 0f);
    }

    // ===================== ENGINE =====================
    private void SetEnginePower(float p)
    {
        foreach (var e in engine)
            e.controlVal = Mathf.Clamp01(p);
    }

    // ===================== ROTATION =====================
    private void FreezeRotation()
    {
        rb.angularVelocity = Vector3.zero;
        transform.rotation = Quaternion.identity;
    }

    // ===================== PATH =====================
    public void addPathPoint(Vector3 pos)
    {
        foreach (var p in pathpointList)
        {
            if (!p.activeSelf)
            {
                p.transform.position = pos;
                p.SetActive(true);
                activePathPoints.Add(p);
                return;
            }
        }
    }
    
    // ===================== DEBUG =====================
    private void DebugIMUValues()
    {
        debugTimer += Time.fixedDeltaTime;
        
        if (debugTimer >= debugInterval)
        {
            // IMU 디버그 로직 (생략)
        }
    }
    
    private void DebugStateLog()
    {
        if (debugTimer >= debugInterval) // 1초 간격으로 출력
        {
            int activeDrones = GetTotalActiveDroneCount();
            Debug.Log($"<color=yellow>[State]</color> Mode: {currentMode} | Spawned: {dronesSpawned} | Active Drones: {activeDrones}");
            
            // COLLINFO 정보 출력
            if (GPS != null && GPS.Count > 0 && IMU != null && IMU.Count > 0 && servo != null && servo.Count > 0)
            {
                Vector3 currentPos = GPS[0].currentPos;
                Vector3 localVel = transform.InverseTransformDirection(IMU[0].linearVelocity);
                Vector3 worldVel = IMU[0].linearVelocity;
                Vector3 localAccel = transform.InverseTransformDirection(IMU[0].accel);
                float lateralDrift = localVel.x + localAccel.x * 0.4f;
                float driftComp = Mathf.Clamp(-lateralDrift * 3f, -15f, 15f);
                
                string brakeInfo = brake.Count >= 5 ? 
                    $"L={brake[0].controlVal:F2} R={brake[1].controlVal:F2} FB={brake[4].controlVal:F2}" : 
                    "N/A";
                
                float thrust = engine.Count > 0 ? engine[0].controlVal : 0f;
                
                Debug.Log(
                    $"<color=cyan>[COLLINFO]</color> ========== STATUS ==========\n" +
                    $"Position: {GetGridPos(currentPos)} World=({currentPos.x:F1}, {currentPos.z:F1}) | Target: {GetGridPos(autoTargetPos)} ({autoTargetPos.x:F1}, {autoTargetPos.z:F1})\n" +
                    $"Velocity: Local=({localVel.x:F2}, {localVel.z:F2}) World=({worldVel.x:F2}, {worldVel.z:F2}) | LateralDrift={lateralDrift:F2}\n" +
                    $"Servo: Current={servo[0].controlVal:F1}° Target={targetEngineAngle:F1}° | AngleError={Mathf.DeltaAngle(servo[0].controlVal, targetEngineAngle):F1}° | DriftComp={driftComp:F1}°\n" +
                    $"Control: Thrust={thrust:F2} Brake=[{brakeInfo}] Mode={currentMode}"
                );
            }
            
            debugTimer = 0f; // 타이머 초기화
        }
    }
    
    // ===================== AUTO MODE HELPERS =====================
    
    // ControlUnit Auto 모드: finalTrajectory 기반 경로 추적 (LIDAR 없음)
    // DroneControlUnit과 동일한 물리 제어 로직
    private void PerformAutoPhysicsMovement()
    {
        // 🔍 디버그: 위치 및 각도 확인 (더 자주)
        if (GPS != null && GPS.Count > 0 && Time.frameCount % 30 == 0)
        {
            Vector3 pos = GPS[0].currentPos;
            Vector3 targetDir = autoTargetPos - pos;
            targetDir.y = 0f;
            float dist = targetDir.magnitude;
            
            // 월드 좌표 출력
            Debug.Log($"<color=cyan>[WORLD POS]</color> Current: ({pos.x:F1}, {pos.z:F1}) | Target: ({autoTargetPos.x:F1}, {autoTargetPos.z:F1}) | Dir: ({targetDir.x:F1}, {targetDir.z:F1})");
            
            // 각도 계산 과정 출력
            float rawAngle = Mathf.Atan2(targetDir.x, targetDir.z) * Mathf.Rad2Deg;
            float angleWithOffset = rawAngle - 90f;
            float correctAngle = Mathf.Repeat(angleWithOffset, 360f);
            
            // IMU 보정 출력
            float lateralDrift = 0f;
            float driftComp = 0f;
            if (IMU != null && IMU.Count > 0)
            {
                Vector3 localVel = transform.InverseTransformDirection(IMU[0].linearVelocity);
                Vector3 localAccel = transform.InverseTransformDirection(IMU[0].accel);
                lateralDrift = localVel.x + localAccel.x * 0.4f;
                driftComp = -lateralDrift * 10f;
            }
            
            Debug.Log($"<color=orange>[AUTO DEBUG]</color> Dist={dist:F1}m | RawAngle={rawAngle:F1}° | -90°={angleWithOffset:F1}° | Repeat={correctAngle:F1}° | LateralDrift={lateralDrift:F2} | DriftComp={driftComp:F1}° | ServoYaw={servo[0].controlVal:F1}° | TargetAngle={targetEngineAngle:F1}°");
        }
        
        // 1. 목표 각도 오차 계산 (DroneControlUnit과 동일)
        float currentYaw = (servo.Count > 0) ? servo[0].controlVal : 0f;
        float angleError = Mathf.DeltaAngle(currentYaw, targetEngineAngle);

        // 2. 서보 모터 P-Control
        float Kp = 3.0f;
        float servoOutput = currentYaw + (angleError * Kp * Time.fixedDeltaTime * 10f);
        servoOutput = Mathf.Repeat(servoOutput, 360f);  // ⭐ 0~360 범위로 정규화
        if (servo.Count > 0) servo[0].controlVal = servoOutput;

        // 4. 스로틀 & 브레이크 제어
        float absError = Mathf.Abs(angleError);
        bool is180Turn = absError > 120f;

        // [설정] 주행 중 좌우 기본 저항 (안정성 확보)
        float defaultDrag = 1.0f;  // ⭐ 1.0f → 0.3f로 감소 (직진 안정성 향상)

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
    
    private Vector3 SnapToGrid(Vector3 worldPos)
    {
        float gridX = Mathf.Round(worldPos.x / MAP_CUBE_SIZE) * MAP_CUBE_SIZE;
        float gridZ = Mathf.Round(worldPos.z / MAP_CUBE_SIZE) * MAP_CUBE_SIZE;
        return new Vector3(gridX, worldPos.y, gridZ);
    }
    
    private string GetGridPos(Vector3 worldPos)
    {
        int gridX = Mathf.RoundToInt(worldPos.x / MAP_CUBE_SIZE) + 10;
        int gridZ = Mathf.RoundToInt(worldPos.z / MAP_CUBE_SIZE) + 10;
        return $"({gridX},{gridZ})";
    }
    
    private void SetThrust(float val)
    {
        foreach (var eng in engine)
            eng.controlVal = Mathf.Clamp01(val);
    }
    
    private void ApplyAerodynamicBrakes(float leftVal, float rightVal, float frontBackVal)
    {
        if (brake.Count > 0) brake[0].controlVal = leftVal;
        if (brake.Count > 1) brake[1].controlVal = rightVal;
        if (brake.Count > 2) brake[2].controlVal = leftVal;
        if (brake.Count > 3) brake[3].controlVal = rightVal;
        if (brake.Count > 4) brake[4].controlVal = frontBackVal;
        if (brake.Count > 5) brake[5].controlVal = frontBackVal;
        if (brake.Count > 6) brake[6].controlVal = frontBackVal;
    }
    
    private void FullBrake()
    {
        ApplyAerodynamicBrakes(1.0f, 1.0f, 1.0f);
    }
}