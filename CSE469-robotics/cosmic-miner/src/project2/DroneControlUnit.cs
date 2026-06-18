using UnityEngine;
using System.IO;
using System.Collections.Generic;
using UnityEngine.Android;

#if UNITY_EDITOR
using UnityEditor;
#endif

public class DroneControlUnit : MonoBehaviour
{
    [Header("Drone Actuators")]
    public Rigidbody rb;
    public List<ThrusterBehave> engine;
    public List<BrakeBehave> brake;
    public List<ServoBehave> servo;
    public List<IMU_Behave> IMU;
    public List<GPS_Behave> GPS;   // GPS_Behave (Element 0 기준) 안에 checkpoints 목록 있음

    // ===== CSV 파일 이름들 =====
    public string fileName = "breakDist.csv";              // 기존 용도 (지금은 헤더만 씀)
    public string instLogFileName = "inst_log.csv";        // 0.1초 간격 속도 로그
    public string checkpointLogFileName = "checkpoint_record.csv"; // 체크포인트 도착 로그

    // Servo control timeline CSV
    public string servoTimelineFile = "servo_timeline.csv";

    // ===== CSV 버퍼 =====
    System.Text.StringBuilder sb = new System.Text.StringBuilder();
    System.Text.StringBuilder instSb = new System.Text.StringBuilder();
    System.Text.StringBuilder checkpointSb = new System.Text.StringBuilder();

    Vector3 brakePoint;

    public int min, sec, frame;

    // ===== Servo 타임라인 구조 =====
    [System.Serializable]
    public class ServoKeyframe
    {
        public int second;
        public int frame;
        public float servoValue;
        public int rotate; // -1: counter-clockwise, 0: hold, 1: clockwise

        public ServoKeyframe(float time, float value, int rotate)
        {
            // Convert time to second and frame
            // 1 second = 50 frames
            // time 1.26 = 1 second + 0.26*50 = 1 second + 13 frames
            this.second = (int)time;
            float fractionalPart = time - this.second;
            this.frame = Mathf.FloorToInt(fractionalPart * 50f);
            this.servoValue = value;
            this.rotate = rotate;
        }
    }

    private List<ServoKeyframe> servoTimeline;
    private float currentServoValue = 0f;
    private int currentKeyframeIndex = 0;
    private int nextKeyframeIndex = 0;

    // ===== 타이머 / 로깅 =====
    private bool isTimerStarted = false;
    private float internalTimer = 0f;

    // 0.1초마다 속도 로그
    public float instLogInterval = 0.1f;
    private float instLogTimer = 0f;

    // ===== 체크포인트 판정 =====
    public float checkpointRadius = 10.0f;   // 드론-체크포인트 거리 <= checkpointRadius면 도착으로 간주 (이 값 = arriveThreshold로 사용)

    // ★ NEW: 오버슈트 캡처 반경 배수
    public float captureScale = 1.8f;       // arriveThreshold * captureScale 까지 오버슈트 허용

    // ===== 기타 (기존 코드와 호환) =====
    [System.Serializable]
    public enum dronePhase // make your own control phase by defining new enum variable
    {
        forward,
        fordown,
        down,
        backdown,
        backward,
        backup,
        up,
        forup
        // brake
    }

    public dronePhase dp;
    public float testVelocity;
    private float actualTestVelocity;
    public Vector3 currentVel;

    // ★ NEW: 체크포인트 순차 인식 상태
    private int curIdx = 0;                           // 현재 목표 체크포인트 인덱스
    private int lastLoggedIdx = -1;                   // 중복 로그 방지
    private float prevPlanarDist = float.PositiveInfinity; // 오버슈트 감지용 (XZ 평면 거리)

    // ================== 외부에서 호출: 스타트 플랫폼 떠날 때 ==================
    public void leaveStartingPoint()
    {
        isTimerStarted = true;
        sec = 0;
        frame = 0;
        internalTimer = 0f;

        // ★ NEW: 체크포인트 상태 리셋
        curIdx = 0;
        lastLoggedIdx = -1;
        prevPlanarDist = float.PositiveInfinity;

        Debug.Log("DroneControlUnit: Timer started");
    }
    // =====================================================================

