import pandas as pd
import numpy as np
import os
from scipy.stats import skew, kurtosis, trim_mean
from scipy.fft import fft

# --- Utility Functions ---
def safe_divide(n, d):
    return n / d if d != 0 else 0

def extract_features(window, label, trial_id, window_id):
    ax, ay, az = window['accelX'].values, window['accelY'].values, window['accelZ'].values
    gx, gy, gz = window['gyroX'].values, window['gyroY'].values, window['gyroZ'].values
    a_mag = np.sqrt(ax**2 + ay**2 + az**2)
    g_mag = np.sqrt(gx**2 + gy**2 + gz**2)
    
    feats = {'label': label, 'trial_id': trial_id, 'window_id': window_id}
    for name, sig in [('accel_mag', a_mag), ('gyro_mag', g_mag), ('accelZ', az)]:
        feats[f'{name}_mean'] = np.mean(sig)
        feats[f'{name}_std'] = np.std(sig)
        feats[f'{name}_rms'] = np.sqrt(np.mean(sig**2))
        feats[f'{name}_p50'] = np.percentile(sig, 50)
        feats[f'{name}_skew'] = skew(sig)
        feats[f'{name}_kurt'] = kurtosis(sig)

    n = len(a_mag)
    if n > 1:
        yf = fft(a_mag - np.mean(a_mag))
        psd = np.abs(yf[:n//2])**2
        freqs = np.fft.fftfreq(n, 1/50)[:n//2]
        feats['accel_mag_dom_freq'] = freqs[np.argmax(psd)] if len(psd) > 0 else 0
        feats['accel_mag_spectral_energy'] = np.sum(psd)
        psd_norm = psd / (np.sum(psd) + 1e-9)
        feats['accel_mag_spectral_entropy'] = -np.sum(psd_norm * np.log(psd_norm + 1e-9))
        if len(psd) > 1:
            sorted_psd = np.sort(psd)
            feats['accel_mag_peak2_ratio'] = safe_divide(sorted_psd[-2], sorted_psd[-1])
        else: feats['accel_mag_peak2_ratio'] = 0
    else: 
        feats['accel_mag_dom_freq'] = feats['accel_mag_spectral_energy'] = feats['accel_mag_spectral_entropy'] = feats['accel_mag_peak2_ratio'] = 0

    feats['corr_accelY_accelZ'] = np.corrcoef(ay, az)[0, 1] if np.std(ay) > 0 and np.std(az) > 0 else 0
    feats['corr_accelX_accelY'] = np.corrcoef(ax, ay)[0, 1] if np.std(ax) > 0 and np.std(ay) > 0 else 0
    return feats

def split_into_trials(df):
    df = df.copy()
    boundary = (df['label'] != df['label'].shift()) | (df['timestamp'].diff() < 0)
    df['trial_id'] = boundary.cumsum()
    return df

if __name__ == "__main__":
    raw_data_path = 'data/test_fixed.csv'
    summary_dir = 'processed_features'
    expanded_dir = 'expanded_features' # [수정] 폴더 분리
    
    for d in [summary_dir, expanded_dir]:
        if not os.path.exists(d): os.makedirs(d)
    
    if os.path.exists(raw_data_path):
        df = pd.read_csv(raw_data_path)
        df_trialed = split_into_trials(df)
        # [MODIFY ME] 윈도우 크기 분석    # 0.5초 ~ 5.0초 범위를 0.1초 단위로 탐색 (5.1은 미포함)
        window_sizes = np.arange(0.5, 5.1, 0.1)
        
        for w_sec in window_sizes:
            samples = int(w_sec * 50)
            step = 1 # 0.1s sliding
            print(f"⚙️ Process: {w_sec:.1f}s")
            
            all_features = []
            for _, trial_df in df_trialed.groupby('trial_id'):
                n = len(trial_df)
                label = trial_df['label'].iloc[0]
                tid = trial_df['trial_id'].iloc[0]
                for start in range(0, n - samples + 1, step):
                    w_slice = trial_df.iloc[start : start + samples]
                    all_features.append(extract_features(w_slice, label, tid, start//step))
            
            df_features = pd.DataFrame(all_features)
            
            # [1] 상세 데이터 저장 (폴더: expanded_features)
            exp_path = os.path.join(expanded_dir, f'features_{w_sec:.1f}s_expanded.csv')
            df_features.to_csv(exp_path, index=False)
            
            # [2] 요약본 저장 (폴더: processed_features)
            summary_df = df_features.groupby('label').apply(
                lambda x: x.select_dtypes(include=[np.number]).apply(lambda col: trim_mean(col, 0.05))
            )
            summary_df.index.name = 'label'
            ordered = ['Still', 'Walk', 'Running', 'Stairs Up', 'Stairs Down', 'Moonwalk']
            summary_df = summary_df.reindex([L for L in ordered if L in summary_df.index])
            sum_path = os.path.join(summary_dir, f'features_{w_sec:.1f}s.csv')
            summary_df.drop(columns=[c for c in ['window_id', 'trial_id'] if c in summary_df.columns], errors='ignore').to_csv(sum_path)

        print(f"\n✅ All extractions complete.")
