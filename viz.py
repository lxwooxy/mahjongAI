#!/usr/bin/env python3
"""
Visualize draw game patterns from Mahjong AI benchmark
"""

import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import numpy as np
from pathlib import Path
import sys

def load_data(csv_path):
    """Load the pattern overlap details CSV"""
    df = pd.read_csv(csv_path)
    # Convert progress to percentages if needed
    if df['player_progress'].max() <= 1.0:
        df['player_progress'] = df['player_progress'] * 100
        df['opponent_progress'] = df['opponent_progress'] * 100
    return df

def plot_progress_scatter(df, output_dir):
    """Scatter plot of P1 vs P2 progress at draw"""
    fig, ax = plt.subplots(figsize=(10, 10))
    
    # Create scatter plot
    scatter = ax.scatter(df['player_progress'], df['opponent_progress'], 
                        alpha=0.6, s=100, c=df['overlap_pct'], 
                        cmap='RdYlGn_r', edgecolors='black', linewidth=0.5)
    
    # Add diagonal line (equal progress)
    ax.plot([0, 100], [0, 100], 'k--', alpha=0.3, linewidth=2, label='Equal Progress')
    
    # Add reference lines
    ax.axhline(70, color='red', linestyle=':', alpha=0.3, label='70% threshold')
    ax.axvline(70, color='red', linestyle=':', alpha=0.3)
    
    # Formatting
    ax.set_xlabel('Player 1 Progress (%)', fontsize=14, fontweight='bold')
    ax.set_ylabel('Player 2 Progress (%)', fontsize=14, fontweight='bold')
    ax.set_title('Draw Game Outcomes: P1 vs P2 Progress\n(Color = Pattern Overlap %)', 
                 fontsize=16, fontweight='bold', pad=20)
    ax.set_xlim(0, 100)
    ax.set_ylim(0, 100)
    ax.grid(True, alpha=0.3)
    ax.legend(loc='upper left', fontsize=10)
    
    # Add colorbar
    cbar = plt.colorbar(scatter, ax=ax)
    cbar.set_label('Pattern Overlap (%)', fontsize=12, fontweight='bold')
    
    # Add quadrant labels
    ax.text(85, 15, 'P1 Ahead', fontsize=12, alpha=0.5, ha='center', 
            bbox=dict(boxstyle='round', facecolor='lightblue', alpha=0.3))
    ax.text(15, 85, 'P2 Ahead', fontsize=12, alpha=0.5, ha='center',
            bbox=dict(boxstyle='round', facecolor='lightcoral', alpha=0.3))
    ax.text(85, 85, 'Both High', fontsize=12, alpha=0.5, ha='center',
            bbox=dict(boxstyle='round', facecolor='lightgreen', alpha=0.3))
    ax.text(15, 15, 'Both Stuck', fontsize=12, alpha=0.5, ha='center',
            bbox=dict(boxstyle='round', facecolor='lightyellow', alpha=0.3))
    
    plt.tight_layout()
    plt.savefig(output_dir / 'draw_progress_scatter.png', dpi=300, bbox_inches='tight')
    print(f"✓ Saved: draw_progress_scatter.png")
    plt.close()

