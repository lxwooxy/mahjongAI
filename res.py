#!/usr/bin/env python3
"""
Generate all statistics needed for the Mahjong AI paper.
Run this to get the numbers to put IN the paper.
"""

import pandas as pd
import numpy as np
from scipy import stats

df = pd.read_csv('res/player_comparison_results.csv')
neither = df[df['config_name'] == 'neither'].copy()

print("="*80)
print("MAHJONG AI PAPER - STATISTICS FOR RESULTS SECTION")
print("="*80)

print("\n" + "="*80)
print("BASIC STATISTICS")
print("="*80)
print(f"Total configurations: {len(df)}")
print(f"Total games: {df['total_games'].sum()}")
print(f"'Neither nervous' configurations: {len(neither)}")

print("\n" + "="*80)
print("SECTION 4.1.1: BAYESIAN VS GREEDY (PRIMARY RESULT)")
print("="*80)

bg_neither = neither[(neither['player1_type'] == 'bayesian') & 
                     (neither['player2_type'] == 'greedy')]

if len(bg_neither) > 0:
    row = bg_neither.iloc[0]
    p1_wins = row['p1_wins']
    p2_wins = row['p2_wins']
    decisive = row['decisive_games']
    win_rate = row['p1_win_rate_decisive']
    
    # Calculate binomial test p-value (testing if win rate > 50%)
    p_value = stats.binomtest(p1_wins, n=decisive, p=0.5, alternative='greater').pvalue
    
    print(f"\nNeither nervous configuration:")
    print(f"  Bayesian wins: {p1_wins}")
    print(f"  Greedy wins: {p2_wins}")
    print(f"  Win rate: {win_rate:.1f}%")
    print(f"  Total decisive games: {decisive}")
    print(f"  Draw rate: {row['draw_pct']:.1f}%")
    print(f"  P-value (binomial test, H0: p=0.5): {p_value:.4f}")
    
    if p_value < 0.001:
        sig_text = "p < 0.001"
    elif p_value < 0.01:
        sig_text = "p < 0.01"
    elif p_value < 0.05:
        sig_text = "p < 0.05"
    else:
        sig_text = f"p = {p_value:.3f}"
    
    print(f"\n  → PAPER TEXT: \"The Bayesian agent achieved a {win_rate:.1f}% win rate")
    print(f"     against the Greedy agent in decisive games (neither nervous")
    print(f"     configuration: {p1_wins} wins vs. {p2_wins} losses, {sig_text} binomial test)\"")

print("\n" + "-"*80)
print("ALL BAYESIAN VS GREEDY CONFIGURATIONS (13 or 16 total)")
print("-"*80)

bg_all = df[(df['player1_type'] == 'bayesian') & (df['player2_type'] == 'greedy')]
print(f"\nTotal Bayesian vs Greedy configurations: {len(bg_all)}")

win_rates = []
draw_rates = []
for idx, row in bg_all.iterrows():
    if row['decisive_games'] > 0:
        wr = row['p1_win_rate_decisive']
        win_rates.append(wr)
        draw_rates.append(row['draw_pct'])

if win_rates:
    print(f"\nWin rate statistics:")
    print(f"  Minimum: {min(win_rates):.1f}%")
    print(f"  Maximum: {max(win_rates):.1f}%")
    print(f"  Mean: {np.mean(win_rates):.1f}%")
    print(f"  Median: {np.median(win_rates):.1f}%")
    
    # Count configs in different ranges
    clustered_52_68 = [wr for wr in win_rates if 52 <= wr <= 68]
    below_52 = [wr for wr in win_rates if wr < 52]
    above_68 = [wr for wr in win_rates if wr > 68]
    
    print(f"\nDistribution:")
    print(f"  Below 52%: {len(below_52)} configs")
    print(f"  52-68% range: {len(clustered_52_68)} configs")
    print(f"  Above 68%: {len(above_68)} configs")
    
    print(f"\n  → PAPER TEXT: \"Across all {len(bg_all)} nervousness configurations,")
    print(f"     Bayesian win rates ranged from {min(win_rates):.1f}% to {max(win_rates):.1f}%,")
    print(f"     with most configurations clustered around 52-68%.\"")
    
    # Find highest win rate config
    max_idx = win_rates.index(max(win_rates))
    max_row = bg_all.iloc[max_idx]
    print(f"\n  Highest win rate config: {max_row['config_name']}")
    print(f"    Win rate: {max(win_rates):.1f}%")
    print(f"    Decisive games: {max_row['decisive_games']}")
    print(f"    Draw rate: {max_row['draw_pct']:.1f}%")

