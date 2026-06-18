using System;
using System.IO.Ports;
using System.Threading;
using UnityEngine;

public class SerialReader : MonoBehaviour
{
    public ControlUnit CU;
    [Header("Serial Settings")]
    public string portName = "COM3";          // 비워두면 자동 탐색
    public int baudRate = 115200;
    public bool autoOpenOnStart = true;
    public bool autoReconnect = true;
    public bool autoDetectPort = true;    // true면 자동 탐색 사용
    public int portOpenResetWaitMs = 500; // Uno 자동리셋 대기
    public int scanPerPortProbePackets = 3; // 각 포트에서 최대 몇 개 패킷 검사할지
    // --- Detect tuning (auto-detect phase only) ---
    private const int DETECT_WARMUP_MS = 1200; // 리셋 후 안정화(부트로더+스케치 시작)
    private const int DETECT_FIND_START_MS = 1500; // START(0xAA) 찾는 총 대기한도
    private const int DETECT_READ_TIMEOUT_MS = 100;  // 탐색 중 per-read 타임아웃


    [Header("Raw ADC (0..1023)")]
    public ushort j1x;    // A0
    public ushort j1y;    // A1
    public ushort j2x;    // A2
    public ushort j2y;    // A3
    public ushort pot1;   // A4
    public ushort pot2;   // A5

    [Header("Buttons (pressed = true)")]
    public bool button1;  // bit0
    public bool button2;  // bit1
    public bool button3;  // bit2
    public bool button4;  // bit3
    public bool button5;  // bit4

    [Header("Stats")]
    public int packetsPerSecond;
    public int checksumErrors;
    public int framingErrors;
    public string connectedPort;          // 현재 연결된 포트 이름

    // --- 16B Packet spec ---
    // [0]  START = 0xAA
    // [1..12] 6 * uint16 (LE) A0..A5
    // [13] BTN (pressed=1 bits 0..4)
    // [14] CHK = sum(12 analog bytes + BTN) mod 256
    // [15] END   = 0x55
    private const byte START_BYTE = 0xAA;
    private const byte END_BYTE = 0x55;
    private const int PACKET_LEN = 16;
    private const int REM_AFTER_START = PACKET_LEN - 1; // 15
    private const int READ_TIMEOUT_MS = 20;
    private const int RECONNECT_WAIT_MS = 500;

    // --- Serial + Thread ---
    private SerialPort _sp;
    private Thread _rxThread;
    private volatile bool _run;

    private readonly object _lock = new object();
    private Parsed _latest;
    private int _packetsCounter;
    private float _ppsTimer;

    [Serializable]
    private struct Parsed
    {
        public ushort a0, a1, a2, a3, a4, a5;
        public byte btn;
        public bool valid;
    }

    void Start()
    {
        if (autoOpenOnStart) StartWorker();
    }

    void FixedUpdate()
    {
        Parsed snap;
        lock (_lock) snap = _latest;

        if (snap.valid)
        {
            j1x = snap.a0; j1y = snap.a1;
            j2x = snap.a2; j2y = snap.a3;
            pot1 = snap.a4; pot2 = snap.a5;

            button1 = (snap.btn & (1 << 0)) != 0;
            button2 = (snap.btn & (1 << 1)) != 0;
            button3 = (snap.btn & (1 << 2)) != 0;
            button4 = (snap.btn & (1 << 3)) != 0;
            button5 = (snap.btn & (1 << 4)) != 0;

            if(CU!= null)
            {
                CU.A0 = snap.a0; CU.A1 = snap.a1;
                CU.A2 = snap.a2; CU.A3 = snap.a3;
                CU.A4 = snap.a4; CU.A5 = snap.a5;

                CU.D2 = (snap.btn & (1 << 0)) != 0;
                CU.D3 = (snap.btn & (1 << 1)) != 0;
                CU.D4 = (snap.btn & (1 << 2)) != 0;
                CU.D5 = (snap.btn & (1 << 3)) != 0;
                CU.D6 = (snap.btn & (1 << 4)) != 0;
            }
        }

        _ppsTimer += Time.unscaledDeltaTime;
        if (_ppsTimer >= 1f)
        {
            packetsPerSecond = Interlocked.Exchange(ref _packetsCounter, 0);
            _ppsTimer = 0f;
        }
    }

    void OnDisable() => StopWorker();
    void OnDestroy() => StopWorker();

    // -------- Controls --------
    public void StartWorker()
    {
        StopWorker();
        _run = true;
        _rxThread = new Thread(RxLoop) { IsBackground = true, Name = "ArduinoSerialRx" };
        _rxThread.Start();
    }

    public void StopWorker()
    {
        _run = false;

        try { _sp?.Close(); } catch { }
        try { _sp?.Dispose(); } catch { }
        _sp = null;

        if (_rxThread != null)
        {
            try { _rxThread.Join(300); } catch { }
            _rxThread = null;
        }
        connectedPort = "";
    }