def plot_progress_difference_histogram(df, output_dir):
    """Histogram of progress differences"""
    df['progress_diff'] = df['player_progress'] - df['opponent_progress']
    
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 6))
    
    # Histogram
    ax1.hist(df['progress_diff'], bins=30, edgecolor='black', alpha=0.7, color='steelblue')
    ax1.axvline(0, color='red', linestyle='--', linewidth=2, label='Equal Progress')
    ax1.set_xlabel('Progress Difference (P1 - P2) (%)', fontsize=12, fontweight='bold')
    ax1.set_ylabel('Number of Draw Games', fontsize=12, fontweight='bold')
    ax1.set_title('Distribution of Progress Differences at Draw', fontsize=14, fontweight='bold')
    ax1.grid(True, alpha=0.3, axis='y')
    ax1.legend()
    
    # Add statistics text
    stats_text = f"Mean: {df['progress_diff'].mean():.1f}%\n"
    stats_text += f"Median: {df['progress_diff'].median():.1f}%\n"
    stats_text += f"Std Dev: {df['progress_diff'].std():.1f}%"
    ax1.text(0.02, 0.98, stats_text, transform=ax1.transAxes, 
             verticalalignment='top', fontsize=10,
             bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.5))
    
    # Box plot by matchup type
    df['matchup'] = df['p1_type'] + ' vs ' + df['p2_type']
    matchup_order = df.groupby('matchup')['progress_diff'].median().sort_values().index
    
    sns.boxplot(data=df, y='matchup', x='progress_diff', ax=ax2, 
                order=matchup_order, palette='Set2')
    ax2.axvline(0, color='red', linestyle='--', linewidth=2, alpha=0.5)
    ax2.set_xlabel('Progress Difference (P1 - P2) (%)', fontsize=12, fontweight='bold')
    ax2.set_ylabel('Player Matchup', fontsize=12, fontweight='bold')
    ax2.set_title('Progress Difference by Player Types', fontsize=14, fontweight='bold')
    ax2.grid(True, alpha=0.3, axis='x')
    
    plt.tight_layout()
    plt.savefig(output_dir / 'draw_progress_differences.png', dpi=300, bbox_inches='tight')
    print(f"✓ Saved: draw_progress_differences.png")
    plt.close()

def plot_progress_heatmap(df, output_dir):
    """2D histogram heatmap of draw outcomes"""
    fig, ax = plt.subplots(figsize=(12, 10))
    
    # Create 2D histogram
    x_bins = np.arange(0, 101, 10)
    y_bins = np.arange(0, 101, 10)
    
    hist, x_edges, y_edges = np.histogram2d(
        df['player_progress'], df['opponent_progress'], 
        bins=[x_bins, y_bins]
    )
    
    # Plot heatmap
    im = ax.imshow(hist.T, origin='lower', aspect='auto', 
                   cmap='YlOrRd', interpolation='nearest',
                   extent=[x_edges[0], x_edges[-1], y_edges[0], y_edges[-1]])
    
    # Add diagonal line
    ax.plot([0, 100], [0, 100], 'b--', alpha=0.5, linewidth=2, label='Equal Progress')
    
    # Add quadrant lines
    ax.axhline(70, color='blue', linestyle=':', alpha=0.3)
    ax.axvline(70, color='blue', linestyle=':', alpha=0.3)
    
    # Formatting
    ax.set_xlabel('Player 1 Progress (%)', fontsize=14, fontweight='bold')
    ax.set_ylabel('Player 2 Progress (%)', fontsize=14, fontweight='bold')
    ax.set_title('Heatmap of Draw Game Outcomes\n(Darker = More Games)', 
                 fontsize=16, fontweight='bold', pad=20)
    ax.legend(loc='upper left')
    
    # Colorbar
    cbar = plt.colorbar(im, ax=ax)
    cbar.set_label('Number of Draw Games', fontsize=12, fontweight='bold')
    
    # Add text annotations for counts in each cell
    for i in range(len(x_edges)-1):
        for j in range(len(y_edges)-1):
            count = int(hist[i, j])
            if count > 0:
                text_color = 'white' if count > hist.max()/2 else 'black'
                ax.text((x_edges[i] + x_edges[i+1])/2, 
                       (y_edges[j] + y_edges[j+1])/2,
                       str(count), ha='center', va='center', 
                       color=text_color, fontsize=8, fontweight='bold')
    
    plt.tight_layout()
    plt.savefig(output_dir / 'draw_progress_heatmap.png', dpi=300, bbox_inches='tight')
    print(f"✓ Saved: draw_progress_heatmap.png")
    plt.close()