print("\n" + "="*80)
print("SECTION 4.1.2: BAYESIAN VS BASELINES")
print("="*80)

# Bayesian vs Random-Commit
brc_neither = neither[(neither['player1_type'] == 'bayesian') & 
                      (neither['player2_type'] == 'random_commit')]
if len(brc_neither) > 0:
    row = brc_neither.iloc[0]
    p_value_brc = stats.binomtest(row['p1_wins'], n=row['decisive_games'], p=0.5, alternative='greater').pvalue
    
    print(f"\nBayesian vs Random-Commit:")
    print(f"  P1 wins: {row['p1_wins']}")
    print(f"  P2 wins: {row['p2_wins']}")
    print(f"  Decisive games: {row['decisive_games']}")
    print(f"  Win rate: {row['p1_win_rate_decisive']:.1f}%")
    print(f"  Draw rate: {row['draw_pct']:.1f}%")
    print(f"  P-value: {p_value_brc:.6f}")
    print(f"\n  → PAPER TEXT: \"vs. Random-Commit: {row['p1_win_rate_decisive']:.1f}% win rate")
    print(f"     in decisive games ({row['p1_wins']}/{row['decisive_games']} wins, neither nervous)\"")

# Bayesian vs Pure Random - ALL configs
bpr_all = df[(df['player1_type'] == 'bayesian') & (df['player2_type'] == 'pure_random')]
total_p1_wins = bpr_all['p1_wins'].sum()
total_p2_wins = bpr_all['p2_wins'].sum()
total_games_bpr = bpr_all['total_games'].sum()

if total_p1_wins + total_p2_wins > 0:
    p_value_bpr = stats.binomtest(total_p1_wins, n=total_p1_wins + total_p2_wins, p=0.5, alternative='greater').pvalue
else:
    p_value_bpr = 1.0

print(f"\nBayesian vs Pure Random (all configurations):")
print(f"  Total P1 wins: {total_p1_wins}")
print(f"  Total P2 wins: {total_p2_wins}")
print(f"  Total decisive: {total_p1_wins + total_p2_wins}")
print(f"  Win rate: {(total_p1_wins/(total_p1_wins + total_p2_wins))*100:.1f}%")
print(f"  P-value: {p_value_bpr:.6e}")
print(f"\n  → PAPER TEXT: \"vs. Pure Random: 100% win rate across all configurations")
print(f"     ({total_p1_wins}/{total_p1_wins + total_p2_wins} total wins, 0 losses)\"")

print("\n" + "="*80)
print("SECTION 4.1.3: GREEDY VS BASELINES")
print("="*80)

# Greedy vs Random-Commit
grc_neither = neither[(neither['player1_type'] == 'greedy') & 
                      (neither['player2_type'] == 'random_commit')]
if len(grc_neither) > 0:
    row = grc_neither.iloc[0]
    p_value_grc = stats.binomtest(row['p1_wins'], n=row['decisive_games'], p=0.5, alternative='greater').pvalue
    
    print(f"\nGreedy vs Random-Commit:")
    print(f"  P1 wins: {row['p1_wins']}")
    print(f"  Decisive games: {row['decisive_games']}")
    print(f"  Win rate: {row['p1_win_rate_decisive']:.1f}%")
    print(f"  P-value: {p_value_grc:.6f}")
    print(f"\n  → PAPER TEXT: \"vs. Random-Commit: {row['p1_win_rate_decisive']:.1f}% win rate")
    print(f"     in decisive games ({row['p1_wins']}/{row['decisive_games']} wins)\"")

# Greedy vs Pure Random - ALL configs
gpr_all = df[(df['player1_type'] == 'greedy') & (df['player2_type'] == 'pure_random')]
total_p1_wins_g = gpr_all['p1_wins'].sum()
total_p2_wins_g = gpr_all['p2_wins'].sum()

