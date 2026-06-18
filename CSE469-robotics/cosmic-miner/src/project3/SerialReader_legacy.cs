using System;
using System.IO.Ports;
using System.Threading;
using UnityEngine;

public class SerialReader_legacy : MonoBehaviour
{
    [Header("Serial Settings")]
    public string portName = "";          // 비워두면 자동 탐색
    public int baudRate = 115200;
    public bool autoOpenOnStart = true;
    public bool autoReconnect = true;
    public bool autoDetectPort = true;    // true면 자동 탐색 사용
    public int portOpenResetWaitMs = 500; // Uno 자동리셋 대기
    public int scanPerPortProbePackets = 3; // 각 포트에서 최대 몇 개 패킷 검사할지

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

    void Update()
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

            // 몇 개 패킷을 검사하여 시그니처 일치 여부 판단
            int probes = Mathf.Max(1, scanPerPortProbePackets);
            for (int attempt = 0; attempt < probes; attempt++)
            {
                // START 탐색
                int wait = 40; // 소규모 루프 대기 (ms)
                var tEnd = Environment.TickCount + wait;
                int b;
                do
                {
                    b = SafeReadByte(_sp);
                    if (b == START_BYTE) break;
                } while (_run && Environment.TickCount < tEnd);

                if (b != START_BYTE) continue;

                // 나머지 15B 수신
                byte[] buf = new byte[REM_AFTER_START];
                if (!ReadExact(_sp, buf, 0, buf.Length, READ_TIMEOUT_MS))
                    continue;

                if (buf[14] != END_BYTE) continue;

                byte calcChk = 0;
                for (int i = 0; i < 12; i++) calcChk += buf[i];
                calcChk += buf[12];
                if (calcChk != buf[13]) continue;

                // 하나라도 유효하면 성공
                return true;
            }
        }
        catch
        {
            // 무시하고 false 반환
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