def plot_progress_by_overlap(df, output_dir):
    """Box plots of progress by overlap category"""
    fig, axes = plt.subplots(2, 2, figsize=(16, 12))
    
    # P1 Progress by Overlap
    sns.boxplot(data=df, x='overlap_category', y='player_progress', ax=axes[0, 0],
                palette='viridis', order=['0-24%', '25-49%', '50-74%', '75-99%', '100% (Exact)'])
    axes[0, 0].set_title('Player 1 Progress by Pattern Overlap', fontsize=14, fontweight='bold')
    axes[0, 0].set_xlabel('Pattern Overlap Category', fontsize=12, fontweight='bold')
    axes[0, 0].set_ylabel('Progress (%)', fontsize=12, fontweight='bold')
    axes[0, 0].grid(True, alpha=0.3, axis='y')
    axes[0, 0].axhline(70, color='red', linestyle='--', alpha=0.3, label='70% threshold')
    axes[0, 0].legend()
    
    # P2 Progress by Overlap
    sns.boxplot(data=df, x='overlap_category', y='opponent_progress', ax=axes[0, 1],
                palette='viridis', order=['0-24%', '25-49%', '50-74%', '75-99%', '100% (Exact)'])
    axes[0, 1].set_title('Player 2 Progress by Pattern Overlap', fontsize=14, fontweight='bold')
    axes[0, 1].set_xlabel('Pattern Overlap Category', fontsize=12, fontweight='bold')
    axes[0, 1].set_ylabel('Progress (%)', fontsize=12, fontweight='bold')
    axes[0, 1].grid(True, alpha=0.3, axis='y')
    axes[0, 1].axhline(70, color='red', linestyle='--', alpha=0.3, label='70% threshold')
    axes[0, 1].legend()
    
    # Average progress by overlap
    overlap_stats = df.groupby('overlap_category').agg({
        'player_progress': 'mean',
        'opponent_progress': 'mean'
    }).reset_index()
    
    x_pos = np.arange(len(overlap_stats))
    width = 0.35
    
    axes[1, 0].bar(x_pos - width/2, overlap_stats['player_progress'], 
                   width, label='Player 1', alpha=0.8, color='steelblue')
    axes[1, 0].bar(x_pos + width/2, overlap_stats['opponent_progress'], 
                   width, label='Player 2', alpha=0.8, color='coral')
    axes[1, 0].set_xlabel('Pattern Overlap Category', fontsize=12, fontweight='bold')
    axes[1, 0].set_ylabel('Average Progress (%)', fontsize=12, fontweight='bold')
    axes[1, 0].set_title('Average Progress by Overlap Category', fontsize=14, fontweight='bold')
    axes[1, 0].set_xticks(x_pos)
    axes[1, 0].set_xticklabels(overlap_stats['overlap_category'], rotation=45, ha='right')
    axes[1, 0].legend()
    axes[1, 0].grid(True, alpha=0.3, axis='y')
    axes[1, 0].axhline(70, color='red', linestyle='--', alpha=0.3)
    
    # Overlap distribution
    overlap_counts = df['overlap_category'].value_counts()
    axes[1, 1].pie(overlap_counts, labels=overlap_counts.index, autopct='%1.1f%%',
                   startangle=90, colors=sns.color_palette('viridis', len(overlap_counts)))
    axes[1, 1].set_title('Distribution of Overlap Categories', fontsize=14, fontweight='bold')
    
    plt.tight_layout()
    plt.savefig(output_dir / 'draw_progress_by_overlap.png', dpi=300, bbox_inches='tight')
    print(f"✓ Saved: draw_progress_by_overlap.png")
    plt.close()

