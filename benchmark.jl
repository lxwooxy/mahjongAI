using Gen
using Random
using Statistics
using Printf

include("mahjong_model.jl")
include("mahjong_hands.jl")


# ============================================================================
# ENHANCED SIMULATION WITH DETAILED LOGGING
# ============================================================================

"""
Simulate a complete turn in Mahjong with detailed logging
"""
function simulate_turn_logged(game_state::GameState, game_log::Dict, nervousness::Int=5)
    if game_state.wall_remaining <= 0
        return nothing
    end
    
    turn_num = game_state.turn
    
    # Draw a tile for player
    wall_tiles = generate_remaining_wall(vcat(
        game_state.my_hand, 
        game_state.discards,
        reduce(vcat, game_state.opponents, init=Tile[])
    ))
    
    if isempty(wall_tiles)
        return nothing
    end
    
    drawn_tile = rand(wall_tiles)
    push!(game_state.my_hand, drawn_tile)
    game_state.wall_remaining -= 1
    
    # Update viable hands
    all_opponent_exposed = Tile[]
    for opponent_sets in game_state.opponent_exposed
        for set in opponent_sets
            append!(all_opponent_exposed, set)
        end
    end
    
    seen_tiles = vcat(
        game_state.my_hand, 
        game_state.discards,
        reduce(vcat, game_state.exposed_sets, init=Tile[]),
        all_opponent_exposed
    )
    
    game_state.viable_hands = get_viable_hands(game_state.all_hands, 
                                           game_state.my_hand, 
                                           seen_tiles,
                                           game_state.exposed_sets)
    
    # Sort viable hands by fewest tiles needed
    if !isempty(game_state.viable_hands)
        sorted_hands = sort(game_state.viable_hands, by=hand -> length(tiles_needed_for_hand(hand, game_state.my_hand, game_state.exposed_sets)))
        game_state.viable_hands = sorted_hands
    end
    
    # LOG PLAYER STATE
    if !isempty(game_state.viable_hands)
        best_hand = game_state.viable_hands[1]
        needed = tiles_needed_for_hand(best_hand, game_state.my_hand, game_state.exposed_sets)
        total = length(best_hand.required_tiles)
        progress = (total - length(needed)) / total
        
        if !haskey(game_log, :player_hands)
            game_log[:player_hands] = Dict{Int, Tuple{String, Float64}}()
        end
        game_log[:player_hands][turn_num] = (best_hand.pattern_name, progress)
    end
    
    # Check if player won
    for hand in game_state.viable_hands
        needed = tiles_needed_for_hand(hand, game_state.my_hand, game_state.exposed_sets)
        if isempty(needed)
            game_log[:winning_hand] = (:player, hand.pattern_name, hand.point_value)
            return :player_won
        end
    end
    
    # Make decision
    hands_to_evaluate = game_state.viable_hands[1:min(10, end)]
    temp_state = GameState(
        game_state.my_hand,
        game_state.discards,
        game_state.opponents,
        game_state.opponent_exposed,
        game_state.wall_remaining,
        game_state.turn,
        hands_to_evaluate,
        game_state.all_hands,
        game_state.committed_hand_id,
        game_state.exposed_sets,
        game_state.opponent_discards,
        game_state.turns_since_progress,     
        game_state.last_progress_value       
    )
    
    hand_scores = evaluate_hands(temp_state, 30)
    decision = make_decision(temp_state, drawn_tile, [Dict{Int,Int}()], false, nervousness)

    if temp_state.committed_hand_id !== nothing
        game_state.committed_hand_id = temp_state.committed_hand_id
    end

    
    game_state.turns_since_progress = temp_state.turns_since_progress
    game_state.last_progress_value = temp_state.last_progress_value
    
    # Execute decision - discard a tile
    discard_tile = nothing
    if decision[1] == :commit && length(decision) >= 3
        discard_tile = decision[3]
    elseif length(decision) >= 2
        discard_tile = decision[2]
    end
    
    # Discard player's tile
    if discard_tile !== nothing
        idx = findfirst(t -> t.name == discard_tile.name, game_state.my_hand)
        if idx !== nothing
            deleteat!(game_state.my_hand, idx)
            push!(game_state.discards, discard_tile)
        end
    end
    
    # Simulate opponent turn
    if !isempty(wall_tiles) && length(wall_tiles) > 1
        game_state.wall_remaining -= 1
        wall_tiles_after_my_discard = generate_remaining_wall(vcat(
            game_state.my_hand, 
            game_state.discards,
            reduce(vcat, game_state.opponents, init=Tile[])
        ))

        if !isempty(wall_tiles_after_my_discard)
            opponent_drawn = rand(wall_tiles_after_my_discard)
            push!(game_state.opponents[1], opponent_drawn)
            
            # Get opponent viable hands for logging
            all_seen = vcat(game_state.discards, 
                            reduce(vcat, game_state.opponents, init=Tile[]))
            opp_viable = get_viable_hands(game_state.all_hands, 
                                         game_state.opponents[1], 
                                         all_seen,
                                         game_state.opponent_exposed[1])
            
            # LOG OPPONENT STATE
            if !isempty(opp_viable)
                opp_best = opp_viable[1]
                opp_needed = tiles_needed_for_hand(opp_best, game_state.opponents[1], game_state.opponent_exposed[1])
                opp_total = length(opp_best.required_tiles)
                opp_progress = (opp_total - length(opp_needed)) / opp_total
                
                if !haskey(game_log, :opponent_hands)
                    game_log[:opponent_hands] = Dict{Int, Tuple{String, Float64}}()
                end
                game_log[:opponent_hands][turn_num] = (opp_best.pattern_name, opp_progress)
            end
            
            # CHECK IF OPPONENT WON BY DRAWING
            for hand in opp_viable
                needed = tiles_needed_for_hand(hand, game_state.opponents[1], game_state.opponent_exposed[1])
                if isempty(needed)
                    game_log[:winning_hand] = (:opponent, hand.pattern_name, hand.point_value)
                    return :opponent_won
                end
            end
            
           # Opponent makes decision (greedy but with pattern diversity)
            # Track what player is pursuing
            player_pattern = nothing
            if !isempty(game_state.viable_hands)
                player_best = game_state.viable_hands[1]
                player_pattern = player_best.pattern_name
            end

            # Give opponent diversity awareness
            opp_opponent_info = Dict{Int,Int}()
            if player_pattern !== nothing
                for hand in game_state.all_hands
                    if hand.pattern_name == player_pattern
                        opp_opponent_info[hand.id] = 100
                        break
                    end
                end
            end

            # Use greedy with diversity for opponent
            opponent_discard, opp_hand_info = opponent_make_decision_diverse(  # <-- NEW FUNCTION
                game_state.opponents[1],
                game_state.all_hands,
                all_seen,
                game_state.opponent_exposed[1],
                [opp_opponent_info]
            )
            
            # Remove from opponent's hand
            opp_idx = findfirst(t -> t.name == opponent_discard.name, game_state.opponents[1])
            if opp_idx !== nothing
                deleteat!(game_state.opponents[1], opp_idx)
            end

            # Track this discard
            push!(game_state.opponent_discards[1], opponent_discard)

            # CHECK: Can player claim this tile?
            can_claim, set_type, completing_tiles = can_claim_tile(opponent_discard, game_state)
            
            if can_claim
                if set_type == :mahjong
                    game_log[:winning_hand] = (:player, "claimed", 0)
                    return :player_won
                else
                    # Claim for pung/kong
                    claim_tile!(opponent_discard, game_state, set_type, completing_tiles)
                    
                    # Discard after claim
                    hand_idx = findfirst(h -> h.id == game_state.committed_hand_id, game_state.viable_hands)
                    if hand_idx !== nothing
                        discard_after_claim = find_best_discard(game_state, game_state.committed_hand_id, false)
                        if discard_after_claim !== nothing
                            idx = findfirst(t -> t.name == discard_after_claim.name, game_state.my_hand)
                            if idx !== nothing
                                deleteat!(game_state.my_hand, idx)
                                push!(game_state.discards, discard_after_claim)
                            end
                        end
                    end
                end
            else
                # Tile goes to pot
                push!(game_state.discards, opponent_discard)
            end
        end
    end
    
    # Increment turn
    game_state.turn += 1
    
    return :continue
