using Gen
using Random
using Statistics
using Printf

include("mahjong_model.jl")
include("mahjong_hands.jl")

# ============================================================================
# GAME SIMULATION WITH DRAW RESOLUTION (NO NERVOUSNESS)
# ============================================================================

"""
Simulate a turn with detailed logging (no nervousness/hand-switching)
"""
function simulate_turn_simple(game_state::GameState, game_log::Dict)
    if game_state.wall_remaining <= 0
        return :wall_empty
    end
    
    turn_num = game_state.turn
    
    # Draw tile for player
    wall_tiles = generate_remaining_wall(vcat(
        game_state.my_hand, 
        game_state.discards,
        reduce(vcat, game_state.opponents, init=Tile[])
    ))
    
    if isempty(wall_tiles)
        return :wall_empty
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
    
    game_state.viable_hands = get_viable_hands(
        game_state.all_hands, 
        game_state.my_hand, 
        seen_tiles,
        game_state.exposed_sets
    )
    
    if !isempty(game_state.viable_hands)
        sorted_hands = sort(
            game_state.viable_hands, 
            by=hand -> length(tiles_needed_for_hand(hand, game_state.my_hand, game_state.exposed_sets))
        )
        game_state.viable_hands = sorted_hands
    end
    
    # Log player state
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
    
    # Make decision (no nervousness parameter - always 0)
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
        0,       # turns_since_progress (not used without nervousness)
        nothing  # last_progress_value (not used without nervousness)
    )
    
    hand_scores = evaluate_hands(temp_state, 30)
    decision = make_decision(temp_state, drawn_tile, [Dict{Int,Int}()], false, 999)  # High nervousness = never switch
    
    if temp_state.committed_hand_id !== nothing
        game_state.committed_hand_id = temp_state.committed_hand_id
    end
    
    # Execute decision - discard
    discard_tile = nothing
    if decision[1] == :commit && length(decision) >= 3
        discard_tile = decision[3]
    elseif length(decision) >= 2
        discard_tile = decision[2]
    end
    
    if discard_tile !== nothing
        idx = findfirst(t -> t.name == discard_tile.name, game_state.my_hand)
        if idx !== nothing
            deleteat!(game_state.my_hand, idx)
            push!(game_state.discards, discard_tile)
        end
    end
    
    # Opponent turn
    if !isempty(wall_tiles) && length(wall_tiles) > 1
        game_state.wall_remaining -= 1
        wall_tiles_after = generate_remaining_wall(vcat(
            game_state.my_hand, 
            game_state.discards,
            reduce(vcat, game_state.opponents, init=Tile[])
        ))

        if !isempty(wall_tiles_after)
            opponent_drawn = rand(wall_tiles_after)
            push!(game_state.opponents[1], opponent_drawn)
            
            # Get opponent viable hands
            all_seen = vcat(
                game_state.discards, 
                reduce(vcat, game_state.opponents, init=Tile[])
            )
            opp_viable = get_viable_hands(
                game_state.all_hands, 
                game_state.opponents[1], 
                all_seen,
                game_state.opponent_exposed[1]
            )
            
            # Log opponent state
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
            
            # Check if opponent won by drawing
            for hand in opp_viable
                needed = tiles_needed_for_hand(hand, game_state.opponents[1], game_state.opponent_exposed[1])
                if isempty(needed)
                    game_log[:winning_hand] = (:opponent, hand.pattern_name, hand.point_value)
                    return :opponent_won
                end
            end
            
            # Opponent decision (with diversity awareness)
            player_pattern = nothing
            if !isempty(game_state.viable_hands)
                player_best = game_state.viable_hands[1]
                player_pattern = player_best.pattern_name
            end

            opp_opponent_info = Dict{Int,Int}()
            if player_pattern !== nothing
                for hand in game_state.all_hands
                    if hand.pattern_name == player_pattern
                        opp_opponent_info[hand.id] = 100
                        break
                    end
                end
            end

            opponent_discard, _ = opponent_make_decision_diverse(
                game_state.opponents[1],
                game_state.all_hands,
                all_seen,
                game_state.opponent_exposed[1],
                [opp_opponent_info]
            )
            
            opp_idx = findfirst(t -> t.name == opponent_discard.name, game_state.opponents[1])
            if opp_idx !== nothing
                deleteat!(game_state.opponents[1], opp_idx)
            end

            push!(game_state.opponent_discards[1], opponent_discard)

            # Check if player can claim
            can_claim, set_type, completing_tiles = can_claim_tile(opponent_discard, game_state)
            
            if can_claim
                if set_type == :mahjong
                    game_log[:winning_hand] = (:player, "claimed", 0)
                    return :player_won
                else
                    claim_tile!(opponent_discard, game_state, set_type, completing_tiles)
                    
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
                push!(game_state.discards, opponent_discard)
            end
        end
    end
    
    game_state.turn += 1
    return :continue
