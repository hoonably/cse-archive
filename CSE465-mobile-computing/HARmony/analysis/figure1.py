import pandas as pd
import matplotlib.pyplot as plt
from pathlib import Path

CSV_PATH = "data/test_fixed.csv"   # 네 파일명으로 수정
OUT_DIR = Path("report_figures")
OUT_DIR.mkdir(exist_ok=True)

def split_into_trials(df):
    df = df.copy()
    boundary = (df["label"] != df["label"].shift()) | (df["timestamp"].diff() < 0)
    df["trial_id"] = boundary.cumsum()
    return df

def get_first_trial(df, activity, duration_sec=3.0):
    sub = df[df["label"] == activity].copy()
    if sub.empty:
        raise ValueError(f"No samples found for activity: {activity}")
    sub = split_into_trials(sub)
    first_trial_id = sub["trial_id"].iloc[0]
    trial = sub[sub["trial_id"] == first_trial_id].copy()
    t0 = trial["timestamp"].iloc[0]
    trial["t_rel"] = trial["timestamp"] - t0
    return trial[trial["t_rel"] <= duration_sec]

def plot_group(df, activities, filename, duration_sec=3.0):
    fig, axes = plt.subplots(len(activities), 2, figsize=(10, 2.8 * len(activities)), sharex=False)

    if len(activities) == 1:
        axes = [axes]

    for i, activity in enumerate(activities):
        trial = get_first_trial(df, activity, duration_sec=duration_sec)

        ax1, ax2 = axes[i]

        # Accelerometer
        ax1.plot(trial["t_rel"], trial["accelX"], label="X")
        ax1.plot(trial["t_rel"], trial["accelY"], label="Y")
        ax1.plot(trial["t_rel"], trial["accelZ"], label="Z")
        ax1.set_title(f"{activity} - Accelerometer")
        ax1.set_xlabel("Time (s)")
        ax1.set_ylabel("Acceleration (G)")
        ax1.grid(True, alpha=0.3)
        ax1.legend(fontsize=8, loc="upper right")

        # Gyroscope
        ax2.plot(trial["t_rel"], trial["gyroX"], label="X")
        ax2.plot(trial["t_rel"], trial["gyroY"], label="Y")
        ax2.plot(trial["t_rel"], trial["gyroZ"], label="Z")
        ax2.set_title(f"{activity} - Gyroscope")
        ax2.set_xlabel("Time (s)")
        ax2.set_ylabel("Angular Velocity (rad/s)")
        ax2.grid(True, alpha=0.3)
        ax2.legend(fontsize=8, loc="upper right")

    plt.tight_layout()
    out_path_png = OUT_DIR / filename
    out_path_pdf = OUT_DIR / filename.replace(".png", ".pdf")
    
    plt.savefig(out_path_png, dpi=300, bbox_inches="tight")
    plt.savefig(out_path_pdf, bbox_inches="tight")
    plt.close()
    print(f"Saved: {out_path_png} & {out_path_pdf}")

if __name__ == "__main__":
    df = pd.read_csv(CSV_PATH)

    plot_group(
        df,
        activities=["Still", "Walk", "Running"],
        filename="raw_signals_group1.png",
        duration_sec=3.0
    )

    plot_group(
        df,
        activities=["Stairs Up", "Stairs Down", "Moonwalk"],
        filename="raw_signals_group2.png",
        duration_sec=3.0
    )

    plot_group(
        df,
        activities=["Still", "Walk", "Running", "Stairs Up", "Stairs Down", "Moonwalk"],
        filename="raw_signals_all_activities.png",
        duration_sec=2.5
    )