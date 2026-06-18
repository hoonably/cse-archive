import pandas as pd
import numpy as np

def preprocess_test_data(input_path, output_path):
    print(f"--- Loading {input_path} ---")
    df = pd.read_csv(input_path)
    
    fixed_dfs = []
    target_hz = 50
    target_seconds = 30
    target_samples = target_hz * target_seconds # 1500
    
    for label in df['label'].unique():
        label_df = df[df['label'] == label].copy()
        
        # [1] 시간축 초기화 
        # 계단처럼 중복된 시간이나 불규칙한 Hz가 섞여 있으므로, 
        # 모든 데이터를 순서대로 나열한 뒤 0~30초 범위에 고르게 분포시킵니다.
        n_samples = len(label_df)
        print(f"Processing [{label}]: Original samples = {n_samples}")
        
        # 실제 데이터의 순서를 유지하며 시간축을 0~30s로 재부여
        label_df = label_df.sort_index().reset_index(drop=True)
        # 현재 있는 샘플들을 0초부터 마지막 시간까지 균등하게 배치 (가속도/자원 값 보존용)
        label_df['timestamp'] = np.linspace(0, target_seconds, n_samples)
        
        # [2] 50Hz로 선형 보간 (Resampling)
        # 0.02, 0.04 ... 30.00 까지의 새로운 타임스태프 생성
        new_timestamps = np.linspace(0, target_seconds, target_samples)
        
        resampled_df = pd.DataFrame({'timestamp': new_timestamps})
        resampled_df['label'] = label
        
        # 각 축 데이터 보간
        for col in ['accelX', 'accelY', 'accelZ', 'gyroX', 'gyroY', 'gyroZ']:
            resampled_df[col] = np.interp(new_timestamps, label_df['timestamp'], label_df[col])
            
        fixed_dfs.append(resampled_df)
        print(f"  -> Fixed to {len(resampled_df)} samples (Exactly {target_hz}Hz, {target_seconds}s)")

    # 모든 라벨 합치기
    final_df = pd.concat(fixed_dfs, ignore_index=True)
    final_df.to_csv(output_path, index=False)
    print(f"\n--- Success! Saved to {output_path} ---")

if __name__ == "__main__":
    preprocess_test_data('data/test.csv', 'data/test_fixed.csv')