    void Start()
    {
        rb = this.GetComponent<Rigidbody>();

        // 기존 breakDist 헤더 (필요하면 내용 추가해서 써도 됨)
        sb.AppendLine("velocity, distance");

        // inst_log.csv 헤더
        instSb.AppendLine("time,vel_x,vel_y,vel_z,speed_xy,speed_3d");

        // checkpoint_record.csv 헤더
        checkpointSb.AppendLine("index,checkpoint_name,pos_x,pos_y,pos_z,time_sec,frame");

        File.WriteAllText(
            Path.Combine(Application.dataPath, checkpointLogFileName),
            checkpointSb.ToString()
        );

        // 시작지점을 지나기 전에 시간측정이 시작하지 않도록
        min = 0; sec = -1000; frame = 0;

        // Servo 타임라인 초기화
        InitializeServoTimeline();

        Debug.Log($"[DroneControlUnit] Application.dataPath = {Application.dataPath}");
    }

    // ===== servo_timeline.csv 로드 =====
    private void InitializeServoTimeline()
    {
        servoTimeline = new List<ServoKeyframe>();

        string path = Path.Combine(Application.dataPath, servoTimelineFile);

        if (!File.Exists(path))
        {
            Debug.LogError($"Servo timeline CSV file not found at {path}");
            return;
        }

        try
        {
            string[] lines = File.ReadAllLines(path);

            // 첫 줄은 헤더 (time,servoValue,rotate,memo)
            for (int i = 1; i < lines.Length; i++)
            {
                string line = lines[i].Trim();
                if (string.IsNullOrEmpty(line)) continue;

                string[] values = line.Split(',');
                // time, servoValue, rotate, memo → 4개 이상이라고 가정
                if (values.Length < 3)
                {
                    Debug.LogWarning($"Invalid line format at line {i + 1}: {line}");
                    continue;
                }

                float time = float.Parse(values[0].Trim());
                float servoValue = float.Parse(values[1].Trim());
                int rotate = int.Parse(values[2].Trim());

                servoTimeline.Add(new ServoKeyframe(time, servoValue, rotate));
            }

            Debug.Log($"Loaded {servoTimeline.Count} servo keyframes from {path}");

            // 초기 인덱스 세팅
            if (servoTimeline.Count > 0)
            {
                currentServoValue = servoTimeline[0].servoValue;
                currentKeyframeIndex = 0;
                nextKeyframeIndex = servoTimeline.Count > 1 ? 1 : 0;
            }
        }
        catch (System.Exception e)
        {
            Debug.LogError($"Failed to load servo timeline CSV: {e}");
        }
    }

    // ===== 회전 고정 (기존 코드) =====
    private void FreezeRotation()
    {
        rb.angularVelocity = new Vector3(0f, rb.angularVelocity.y, 0f);
        Vector3 curRot = this.transform.rotation.eulerAngles;
        this.transform.rotation = Quaternion.Euler(0f, curRot.y, 0f);
        rb.linearVelocity = new Vector3(rb.linearVelocity.x, 0f, rb.linearVelocity.z);
    }

    void Update()
    {
        // 입력은 안 씀 (새 Input System 사용 중이므로 UnityEngine.Input 쓰지 않음)
    }