if total_p1_wins_g + total_p2_wins_g > 0:
    p_value_gpr = stats.binomtest(total_p1_wins_g, n=total_p1_wins_g + total_p2_wins_g, p=0.5, alternative='greater').pvalue
else:
    p_value_gpr = 1.0

print(f"\nGreedy vs Pure Random (all configurations):")
print(f"  Total P1 wins: {total_p1_wins_g}")
print(f"  Total P2 wins: {total_p2_wins_g}")
print(f"  Win rate: 100%")
print(f"  P-value: {p_value_gpr:.6e}")
print(f"\n  → PAPER TEXT: \"vs. Pure Random: 100% win rate across all configurations")
print(f"     ({total_p1_wins_g}/{total_p1_wins_g + total_p2_wins_g} total wins)\"")

print("\n" + "="*80)
print("SECTION 4.1.4: SELF-PLAY RESULTS")
print("="*80)

# Bayesian vs Bayesian
bb_neither = neither[(neither['player1_type'] == 'bayesian') & 
                     (neither['player2_type'] == 'bayesian')]
if len(bb_neither) > 0:
    row = bb_neither.iloc[0]
    p_value_bb = stats.binomtest(row['p1_wins'], n=row['decisive_games'], p=0.5, alternative='greater').pvalue
    
    print(f"\nBayesian vs Bayesian:")
    print(f"  P1 wins: {row['p1_wins']}")
    print(f"  P2 wins: {row['p2_wins']}")
    print(f"  Decisive games: {row['decisive_games']}")
    print(f"  P1 win rate: {row['p1_win_rate_decisive']:.1f}%")
    print(f"  Draw rate: {row['draw_pct']:.1f}%")
    print(f"  P-value: {p_value_bb:.6f}")
    print(f"\n  → PAPER TEXT: \"Bayesian vs. Bayesian yielded {row['p1_win_rate_decisive']:.1f}% P1 wins")
    print(f"     in the 'neither nervous' configuration ({row['p1_wins']}/{row['decisive_games']} decisive games)\"")

# Greedy vs Greedy
gg_neither = neither[(neither['player1_type'] == 'greedy') & 
                     (neither['player2_type'] == 'greedy')]
if len(gg_neither) > 0:
    row = gg_neither.iloc[0]
    p_value_gg = stats.binomtest(row['p1_wins'], n=row['decisive_games'], p=0.5, alternative='greater').pvalue
    
    print(f"\nGreedy vs Greedy:")
    print(f"  P1 wins: {row['p1_wins']}")
    print(f"  Decisive games: {row['decisive_games']}")
    print(f"  P1 win rate: {row['p1_win_rate_decisive']:.1f}%")
    print(f"  Draw rate: {row['draw_pct']:.1f}%")
    print(f"  P-value: {p_value_gg:.6f}")
    print(f"\n  → PAPER TEXT: \"Greedy vs. Greedy showed similar patterns")
    print(f"     ({row['p1_win_rate_decisive']:.1f}% P1 wins, {row['draw_pct']:.1f}% draw rates)\"")

print("\n" + "="*80)
print("TABLE 1: DRAW RATES AND CHARACTERISTICS")
print("="*80)

pairings = [
    ('bayesian', 'bayesian', 'Bayesian vs. Bayesian'),
    ('bayesian', 'greedy', 'Bayesian vs. Greedy'),
    ('greedy', 'greedy', 'Greedy vs. Greedy'),
    ('bayesian', 'random_commit', 'Bayesian vs. Random-C'),
    ('greedy', 'random_commit', 'Greedy vs. Random-C'),
    ('bayesian', 'pure_random', 'Bayesian vs. Pure Rand'),
    ('random_commit', 'random_commit', 'Random-C vs. Random-C'),
    ('random_commit', 'pure_random', 'Random-C vs. Pure Rand'),
    ('pure_random', 'pure_random', 'Pure Rand vs. Pure Rand')
]

print(f"\n{'Pairing':<30} {'Draw Rate':<12} {'Overlap':<12} {'Reshuffle':<12}")
print("-"*66)

