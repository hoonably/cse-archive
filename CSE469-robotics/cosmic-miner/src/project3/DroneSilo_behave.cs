using UnityEngine;
using System.Collections.Generic;

public class DroneSilo_behave : MonoBehaviour
{
    public Transform spawnPoint;

    public float RetreiveRange;
    public int droneNo; // 이 사일로에서 몇 마리를 뽑을지 (보통 1이겠죠?)
    public GameObject dronePrefab;
    public List<GameObject> droneList;

    // [핵심 수정] 모든 사일로가 공유하는 전역 번호표 발행기
    // static이 붙으면 사일로가 여러 개여도 이 변수는 딱 하나만 존재합니다.
    public static int globalDroneIndex = 0; 

    // 게임 시작할 때마다 번호표 초기화 (재시작 시 0번부터 다시 뽑기 위함)
    [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.SubsystemRegistration)]
    static void ResetCounter()
    {
        globalDroneIndex = 0;
    }

    void Start()
    {
        droneList = new List<GameObject>();
        
        // 이 사일로에 할당된 수만큼 생성
        for(int i = 0; i < droneNo; i++)
        {
            if (dronePrefab == null) break;
            
            // 1. 드론 생성
            GameObject newDrone = Instantiate(dronePrefab, spawnPoint.position, Quaternion.identity);
            
            // 2. [수정] 지역변수 i 대신, 전역변수 globalDroneIndex 사용
            int currentID = globalDroneIndex; 
            globalDroneIndex++; // 번호표 한 장 썼으니 다음 번호로 증가 (0 -> 1 -> 2)

            newDrone.name = $"Drone_{currentID}"; 
            droneList.Add(newDrone);
            newDrone.SetActive(false);
            
            // 3. 컴포넌트 찾아서 번호 부여
            DroneControlUnit dcu = newDrone.GetComponentInChildren<DroneControlUnit>();
            if (dcu != null)
            {
                dcu.droneInd = currentID; // 0, 1, 2가 순차적으로 들어감
                Debug.Log($"[Silo] {newDrone.name}에게 전역 번호 {currentID}번 부여 완료");
            }
        }
    }

    public void SpawnDrone(int callNo)
    {
        // callNo는 리스트 인덱스이므로 그대로 사용 (0번째 소환)
        if (callNo < droneList.Count && !droneList[callNo].activeSelf)
        {
            droneList[callNo].transform.position = spawnPoint.position;
            droneList[callNo].transform.rotation = spawnPoint.rotation;

            droneList[callNo].SetActive(true);
            LIDAR_behave[] droneLIDAR = droneList[callNo].GetComponentsInChildren<LIDAR_behave>();
            foreach (LIDAR_behave i in droneLIDAR)
            {
                if (FogOfWarPersistent2.Instance != null)
                {
                     FogOfWarPersistent2.Instance.targets.Add(i.transform);
                }
            }
        }
    }

    public void RetreiveDrone()
    {
        for(int i = 0; i < droneList.Count; i++)
        {
            if(Vector3.Distance(droneList[i].transform.position, spawnPoint.position) < RetreiveRange)
            {
                droneList[i].SetActive(false);
                if (FogOfWarPersistent2.Instance != null && FogOfWarPersistent2.Instance.targets.Contains(droneList[i].transform))
                {
                    FogOfWarPersistent2.Instance.targets.Remove(droneList[i].transform);
                }
            }
        }
    }
}