end

"""
Run a full game simulation with logging
"""
function simulate_game_logged(all_hands::Vector{MahjongHand}, max_turns::Int=70, nervousness::Int=5)
    game_log = Dict{Symbol, Any}()
    
    # Deal initial hands
    all_tiles = generate_remaining_wall(Tile[])
    shuffle!(all_tiles)

    my_hand = all_tiles[1:13]
    opponent_hand = all_tiles[14:26]

    seen_tiles = vcat(my_hand, opponent_hand)

    # Initialize viable hands
    viable_hands = get_viable_hands(all_hands, my_hand, seen_tiles, Vector{Tile}[])
    viable_hands = sort(viable_hands, by=hand -> length(tiles_needed_for_hand(hand, my_hand)))

    game_state = GameState(
        my_hand,
        Tile[],
        [opponent_hand],
        [Vector{Tile}[]],
        length(all_tiles) - 26,
        1,
        viable_hands,
        all_hands,
        nothing,
        Vector{Tile}[],
        [Tile[]],
        0,        
        nothing  
    )
    
    # Play turns
    for turn in 1:max_turns
        result = simulate_turn_logged(game_state, game_log, nervousness)
        
        if result == :player_won
            game_log[:outcome] = :player_won
            game_log[:turns] = game_state.turn - 1
            return game_log
        elseif result == :opponent_won
            game_log[:outcome] = :opponent_won
            game_log[:turns] = game_state.turn - 1
            return game_log
        elseif result === nothing
            game_log[:outcome] = :draw
            game_log[:turns] = game_state.turn - 1
            game_log[:draw_reason] = :wall_exhausted
            return game_log
        end
    end
    
    game_log[:outcome] = :timeout
    game_log[:turns] = max_turns
    return game_log