def plot_symmetric_analysis(df, output_dir):
    """Analyze symmetry of draw outcomes"""
    fig, axes = plt.subplots(2, 2, figsize=(16, 12))
    
    # Calculate asymmetry metric
    df['progress_sum'] = df['player_progress'] + df['opponent_progress']
    df['progress_diff_abs'] = abs(df['player_progress'] - df['opponent_progress'])
    
    # Scatter: sum vs difference
    scatter = axes[0, 0].scatter(df['progress_sum'], df['progress_diff_abs'], 
                                 alpha=0.6, s=80, c=df['overlap_pct'], 
                                 cmap='RdYlGn_r', edgecolors='black', linewidth=0.5)
    axes[0, 0].set_xlabel('Combined Progress (P1 + P2) (%)', fontsize=12, fontweight='bold')
    axes[0, 0].set_ylabel('Progress Asymmetry |P1 - P2| (%)', fontsize=12, fontweight='bold')
    axes[0, 0].set_title('Symmetry Analysis of Draw Games', fontsize=14, fontweight='bold')
    axes[0, 0].grid(True, alpha=0.3)
    axes[0, 0].axhline(20, color='red', linestyle='--', alpha=0.3, label='20% asymmetry')
    axes[0, 0].legend()
    cbar = plt.colorbar(scatter, ax=axes[0, 0])
    cbar.set_label('Overlap %', fontsize=10)
    
    # Histogram of combined progress
    axes[0, 1].hist(df['progress_sum'], bins=20, edgecolor='black', alpha=0.7, color='steelblue')
    axes[0, 1].set_xlabel('Combined Progress (P1 + P2) (%)', fontsize=12, fontweight='bold')
    axes[0, 1].set_ylabel('Number of Draw Games', fontsize=12, fontweight='bold')
    axes[0, 1].set_title('Distribution of Combined Progress', fontsize=14, fontweight='bold')
    axes[0, 1].grid(True, alpha=0.3, axis='y')
    axes[0, 1].axvline(140, color='red', linestyle='--', alpha=0.3, label='140% (both 70%)')
    axes[0, 1].legend()
    
    # Categorize draws
    df['draw_type'] = 'Unknown'
    df.loc[(df['player_progress'] < 50) & (df['opponent_progress'] < 50), 'draw_type'] = 'Both Stuck (<50%)'
    df.loc[(df['player_progress'] >= 50) & (df['player_progress'] < 70) & 
           (df['opponent_progress'] >= 50) & (df['opponent_progress'] < 70), 'draw_type'] = 'Both Mid (50-70%)'
    df.loc[(df['player_progress'] >= 70) & (df['opponent_progress'] >= 70), 'draw_type'] = 'Both High (≥70%)'
    df.loc[(df['player_progress'] >= 70) & (df['opponent_progress'] < 70), 'draw_type'] = 'P1 Ahead'
    df.loc[(df['player_progress'] < 70) & (df['opponent_progress'] >= 70), 'draw_type'] = 'P2 Ahead'
    
    draw_type_counts = df['draw_type'].value_counts()
    colors = ['#ff6b6b', '#feca57', '#48dbfb', '#1dd1a1', '#ee5a6f']
    axes[1, 0].barh(range(len(draw_type_counts)), draw_type_counts.values, color=colors[:len(draw_type_counts)])
    axes[1, 0].set_yticks(range(len(draw_type_counts)))
    axes[1, 0].set_yticklabels(draw_type_counts.index)
    axes[1, 0].set_xlabel('Number of Draw Games', fontsize=12, fontweight='bold')
    axes[1, 0].set_title('Draw Game Types', fontsize=14, fontweight='bold')
    axes[1, 0].grid(True, alpha=0.3, axis='x')
    
    # Add counts as text
    for i, v in enumerate(draw_type_counts.values):
        axes[1, 0].text(v + 0.5, i, str(v), va='center', fontweight='bold')
    
    # Pie chart of draw types
    axes[1, 1].pie(draw_type_counts, labels=draw_type_counts.index, autopct='%1.1f%%',
                   startangle=90, colors=colors[:len(draw_type_counts)])
    axes[1, 1].set_title('Proportion of Draw Types', fontsize=14, fontweight='bold')
    
    plt.tight_layout()
    plt.savefig(output_dir / 'draw_symmetry_analysis.png', dpi=300, bbox_inches='tight')
    print(f"✓ Saved: draw_symmetry_analysis.png")
    plt.close()