end

"""
Simulate game with draw resolution (reshuffle pot on draw, max 1 reshuffle)
"""
function simulate_game_with_reshuffles(all_hands::Vector{MahjongHand}, max_total_turns::Int=200)
    game_log = Dict{Symbol, Any}(
        :reshuffled => false,
        :reshuffle_turn => 0
    )
    
    # Initial deal
    all_tiles = generate_remaining_wall(Tile[])
    shuffle!(all_tiles)

    my_hand = all_tiles[1:13]
    opponent_hand = all_tiles[14:26]
    seen_tiles = vcat(my_hand, opponent_hand)

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
    
    total_turns = 0
    
    # Play until someone wins or we hit max turns
    while total_turns < max_total_turns
        result = simulate_turn_simple(game_state, game_log)
        total_turns = game_state.turn - 1
        
        if result == :player_won
            game_log[:outcome] = :player_won
            game_log[:total_turns] = total_turns
            return game_log
        elseif result == :opponent_won
            game_log[:outcome] = :opponent_won
            game_log[:total_turns] = total_turns
            return game_log
        elseif result == :wall_empty
            # DRAW - Check if we can reshuffle
            if !game_log[:reshuffled]
                # First draw - reshuffle the pot!
                game_log[:reshuffled] = true
                game_log[:reshuffle_turn] = total_turns
                
                # Players keep their hands, but discards go back to wall
                # Reset committed hands (fresh start mentality)
                game_state.committed_hand_id = nothing
                
                # Calculate new wall
                game_state.wall_remaining = length(generate_remaining_wall(
                    vcat(game_state.my_hand, game_state.opponents[1])
                ))
                
                # Clear discards
                game_state.discards = Tile[]
                game_state.opponent_discards[1] = Tile[]
                
                # Continue playing
                continue
            else
                # Already reshuffled once - this is a true draw
                game_log[:outcome] = :draw
                game_log[:total_turns] = total_turns
                return game_log
            end
        end
        
        # Check turn limit
        if total_turns >= max_total_turns
            break
        end
    end
    
    # Timeout
    game_log[:outcome] = :timeout
    game_log[:total_turns] = total_turns
    return game_log
end

# ============================================================================
# BENCHMARK
# ============================================================================