    void FixedUpdate()
    {
        FreezeRotation();

        // control system: 지금은 엔진 0번 항상 ON
        currentVel = rb.linearVelocity;
        if (engine != null && engine.Count > 0 && engine[0] != null)
            engine[0].controlVal = 1f;

        // 타이머 / 로깅은 leaveStartingPoint 이후에만
        if (isTimerStarted)
        {
            // 시간 업데이트
            internalTimer += Time.fixedDeltaTime;
            sec = (int)internalTimer;
            float fractionalPart = internalTimer - sec;
            frame = Mathf.FloorToInt(fractionalPart * 50f);

            // ===== 0.1초 간격 속도 로깅 =====
            instLogTimer += Time.fixedDeltaTime;
            if (instLogTimer >= instLogInterval)
            {
                instLogTimer -= instLogInterval;

                Vector3 v = rb.linearVelocity;
                float speedXY = new Vector2(v.x, v.z).magnitude;
                float speed3D = v.magnitude;

                instSb.AppendLine(
                    $"{internalTimer:F3},{v.x:F4},{v.y:F4},{v.z:F4},{speedXY:F4},{speed3D:F4}"
                );
            }
            // =================================

            // ===== 체크포인트 도착 검사 + 불 켜기 + CSV 기록 =====
            CheckCheckpointArrival();
            // ==================================================
        }

        // Servo 타임라인 기반으로 서보 각도 업데이트
        UpdateServoFromTimeline();
    }

    // ===== 체크포인트 도착 판정 & 기록 =====
    private void CheckCheckpointArrival()
    {

        Debug.Log($"[DEBUG] GPS={GPS != null}, cpsCount={(GPS != null && GPS.Count > 0 && GPS[0] != null && GPS[0].checkpoints != null ? GPS[0].checkpoints.Count : 0)}, curIdx={curIdx}");


        // GPS / checkpoints가 세팅 안 돼 있으면 아무 것도 안 함
        if (GPS == null || GPS.Count == 0 || GPS[0] == null) return;

        GPS_Behave gps = GPS[0];
        if (gps.checkpoints == null || gps.checkpoints.Count == 0) return;

        var cps = gps.checkpoints;

        if (curIdx >= cps.Count) return; // 모든 체크포인트 통과

        checkpointBehave target = cps[curIdx];
        if (target == null) return;

        // 드론 현재 위치
        Vector3 dronePos = transform.position;

        // 체크포인트 위치 (checkpointBehave에서 저장해 둔 좌표 사용)
        Vector3 cpPos = target.transform.position;

        // ★ NEW: XZ 평면 거리만 사용 (고도는 무시)
        float dx = cpPos.x - dronePos.x;
        float dz = cpPos.z - dronePos.z;
        float planarDist = Mathf.Sqrt(dx * dx + dz * dz);

        float arriveThreshold = checkpointRadius;            // 기존 radius를 그대로 사용
        float captureRadius = arriveThreshold * captureScale;

        bool arrivedCore = planarDist <= arriveThreshold;
        bool overshootCapture = false;

        // ★ NEW: 오버슈트 캡처 로직
        if (!arrivedCore && prevPlanarDist < float.PositiveInfinity)
        {
            bool movingAway = planarDist > prevPlanarDist + 1e-4f;
            if (movingAway && planarDist <= captureRadius)
            {
                overshootCapture = true;
            }
        }

        // NEW: 실제 도착 판정
        if ((arrivedCore || overshootCapture) && lastLoggedIdx != curIdx && !target.isTriggered)
        {
            // 불 켜기 (기존 로직 유지)
            target.lit();

            // CSV 기록 (기존 포맷 유지: index, name, cpPos, internalTimer, frame)
            checkpointSb.AppendLine(
                $"{curIdx},{target.name},{cpPos.x:F3},{cpPos.y:F3},{cpPos.z:F3},{internalTimer:F3},{frame}"
            );

            File.AppendAllText(
                Path.Combine(Application.dataPath, checkpointLogFileName),
                $"{curIdx},{target.name},{cpPos.x:F3},{cpPos.y:F3},{cpPos.z:F3},{internalTimer:F3},{frame}\n"
            );

            Debug.Log($"[DroneControlUnit] Reached checkpoint {curIdx} ({target.name}) at t={internalTimer:F3}s dist={planarDist:F3}");

            lastLoggedIdx = curIdx;
            curIdx++;                             // 다음 체크포인트로 진행
            prevPlanarDist = float.PositiveInfinity;
        }
        else
        {
            // 아직 도착 아니면 이전 거리 갱신
            prevPlanarDist = planarDist;
        }
    }