end

# ============================================================================
# ENHANCED BENCHMARK WITH DETAILED ANALYSIS
# ============================================================================

"""
Run benchmark with detailed game logging
"""
function run_detailed_benchmark(n_games::Int=100; max_turns::Int=70, nervousness::Int=5)
    println("\n" * "="^70)
    println("🎮 DETAILED MAHJONG AI BENCHMARK")
    println("="^70)
    println("Nervousness threshold: $nervousness turns without progress")
    
    # Load hands once
    println("\nLoading hand patterns...")
    all_hands = generate_mahjong_hands()
    println("✓ Loaded $(length(all_hands)) unique hands\n")
    
    # Track results
    results = Dict(
        :player_won => 0,
        :opponent_won => 0,
        :draw => 0,
        :timeout => 0
    )
    
    game_logs = []
    
    # Run games
    println("Running simulations...")
    for i in 1:n_games
        Random.seed!(i)
        
        game_log = simulate_game_logged(all_hands, max_turns, nervousness)
        push!(game_logs, game_log)
        
        outcome = game_log[:outcome]
        results[outcome] += 1
        
        # Progress indicator
        if i % 10 == 0
            print(".")
            flush(stdout)
        end
        if i % 50 == 0
            println(" $i/$n_games")
        end
    end
    
    println("\n")
    
    # ========================================================================
    # ANALYZE DRAWS
    # ========================================================================
    
    println("="^70)
    println("📊 DRAW ANALYSIS")
    println("="^70)
    
    draw_games = [log for log in game_logs if log[:outcome] == :draw]
    
    println("\nTotal draws: $(length(draw_games))/$(n_games) ($(round(length(draw_games)/n_games*100, digits=1))%)")
    
    if !isempty(draw_games)
        println("\n🔍 Analyzing draw games...")
        
        # Pattern overlap analysis
        pattern_overlaps = 0
        similar_progress = 0
        both_stuck = 0
        
        for game_log in draw_games
            if haskey(game_log, :player_hands) && haskey(game_log, :opponent_hands)
                # Get final turn data
                turns = collect(keys(game_log[:player_hands]))
                if !isempty(turns)
                    final_turn = maximum(turns)
                    
                    if haskey(game_log[:player_hands], final_turn) && haskey(game_log[:opponent_hands], final_turn)
                        player_hand, player_prog = game_log[:player_hands][final_turn]
                        opp_hand, opp_prog = game_log[:opponent_hands][final_turn]
                        
                        # Check for pattern overlap
                        if player_hand == opp_hand
                            pattern_overlaps += 1
                        end
                        
                        # Check if similar progress
                        if abs(player_prog - opp_prog) < 0.15
                            similar_progress += 1
                        end
                        
                        # Check if both stuck (low progress)
                        if player_prog < 0.7 && opp_prog < 0.7
                            both_stuck += 1
                        end
                    end
                end
            end
        end
        
        println("\n  Pattern Analysis:")
        println("    Same pattern (competing): $(pattern_overlaps)/$(length(draw_games)) ($(round(pattern_overlaps/length(draw_games)*100, digits=1))%)")
        println("    Similar progress:         $(similar_progress)/$(length(draw_games)) ($(round(similar_progress/length(draw_games)*100, digits=1))%)")
        println("    Both stuck (<70%):        $(both_stuck)/$(length(draw_games)) ($(round(both_stuck/length(draw_games)*100, digits=1))%)")
        
        # Sample some draw games
        println("\n  📝 Sample Draw Games (first 5):")
        for (i, game_log) in enumerate(draw_games[1:min(5, end)])
            println("\n    Game $i (ended turn $(game_log[:turns])):")
            
            if haskey(game_log, :player_hands) && haskey(game_log, :opponent_hands)
                turns = sort(collect(keys(game_log[:player_hands])))
                if !isempty(turns)
                    final_turn = turns[end]
                    
                    if haskey(game_log[:player_hands], final_turn)
                        player_hand, player_prog = game_log[:player_hands][final_turn]
                        println("      Player:   $(player_hand)")
                        println("                Progress: $(round(player_prog*100, digits=1))%")
                    end
                    
                    if haskey(game_log[:opponent_hands], final_turn)
                        opp_hand, opp_prog = game_log[:opponent_hands][final_turn]
                        println("      Opponent: $(opp_hand)")
                        println("                Progress: $(round(opp_prog*100, digits=1))%")
                    end
                end
            end
        end
    end
    
    # ========================================================================
    # REGULAR RESULTS
    # ========================================================================
    
    println("\n" * "="^70)
    println("📊 OVERALL RESULTS")
    println("="^70)
    
    total_decided = results[:player_won] + results[:opponent_won]
    
    println("\n🎯 Win Statistics:")
    println("   Player (Bayesian) wins:  $(results[:player_won])/$n_games ($(round(results[:player_won]/n_games*100, digits=1))%)")
    println("   Opponent (Greedy) wins:  $(results[:opponent_won])/$n_games ($(round(results[:opponent_won]/n_games*100, digits=1))%)")
    println("   Draws:                   $(results[:draw])/$n_games ($(round(results[:draw]/n_games*100, digits=1))%)")
    
    if total_decided > 0
        println("\n🏆 Decisive Games Only:")
        println("   Player win rate:         $(round(results[:player_won]/total_decided*100, digits=1))%")
        println("   Opponent win rate:       $(round(results[:opponent_won]/total_decided*100, digits=1))%")
    end
    
    println("\n" * "="^70)
    
    return game_logs
end

# ============================================================================
# MAIN
# ============================================================================

if abspath(PROGRAM_FILE) == @__FILE__
    game_logs = run_detailed_benchmark(100, max_turns=70)
end