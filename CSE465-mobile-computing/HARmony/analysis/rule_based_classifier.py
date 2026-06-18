import numpy as np

def classify_activity(feat):
    # --- 0. 핵심 지표 변수화 ---
    mag_std = feat["accel_mag_std"]
    gyro_mean = feat["gyro_mag_mean"]
    energy = feat["accel_mag_spectral_energy"]
    peak2 = feat["accel_mag_peak2_ratio"]
    entropy = feat["accel_mag_spectral_entropy"]
    corr_yz = feat["corr_accelY_accelZ"]
    corr_xy = feat["corr_accelX_accelY"]

    # --- 1. 기본 동작 상태 정의 ---
    is_walk_like = (0.08 < mag_std < 0.35) and (20 < energy < 380) and (gyro_mean < 1.6)
    is_su = (25 < energy < 170) and (peak2 < 0.85) and (corr_yz > 0.05)
    is_moon = (energy >= 115) and (peak2 > 0.30) and (entropy > 1.60) and \
              ((corr_yz < 0.10) or (corr_xy < -0.05))

    # --- 2. 순차적 판정 (Strict Sequential Flow) ---
    
    # [1] 정지 및 달리기
    if mag_std < 0.08 and gyro_mean < 0.25: return "Still"
    if mag_std > 0.38 and gyro_mean > 1.15: return "Running"
    
    # [2] 명확한 계단 신호 (Strong Presence)
    if corr_yz > 0.35 and 30 < energy < 150: return "Stairs Up"
    if corr_yz > 0.45 and energy > 220: return "Stairs Down"

    # [3] 문워크 판정 
    # (걷기 중이거나, 걷기 밖에서 계단 조건이 아닐 때만 moonwalk 인정)
    if is_moon and (is_walk_like or not is_su):
        return "Moonwalk"

    # [4] 계단 올라가기 판정 
    # (앞선 moonwalk 우선순위에 밀린 나머지 계단 상황 처리)
    if is_su:
        return "Stairs Up"

    # [5] 기본값
    return "Walk"