    // ===== servoTimeline 기반 서보 제어 =====
    private void UpdateServoFromTimeline()
    {
        if (servoTimeline == null || servoTimeline.Count == 0)
            return;

        if (servo == null || servo.Count == 0 || servo[0] == null)
            return;

        // 다음 키프레임 도달했는지 체크
        if (nextKeyframeIndex < servoTimeline.Count)
        {
            var nextKeyframe = servoTimeline[nextKeyframeIndex];
            int currentTotalFrames = sec * 50 + frame;
            int nextTotalFrames = nextKeyframe.second * 50 + nextKeyframe.frame;

            if (currentTotalFrames >= nextTotalFrames)
            {
                currentKeyframeIndex = nextKeyframeIndex;
                nextKeyframeIndex++;

                // 더 이상 다음 키프레임이 없으면 마지막 값 유지
                if (nextKeyframeIndex >= servoTimeline.Count)
                {
                    currentServoValue = servoTimeline[currentKeyframeIndex].servoValue;
                    servo[0].controlVal = currentServoValue;
                    return;
                }
            }
        }

        // 현재 ~ 다음 키프레임 사이 보간
        if (currentKeyframeIndex < servoTimeline.Count && nextKeyframeIndex < servoTimeline.Count)
        {
            var currentKeyframe = servoTimeline[currentKeyframeIndex];
            var nextKeyframe = servoTimeline[nextKeyframeIndex];

            int currentTotalFrames = sec * 50 + frame;
            int startTotalFrames = currentKeyframe.second * 50 + currentKeyframe.frame;
            int endTotalFrames = nextKeyframe.second * 50 + nextKeyframe.frame;

            if (currentKeyframe.rotate == 0)
            {
                // rotate=0: 현재 각도 그대로 유지
                currentServoValue = currentKeyframe.servoValue;
            }
            else
            {
                float progress = 0f;
                if (endTotalFrames > startTotalFrames)
                {
                    progress = (float)(currentTotalFrames - startTotalFrames) /
                               (endTotalFrames - startTotalFrames);
                    progress = Mathf.Clamp01(progress);
                }

                float startAngle = currentKeyframe.servoValue;
                float endAngle = nextKeyframe.servoValue;
                float angleDiff = endAngle - startAngle;

                if (currentKeyframe.rotate == 1)
                {
                    // Clockwise: 항상 + 방향으로 회전
                    while (angleDiff < 0f) angleDiff += 360f;
                }
                else if (currentKeyframe.rotate == -1)
                {
                    // Counter-clockwise: 항상 - 방향으로 회전
                    while (angleDiff > 0f) angleDiff -= 360f;
                }

                currentServoValue = startAngle + angleDiff * progress;
            }
        }
        else if (currentKeyframeIndex < servoTimeline.Count)
        {
            currentServoValue = servoTimeline[currentKeyframeIndex].servoValue;
        }

        // 실제 서보에 값 적용
        servo[0].controlVal = currentServoValue;
    }

    // ===== 플레이 중지 / 오브젝트 비활성화 시 CSV 자동 저장 =====
    void OnDisable()
    {
        try
        {
            string path = Path.Combine(Application.dataPath, fileName);
            string instPath = Path.Combine(Application.dataPath, instLogFileName);
            string checkpointPath = Path.Combine(Application.dataPath, checkpointLogFileName);

            File.WriteAllText(path, sb.ToString());
            File.WriteAllText(instPath, instSb.ToString());
            File.WriteAllText(checkpointPath, checkpointSb.ToString());

            Debug.Log($"[DroneControlUnit] CSV saved to {path}");
            Debug.Log($"[DroneControlUnit] Instantaneous speed CSV saved to {instPath}");
            Debug.Log($"[DroneControlUnit] Checkpoint CSV saved to {checkpointPath}");

#if UNITY_EDITOR
            AssetDatabase.Refresh();
#endif
        }
        catch (System.Exception e)
        {
            Debug.LogError($"Failed to write CSV: {e}");
        }
    }
}