    // -------- RX Thread --------
    private void RxLoop()
    {
        while (_run)
        {
            try
            {
                EnsurePortOpenWithAutoDetect();

                // 정상 수신 루프
                int b = SafeReadByte(_sp);
                if (b < 0) continue;
                if ((byte)b != START_BYTE) { framingErrors++; continue; }

                byte[] buf = new byte[REM_AFTER_START]; // 15B
                if (!ReadExact(_sp, buf, 0, buf.Length, READ_TIMEOUT_MS)) continue;

                if (buf[14] != END_BYTE) { framingErrors++; continue; }

                byte calcChk = 0;
                for (int i = 0; i < 12; i++) calcChk += buf[i];
                calcChk += buf[12];
                byte pktChk = buf[13];
                if (calcChk != pktChk) { checksumErrors++; continue; }

                ushort a0 = (ushort)(buf[0] | (buf[1] << 8));
                ushort a1 = (ushort)(buf[2] | (buf[3] << 8));
                ushort a2 = (ushort)(buf[4] | (buf[5] << 8));
                ushort a3 = (ushort)(buf[6] | (buf[7] << 8));
                ushort a4 = (ushort)(buf[8] | (buf[9] << 8));
                ushort a5 = (ushort)(buf[10] | (buf[11] << 8));
                byte btn = buf[12];

                var parsed = new Parsed { a0 = a0, a1 = a1, a2 = a2, a3 = a3, a4 = a4, a5 = a5, btn = btn, valid = true };
                lock (_lock) _latest = parsed;
                Interlocked.Increment(ref _packetsCounter);
            }
            catch (ThreadAbortException) { return; }
            catch (Exception)
            {
                // 포트 오류 → 닫고 재탐색
                SafeClosePort();
                if (!autoReconnect) return;
                Thread.Sleep(RECONNECT_WAIT_MS);
            }
        }
    }

    // -------- Port Open w/ Auto Detect --------
    private void EnsurePortOpenWithAutoDetect()
    {
        if (_sp != null && _sp.IsOpen) return;

        if (!autoDetectPort && !string.IsNullOrEmpty(portName))
        {
            // 지정 포트 사용
            OpenPort(portName);
            connectedPort = portName;
            return;
        }

        // 자동 탐색
        string[] ports = SerialPort.GetPortNames();
        foreach (var p in ports)
        {
            if (!_run) return;

            if (TryOpenAndValidate(p))
            {
                connectedPort = p;
                return;
            }
            // 실패하면 다음 포트 시도
            SafeClosePort();
        }

        // 후보 없음 → 잠시 대기 후 재시도
        Thread.Sleep(RECONNECT_WAIT_MS);
        throw new Exception("No valid Arduino port found in auto-detect.");
    }

    private void OpenPort(string p)
    {
        _sp = new SerialPort(p, baudRate, Parity.None, 8, StopBits.One)
        {
            ReadTimeout = READ_TIMEOUT_MS,
            WriteTimeout = READ_TIMEOUT_MS,
            Handshake = Handshake.None,
            DtrEnable = true,   // Uno 자동리셋 트리거
            RtsEnable = false
        };
        _sp.Open();

        // 자동 리셋 대기 + 버퍼 정리
        Thread.Sleep(portOpenResetWaitMs);
        try { _sp.DiscardInBuffer(); } catch { }
        try { _sp.DiscardOutBuffer(); } catch { }
    }

    private bool TryOpenAndValidate(string p)
    {
        try
        {
            OpenPort(p);

            // --- 탐색 전용 WARM-UP: 리셋 이후 추가 안정화 시간 ---
            // (OpenPort 내부 대기 + 여기 추가 대기 = 총 1.5~2.0s 수준 권장)
            Thread.Sleep(DETECT_WARMUP_MS);
            try { _sp.DiscardInBuffer(); } catch { }

            // --- 탐색 중에는 타임아웃을 크게 설정 ---
            _sp.ReadTimeout = DETECT_READ_TIMEOUT_MS;

            int probes = Mathf.Max(1, scanPerPortProbePackets);
            var deadline = Environment.TickCount + DETECT_FIND_START_MS;

            for (int attempt = 0; attempt < probes; attempt++)
            {
                // START 바이트를 전체 deadline까지 적극적으로 스캔
                int b;
                while (_run && Environment.TickCount < deadline)
                {
                    b = SafeReadByte(_sp);
                    if (b == START_BYTE) // 0xAA 발견
                    {
                        // 나머지 15B 수신 (탐색 타임아웃 사용)
                        byte[] buf = new byte[REM_AFTER_START];
                        if (!ReadExact(_sp, buf, 0, buf.Length, DETECT_READ_TIMEOUT_MS))
                            break; // 다음 attempt로

                        if (buf[14] != END_BYTE) break;

                        // 체크섬 검증 (12 analog bytes + BTN)
                        byte calcChk = 0;
                        for (int i = 0; i < 12; i++) calcChk += buf[i];
                        calcChk += buf[12];
                        if (calcChk != buf[13]) break;

                        // 유효 패킷 확인!
                        // 운영 루프로 넘어갈 땐 평소 타임아웃으로 복원
                        _sp.ReadTimeout = READ_TIMEOUT_MS;
                        return true;
                    }

                    // timeout으로 -1 왔을 수 있음: 루프 계속
                }

                // attempt 사이에 살짝 숨 고르기
                Thread.Sleep(10);
            }
        }
        catch
        {
            // 무시하고 false
        }
        return false;
    }


    private void SafeClosePort()
    {
        try { _sp?.Close(); } catch { }
        try { _sp?.Dispose(); } catch { }
        _sp = null;
        connectedPort = "";
    }

    // -------- IO Utils --------
    private static int SafeReadByte(SerialPort sp)
    {
        try { return sp.ReadByte(); }
        catch (TimeoutException) { return -1; }
        catch { return -1; }
    }

    private static bool ReadExact(SerialPort sp, byte[] buffer, int offset, int count, int perReadTimeoutMs)
    {
        int got = 0;
        while (got < count)
        {
            try
            {
                sp.ReadTimeout = perReadTimeoutMs;
                int n = sp.Read(buffer, offset + got, count - got);
                if (n <= 0) return false;
                got += n;
            }
            catch (TimeoutException)
            {
                return false;
            }
            catch
            {
                return false;
            }
        }
        return true;
    }
}
