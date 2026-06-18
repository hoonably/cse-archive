import pandas as pd
import numpy as np
import os
import matplotlib.pyplot as plt
import seaborn as sns
from sklearn.metrics import accuracy_score, confusion_matrix, classification_report
from scipy.stats import trim_mean

# 1. Load Rule-Based Classifier
import rule_based_classifier as rbc

if __name__ == "__main__":
    # [수정] 상세 데이터 소스 폴더 변경
    expanded_dir = 'expanded_features'
    output_dir = 'results'
    if not os.path.exists(output_dir): os.makedirs(output_dir)
    
    labels = ['Still', 'Walk', 'Running', 'Stairs Up', 'Stairs Down', 'Moonwalk']
    performance_log = []
    best_overall_acc = -1
    best_window_size = "0.5"
    best_df = None

    print(f"📊 Analyzing performance from '{expanded_dir}'...")
    
    # 0.5초 ~ 5.0초 범위를 0.1초 단위로 탐색 (5.1은 미포함)
    found_files = 0
    for w in np.arange(0.5, 5.1, 0.1):
        w_str = f'{w:.1f}'
        # [수정] 경로 업데이트
        file_path = os.path.join(expanded_dir, f'features_{w_str}s_expanded.csv')
        
        if os.path.exists(file_path):
            found_files += 1
            df = pd.read_csv(file_path)
            
            # Apply your latest classifier rules
            predictions = df.apply(lambda row: rbc.classify_activity(row), axis=1)
            
            # Calculate accuracy
            acc = accuracy_score(df['label'], predictions)
            performance_log.append({'window_size': w, 'accuracy': acc})
            
            print(f"  > Window {w_str}s: Accuracy = {acc:.4f} (Samples: {len(df)})")
            
            if acc > best_overall_acc:
                best_overall_acc = acc
                best_window_size = w_str
                best_df = df.copy()
                best_df['prediction'] = predictions

    # --- SAFETY CHECK ---
    if found_files == 0:
        print("\n" + "!"*60)
        print(f"⚠️ ERROR: No detailed feature files found in '{expanded_dir}/'.")
        print("💡 PLEASE RUN 'python3 feature_extraction.py' FIRST.")
        print("!"*60 + "\n")
        exit(1)

    # 2. Accuracy Plot
    perf_df = pd.DataFrame(performance_log).round(4) # [수정] 소수점 4자리 반올림
    perf_df.to_csv(os.path.join(output_dir, 'fixed_window_performance.csv'), index=False)
    plt.figure(figsize=(10, 6))
    plt.plot(perf_df['window_size'], perf_df['accuracy'], marker='o', color='#2E86C1', lw=3, ms=10)
    plt.title('Accuracy by Window Size (High-Density Samples)', fontsize=22, pad=20, fontweight='bold')
    plt.xlabel('Window Size (s)', fontsize=18, fontweight='bold', labelpad=10)
    plt.ylabel('Accuracy', fontsize=18, fontweight='bold', labelpad=10)
    plt.xticks(fontsize=16)
    plt.yticks(fontsize=16)
    plt.grid(True, alpha=0.3, ls='--')
    plt.savefig(os.path.join(output_dir, 'accuracy_trend_plot.png'), dpi=300, bbox_inches='tight')
    plt.savefig(os.path.join(output_dir, 'accuracy_trend_plot.pdf'), bbox_inches='tight')
    plt.close()

    # 3. Best Result Analysis
    if best_df is not None:
        # --- NEW: Specific analysis for 1.8s window (User Request) ---
        target_w = "1.8"
        target_file = os.path.join(expanded_dir, f'features_{target_w}s_expanded.csv')
        if os.path.exists(target_file):
            t_df = pd.read_csv(target_file)
            t_preds = t_df.apply(lambda row: rbc.classify_activity(row), axis=1)
            t_acc = accuracy_score(t_df['label'], t_preds)
            
            print("\n" + "-"*50)
            print(f"📊 SPECIFIC ANALYSIS: {target_w}s Window (Current App Version)")
            print(f"Accuracy: {t_acc:.4f}")
            print("-"*50)
            print(classification_report(t_df['label'], t_preds, labels=labels, zero_division=0))
            
            # Save 1.8s Confusion Matrix
            t_cm = confusion_matrix(t_df['label'], t_preds, labels=labels)
            plt.figure(figsize=(10, 8))
            ax = sns.heatmap(t_cm, annot=True, fmt='d', xticklabels=labels, yticklabels=labels, cmap='Blues', annot_kws={"size": 16, "weight": "bold"})
            plt.title(f'Confusion Matrix (Window: {target_w}s)\nAccuracy = {t_acc:.4f}', fontsize=24, pad=25, fontweight='bold')
            plt.xlabel('Predicted Activity', fontsize=18, fontweight='bold', labelpad=15)
            plt.ylabel('Actual Activity (Ground Truth)', fontsize=18, fontweight='bold', labelpad=15)
            plt.xticks(fontsize=15)
            plt.yticks(fontsize=15)
            plt.savefig(os.path.join(output_dir, f'fixed_{target_w}s_window_confusion_matrix.png'), dpi=300, bbox_inches='tight')
            plt.savefig(os.path.join(output_dir, f'fixed_{target_w}s_window_confusion_matrix.pdf'), bbox_inches='tight')
            plt.close()

        # Robust Signature for BEST window
        summary_df = best_df.groupby('label').apply(
            lambda x: x.select_dtypes(include=[np.number]).apply(lambda col: trim_mean(col, 0.05))
        )
        summary_df.index.name = 'label'
        summary_df = summary_df.reindex([L for L in labels if L in summary_df.index])
        to_drop = [c for c in ['window_id', 'trial_id', 'Unnamed: 0'] if c in summary_df.columns]
        summary_df.drop(columns=to_drop).to_csv(os.path.join(output_dir, 'label_feature_summary.csv'))

        print("\n" + "="*50)
        print(f"🥇 BEST FIXED WINDOW: {best_window_size}s (Acc: {best_overall_acc:.4f})")
        print("="*50)
        print(classification_report(best_df['label'], best_df['prediction'], labels=labels, zero_division=0))

        # Confusion Matrix
        cm = confusion_matrix(best_df['label'], best_df['prediction'], labels=labels)
        plt.figure(figsize=(10, 8))
        ax = sns.heatmap(cm, annot=True, fmt='d', xticklabels=labels, yticklabels=labels, cmap='Greens', annot_kws={"size": 16, "weight": "bold"})
        plt.title(f'Confusion Matrix (Window: {best_window_size}s)\nAccuracy = {best_overall_acc:.4f}', fontsize=24, pad=25, fontweight='bold')
        plt.xlabel('Predicted Activity', fontsize=18, fontweight='bold', labelpad=15)
        plt.ylabel('Actual Activity (Ground Truth)', fontsize=18, fontweight='bold', labelpad=15)
        plt.xticks(fontsize=15)
        plt.yticks(fontsize=15)
        plt.savefig(os.path.join(output_dir, 'best_fixed_window_confusion_matrix.png'), dpi=300, bbox_inches='tight')
        plt.savefig(os.path.join(output_dir, 'best_fixed_window_confusion_matrix.pdf'), bbox_inches='tight')
        plt.close()

    print(f"\n✅ All analysis completed correctly using samples from '{expanded_dir}/'.")