def generate_summary_stats(df, output_dir):
    """Generate text summary of statistics"""
    summary = []
    summary.append("="*80)
    summary.append("DRAW GAME ANALYSIS SUMMARY")
    summary.append("="*80)
    summary.append(f"\nTotal draw games analyzed: {len(df)}")
    summary.append(f"\nPlayer 1 Average Progress: {df['player_progress'].mean():.1f}%")
    summary.append(f"Player 1 Median Progress: {df['player_progress'].median():.1f}%")
    summary.append(f"Player 1 Std Dev: {df['player_progress'].std():.1f}%")
    summary.append(f"\nPlayer 2 Average Progress: {df['opponent_progress'].mean():.1f}%")
    summary.append(f"Player 2 Median Progress: {df['opponent_progress'].median():.1f}%")
    summary.append(f"Player 2 Std Dev: {df['opponent_progress'].std():.1f}%")
    
    summary.append(f"\nAverage Progress Difference: {abs(df['player_progress'] - df['opponent_progress']).mean():.1f}%")
    summary.append(f"Median Progress Difference: {abs(df['player_progress'] - df['opponent_progress']).median():.1f}%")
    
    summary.append(f"\nAverage Pattern Overlap: {df['overlap_pct'].mean():.1f}%")
    summary.append(f"Exact Pattern Matches: {(df['overlap_pct'] >= 100).sum()} ({(df['overlap_pct'] >= 100).sum()/len(df)*100:.1f}%)")
    
    summary.append(f"\nAverage Turns to Draw: {df['final_turn'].mean():.1f}")
    
    # Quadrant analysis
    both_high = ((df['player_progress'] >= 70) & (df['opponent_progress'] >= 70)).sum()
    both_stuck = ((df['player_progress'] < 70) & (df['opponent_progress'] < 70)).sum()
    p1_ahead = ((df['player_progress'] >= 70) & (df['opponent_progress'] < 70)).sum()
    p2_ahead = ((df['player_progress'] < 70) & (df['opponent_progress'] >= 70)).sum()
    
    summary.append(f"\nQuadrant Analysis:")
    summary.append(f"  Both High (≥70%): {both_high} ({both_high/len(df)*100:.1f}%)")
    summary.append(f"  Both Stuck (<70%): {both_stuck} ({both_stuck/len(df)*100:.1f}%)")
    summary.append(f"  P1 Ahead: {p1_ahead} ({p1_ahead/len(df)*100:.1f}%)")
    summary.append(f"  P2 Ahead: {p2_ahead} ({p2_ahead/len(df)*100:.1f}%)")
    
    summary.append("\n" + "="*80)
    
    summary_text = "\n".join(summary)
    print(summary_text)
    
    with open(output_dir / 'draw_analysis_summary.txt', 'w') as f:
        f.write(summary_text)
    print(f"\n✓ Saved: draw_analysis_summary.txt")

def main():
    # Set style
    sns.set_style("whitegrid")
    plt.rcParams['font.family'] = 'sans-serif'
    plt.rcParams['font.sans-serif'] = ['Arial']
    
    # Get CSV path from command line or use default
    if len(sys.argv) > 1:
        csv_path = Path(sys.argv[1])
    else:
        # Look for the most recent comparison_results directory
        result_dirs = sorted(Path('.').glob('comparison_results_*'))
        if not result_dirs:
            print("Error: No comparison_results directories found!")
            print("Usage: python visualize_draws.py [path/to/pattern_overlap_details.csv]")
            sys.exit(1)
        csv_path = result_dirs[-1] / 'pattern_overlap_details.csv'
    
    if not csv_path.exists():
        print(f"Error: CSV file not found: {csv_path}")
        sys.exit(1)
    
    print(f"\n{'='*80}")
    print(f"MAHJONG DRAW ANALYSIS VISUALIZER")
    print(f"{'='*80}")
    print(f"Loading data from: {csv_path}")
    
    # Load data
    df = load_data(csv_path)
    print(f"Loaded {len(df)} draw games\n")
    
    # Create output directory
    output_dir = csv_path.parent / 'visualizations'
    output_dir.mkdir(exist_ok=True)
    print(f"Output directory: {output_dir}\n")
    
    # Generate plots
    print("Generating visualizations...")
    plot_progress_scatter(df, output_dir)
    plot_progress_difference_histogram(df, output_dir)
    plot_progress_heatmap(df, output_dir)
    plot_progress_by_overlap(df, output_dir)
    plot_symmetric_analysis(df, output_dir)
    
    # Generate summary
    print("\nGenerating summary statistics...")
    generate_summary_stats(df, output_dir)
    
    print(f"\n{'='*80}")
    print(f"✅ All visualizations complete!")
    print(f"{'='*80}")
    print(f"Files saved to: {output_dir}/")
    print(f"  - draw_progress_scatter.png")
    print(f"  - draw_progress_differences.png")
    print(f"  - draw_progress_heatmap.png")
    print(f"  - draw_progress_by_overlap.png")
    print(f"  - draw_symmetry_analysis.png")
    print(f"  - draw_analysis_summary.txt")
    print(f"{'='*80}\n")

if __name__ == '__main__':
    main()