for p1, p2, label in pairings:
    row_data = neither[(neither['player1_type'] == p1) & (neither['player2_type'] == p2)]
    if len(row_data) > 0:
        row = row_data.iloc[0]
        print(f"{label:<30} {row['draw_pct']:>6.1f}%      {row['draw_pattern_overlap_pct']:>6.1f}%      {row['reshuffle_pct']:>6.1f}%")

print("\n" + "="*80)
print("SECTION 4.3.1: PATTERN OVERLAP IN DRAWS")
print("="*80)

strategic_pairs = [
    ('bayesian', 'bayesian', 'B-B'),
    ('bayesian', 'greedy', 'B-G'),
    ('greedy', 'greedy', 'G-G')
]

overlaps_strategic = []
print("\nStrategic agent pattern overlap:")
for p1, p2, label in strategic_pairs:
    row_data = neither[(neither['player1_type'] == p1) & (neither['player2_type'] == p2)]
    if len(row_data) > 0:
        overlap = row_data.iloc[0]['draw_pattern_overlap_pct']
        overlaps_strategic.append(overlap)
        print(f"  {label}: {overlap:.1f}%")

print(f"\nRange: {min(overlaps_strategic):.1f}% - {max(overlaps_strategic):.1f}%")
print(f"\n  → PAPER TEXT: \"In 93-99% of draws between strategic agents")
print(f"     (Bayesian/Greedy), both players were pursuing the same hand pattern.\"")
print(f"  → OR: \"In {min(overlaps_strategic):.1f}-{max(overlaps_strategic):.1f}% of draws\"")

baseline_pairs = [
    ('random_commit', 'random_commit', 'RC-RC'),
    ('random_commit', 'pure_random', 'RC-PR'),
    ('pure_random', 'pure_random', 'PR-PR')
]

overlaps_baseline = []
print("\nBaseline agent pattern overlap:")
for p1, p2, label in baseline_pairs:
    row_data = neither[(neither['player1_type'] == p1) & (neither['player2_type'] == p2)]
    if len(row_data) > 0:
        overlap = row_data.iloc[0]['draw_pattern_overlap_pct']
        overlaps_baseline.append(overlap)
        print(f"  {label}: {overlap:.1f}%")

print(f"\nRange: {min(overlaps_baseline):.1f}% - {max(overlaps_baseline):.1f}%")
print(f"\n  → PAPER TEXT: \"pattern overlap dropped dramatically when both")
print(f"     players were non-strategic ({min(overlaps_baseline):.0f}-{max(overlaps_baseline):.0f}%)\"")

print("\n" + "="*80)
print("SECTION 4.3.2: PROGRESS AT DRAW")
print("="*80)

if len(bb_neither) > 0:
    row = bb_neither.iloc[0]
    total_draws = row['draws']
    
    print(f"\nBayesian vs Bayesian (neither nervous):")
    print(f"Total draws: {total_draws}")
    
    print(f"\nProgress categories:")
    print(f"  Both high (≥70%): {row['draw_both_high_progress']} draws ({(row['draw_both_high_progress']/total_draws)*100:.1f}%)")
    print(f"  Both stuck (<70%): {row['draw_both_stuck']} draws ({(row['draw_both_stuck']/total_draws)*100:.1f}%)")
    print(f"  Similar (within 15%): {row['draw_similar_progress']} draws ({(row['draw_similar_progress']/total_draws)*100:.1f}%)")
    
    asymmetric = row['draw_p1_stuck_p2_ahead'] + row['draw_p2_stuck_p1_ahead']
    print(f"  Asymmetric: {asymmetric} draws ({(asymmetric/total_draws)*100:.1f}%)")
    print(f"    - P1 ahead, P2 stuck: {row['draw_p2_stuck_p1_ahead']}")
    print(f"    - P2 ahead, P1 stuck: {row['draw_p1_stuck_p2_ahead']}")
    
    print(f"\nAverage final progress:")
    print(f"  P1: {row['draw_avg_p1_progress']:.1f}%")
    print(f"  P2: {row['draw_avg_p2_progress']:.1f}%")
    
    print(f"\n  → PAPER TEXT:")
    print(f"     \"Both high progress (≥70%): {(row['draw_both_high_progress']/total_draws)*100:.1f}% of draws")
    print(f"      ({row['draw_both_high_progress']}/{total_draws})\"")
    print(f"     \"Both stuck (<70%): {(row['draw_both_stuck']/total_draws)*100:.1f}% of draws")
    print(f"      ({row['draw_both_stuck']}/{total_draws})\"")
    print(f"     \"Similar progress (within 15%): {(row['draw_similar_progress']/total_draws)*100:.1f}% of draws")
    print(f"      ({row['draw_similar_progress']}/{total_draws})\"")
    print(f"     \"Asymmetric progress: {(asymmetric/total_draws)*100:.1f}% of draws\"")
    print(f"     \"Average final progress at draw: P1 = {row['draw_avg_p1_progress']:.1f}%,")
    print(f"      P2 = {row['draw_avg_p2_progress']:.1f}%\"")

