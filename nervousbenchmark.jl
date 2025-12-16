using Gen
using Random
using Statistics
using Printf

include("mahjong_model.jl")
include("mahjong_hands.jl")
include("benchmark.jl")

println("\n" * "="^80)
println("🎯 NERVOUSNESS THRESHOLD BENCHMARK")
println("="^80)
println("Running 200 games for each nervousness threshold: 10, 5, and 3")
println("This will test if hand-switching reduces draw rates")
println("="^80)

# Run benchmarks
results_summary = Dict()

for nervousness in [10, 5, 3]
    println("\n\n" * "█"^80)
    println("█  NERVOUSNESS = $nervousness")
    println("█"^80)
    
    logs = run_detailed_benchmark(200, max_turns=70, nervousness=nervousness)
    
    results_summary[nervousness] = logs
    
    # Brief summary
    println("\n📊 Quick Summary (nervousness=$nervousness):")
    println("   Draws: $(length([log for log in logs if log[:outcome] == :draw]))/200")
    println("   Player wins: $(length([log for log in logs if log[:outcome] == :player_won]))/200")
    println("   Opponent wins: $(length([log for log in logs if log[:outcome] == :opponent_won]))/200")
end

# Final comparison
println("\n\n" * "="^80)
println("📈 FINAL COMPARISON")
println("="^80)

for nervousness in [10, 5, 3]
    logs = results_summary[nervousness]
    
    draws = length([log for log in logs if log[:outcome] == :draw])
    player_wins = length([log for log in logs if log[:outcome] == :player_won])
    opp_wins = length([log for log in logs if log[:outcome] == :opponent_won])
    
    # Pattern competition analysis
    draw_logs = [log for log in logs if log[:outcome] == :draw]
    pattern_competition = 0
    
    for game_log in draw_logs
        if haskey(game_log, :player_hands) && haskey(game_log, :opponent_hands)
            turns = collect(keys(game_log[:player_hands]))
            if !isempty(turns)
                final_turn = maximum(turns)
                if haskey(game_log[:player_hands], final_turn) && haskey(game_log[:opponent_hands], final_turn)
                    player_hand, _ = game_log[:player_hands][final_turn]
                    opp_hand, _ = game_log[:opponent_hands][final_turn]
                    if player_hand == opp_hand
                        pattern_competition += 1
                    end
                end
            end
        end
    end
    
    println("\nNervousness = $nervousness:")
    println("  Draws:               $draws/200 ($(round(draws/200*100, digits=1))%)")
    println("  Player wins:         $player_wins/200 ($(round(player_wins/200*100, digits=1))%)")
    println("  Opponent wins:       $opp_wins/200 ($(round(opp_wins/200*100, digits=1))%)")
    if !isempty(draw_logs)
        println("  Pattern competition: $pattern_competition/$(length(draw_logs)) draws ($(round(pattern_competition/length(draw_logs)*100, digits=1))%)")
    end
end

println("\n" * "="^80)
println("✅ Benchmark complete!")
println("="^80)