"""
Run benchmark comparing draw resolution vs. standard game
"""
function run_drawresolve_benchmark(n_games::Int=100; max_turns::Int=200)
    println("\n" * "="^80)
    println("🎮 DRAW RESOLUTION BENCHMARK")
    println("="^80)
    println("Rules: On first draw, reshuffle discard pot and continue (max 1 reshuffle)")
    println("Max total turns: $max_turns")
    println("Games to simulate: $n_games")
    println("No nervousness threshold (players don't switch hands)")
    
    # Load hands
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
    
    # Track reshuffle stats
    games_reshuffled = 0
    wins_after_reshuffle = 0
    wins_before_reshuffle = 0
    
    game_logs = []
    
    # Run games
    println("Running simulations...")
    for i in 1:n_games
        Random.seed!(i)
        
        game_log = simulate_game_with_reshuffles(all_hands, max_turns)
        push!(game_logs, game_log)
        
        outcome = game_log[:outcome]
        results[outcome] += 1
        
        # Track reshuffle stats
        if game_log[:reshuffled]
            games_reshuffled += 1
            
            if outcome in [:player_won, :opponent_won]
                wins_after_reshuffle += 1
            end
        else
            if outcome in [:player_won, :opponent_won]
                wins_before_reshuffle += 1
            end
        end
        
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
    # RESULTS ANALYSIS
    # ========================================================================
    
    println("="^80)
    println("📊 RESULTS")
    println("="^80)
    
    total_decisive = results[:player_won] + results[:opponent_won]
    
    println("\n🎯 Win Statistics:")
    println("   Player wins:     $(results[:player_won])/$n_games ($(round(results[:player_won]/n_games*100, digits=1))%)")
    println("   Opponent wins:   $(results[:opponent_won])/$n_games ($(round(results[:opponent_won]/n_games*100, digits=1))%)")
    println("   Draws:           $(results[:draw])/$n_games ($(round(results[:draw]/n_games*100, digits=1))%)")
    println("   Timeouts:        $(results[:timeout])/$n_games ($(round(results[:timeout]/n_games*100, digits=1))%)")
    
    if total_decisive > 0
        println("\n🏆 Decisive Games Only:")
        println("   Player win rate:   $(round(results[:player_won]/total_decisive*100, digits=1))%")
        println("   Opponent win rate: $(round(results[:opponent_won]/total_decisive*100, digits=1))%")
    end
    
    println("\n🔄 Reshuffle Statistics:")
    println("   Games that reshuffled: $games_reshuffled/$n_games ($(round(games_reshuffled/n_games*100, digits=1))%)")
    
    if games_reshuffled > 0
        println("\n   After reshuffle:")
        reshuffled_games = [log for log in game_logs if log[:reshuffled]]
        r_wins = length([log for log in reshuffled_games if log[:outcome] in [:player_won, :opponent_won]])
        r_draws = length([log for log in reshuffled_games if log[:outcome] == :draw])
        r_timeouts = length([log for log in reshuffled_games if log[:outcome] == :timeout])
        
        println("     Resolved (won):  $r_wins/$games_reshuffled ($(round(r_wins/games_reshuffled*100, digits=1))%)")
        println("     Drew again:      $r_draws/$games_reshuffled ($(round(r_draws/games_reshuffled*100, digits=1))%)")
        println("     Timed out:       $r_timeouts/$games_reshuffled ($(round(r_timeouts/games_reshuffled*100, digits=1))%)")
    end
    
    if total_decisive > 0
        println("\n   Win timing:")
        println("     Initial attempt:    $wins_before_reshuffle/$total_decisive ($(round(wins_before_reshuffle/total_decisive*100, digits=1))%)")
        println("     After reshuffle:    $wins_after_reshuffle/$total_decisive ($(round(wins_after_reshuffle/total_decisive*100, digits=1))%)")
    end
    
    # Draw analysis
    draw_games = [log for log in game_logs if log[:outcome] == :draw]
    
    if !isempty(draw_games)
        println("\n📉 Draw Analysis:")
        println("   Total draws (after reshuffle): $(length(draw_games))/$n_games ($(round(length(draw_games)/n_games*100, digits=1))%)")
        
        # Pattern analysis
        pattern_overlaps = 0
        similar_progress = 0
        both_stuck = 0
        
        for game_log in draw_games
            if haskey(game_log, :player_hands) && haskey(game_log, :opponent_hands)
                turns = collect(keys(game_log[:player_hands]))
                if !isempty(turns)
                    final_turn = maximum(turns)
                    
                    if haskey(game_log[:player_hands], final_turn) && haskey(game_log[:opponent_hands], final_turn)
                        player_hand, player_prog = game_log[:player_hands][final_turn]
                        opp_hand, opp_prog = game_log[:opponent_hands][final_turn]
                        
                        if player_hand == opp_hand
                            pattern_overlaps += 1
                        end
                        
                        if abs(player_prog - opp_prog) < 0.15
                            similar_progress += 1
                        end
                        
                        if player_prog < 0.7 && opp_prog < 0.7
                            both_stuck += 1
                        end
                    end
                end
            end
        end
        
        if !isempty(draw_games)
            println("   Same pattern (competing): $(pattern_overlaps)/$(length(draw_games)) ($(round(pattern_overlaps/length(draw_games)*100, digits=1))%)")
            println("   Similar progress:         $(similar_progress)/$(length(draw_games)) ($(round(similar_progress/length(draw_games)*100, digits=1))%)")
            println("   Both stuck (<70%):        $(both_stuck)/$(length(draw_games)) ($(round(both_stuck/length(draw_games)*100, digits=1))%)")
        end
    end
    
    println("\n" * "="^80)
    
    return game_logs
end

# ============================================================================
# MAIN
# ============================================================================

if abspath(PROGRAM_FILE) == @__FILE__
    game_logs = run_drawresolve_benchmark(100, max_turns=200)
end