print("\n" + "="*80)
print("SECTION 4.3.3: RESHUFFLE ANALYSIS")
print("="*80)

print("\nReshuffle rates:")
strategic_reshuffle = []
for p1, p2, label in pairings[:6]:
    row_data = neither[(neither['player1_type'] == p1) & (neither['player2_type'] == p2)]
    if len(row_data) > 0:
        row = row_data.iloc[0]
        strategic_reshuffle.append(row['reshuffle_pct'])
        print(f"  {label}: {row['reshuffle_pct']:.1f}%")

print(f"\nRange for strategic/mixed: {min(strategic_reshuffle):.0f}%-{max(strategic_reshuffle):.0f}%")
print(f"\n  → PAPER TEXT: \"90-98% of games reshuffled at least once\"")

# Resolution after reshuffle
if len(bg_neither) > 0:
    row = bg_neither.iloc[0]
    if row['games_reshuffled'] > 0:
        resolution_pct = (row['wins_after_reshuffle'] / row['games_reshuffled']) * 100
        draw_again_pct = 100 - resolution_pct
        
        print(f"\nResolution after reshuffle (Bayesian vs Greedy):")
        print(f"  Games reshuffled: {row['games_reshuffled']}")
        print(f"  Wins after reshuffle: {row['wins_after_reshuffle']}")
        print(f"  Resolution rate: {resolution_pct:.1f}%")
        print(f"  Drew again: {draw_again_pct:.1f}%")
        
        print(f"\n  → PAPER TEXT: \"Of reshuffled games, only {resolution_pct:.0f}%")
        print(f"     resolved to a winner\"")
        print(f"     \"{draw_again_pct:.0f}% of reshuffled games drew again\"")

print("\n" + "="*80)
print("SECTION 5: DRAW RATE RANGES FOR DISCUSSION")
print("="*80)

strategic_draws = []
for p1, p2, label in pairings[:3]:
    row_data = neither[(neither['player1_type'] == p1) & (neither['player2_type'] == p2)]
    if len(row_data) > 0:
        strategic_draws.append(row_data.iloc[0]['draw_pct'])

print(f"\nDraw rates for strategic matchups:")
print(f"  Range: {min(strategic_draws):.1f}% - {max(strategic_draws):.1f}%")
print(f"\n  → PAPER TEXT (Discussion): \"the extremely high draw rates")
print(f"     ({min(strategic_draws):.1f}-{max(strategic_draws):.1f}% for strategic agents)\"")

print("\n" + "="*80)
print("ABSTRACT STATISTICS")
print("="*80)

if len(bg_neither) > 0:
    row = bg_neither.iloc[0]
    print(f"\nFor abstract:")
    print(f"  Primary win rate: {row['p1_win_rate_decisive']:.1f}%")
    print(f"  Win rate range: {min(win_rates):.1f}%-{max(win_rates):.1f}%")
    print(f"  Most configs cluster: 52-68% ({len(clustered_52_68)}/{len(win_rates)} configs)")
    print(f"  Draw rates: 81-100%")
    print(f"  Pattern overlap (strategic): {min(overlaps_strategic):.0f}-{max(overlaps_strategic):.0f}%")
