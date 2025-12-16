using Gen
using Random
using Statistics
using Printf
using DataFrames
using CSV
using Dates

include("mahjong_model.jl")
include("mahjong_hands.jl")

# ============================================================================
# ENHANCED DRAW ANALYSIS
# ============================================================================

"""
Detailed analysis of draw games
"""
function analyze_draw_details(draw_games::Vector)
    analysis = Dict(
        :total_draws => length(draw_games),
        :pattern_overlap => 0,
        :similar_progress => 0,
        :both_stuck => 0,
        :p1_stuck_p2_ahead => 0,
        :p2_stuck_p1_ahead => 0,
        :both_high_progress => 0,
        :both_low_progress => 0,
        :avg_final_p1_progress => 0.0,
        :avg_final_p2_progress => 0.0,
        :avg_turns => 0.0
    )
    
    if isempty(draw_games)
        return analysis
    end
    
    p1_progresses = Float64[]
    p2_progresses = Float64[]
    turn_counts = Float64[]
    
    for game_log in draw_games
        if haskey(game_log, :total_turns)
            push!(turn_counts, game_log[:total_turns])
        end
        
        if haskey(game_log, :player_hands) && haskey(game_log, :opponent_hands)
            turns = collect(keys(game_log[:player_hands]))
            if !isempty(turns)
                final_turn = maximum(turns)
                
                if haskey(game_log[:player_hands], final_turn) && haskey(game_log[:opponent_hands], final_turn)
                    player_hand, player_prog = game_log[:player_hands][final_turn]
                    opp_hand, opp_prog = game_log[:opponent_hands][final_turn]
                    
                    push!(p1_progresses, player_prog)
                    push!(p2_progresses, opp_prog)
                    
                    # Pattern overlap
                    if player_hand == opp_hand
                        analysis[:pattern_overlap] += 1
                    end
                    
                    # Similar progress (within 15%)
                    if abs(player_prog - opp_prog) < 0.15
                        analysis[:similar_progress] += 1
                    end
                    
                    # Both stuck (both <70%)
                    if player_prog < 0.7 && opp_prog < 0.7
                        analysis[:both_stuck] += 1
                    end
                    
                    # P1 stuck, P2 ahead
                    if player_prog < 0.7 && opp_prog >= 0.7
                        analysis[:p1_stuck_p2_ahead] += 1
                    end
                    
                    # P2 stuck, P1 ahead
                    if opp_prog < 0.7 && player_prog >= 0.7
                        analysis[:p2_stuck_p1_ahead] += 1
                    end
                    
                    # Both high progress (both >=70%)
                    if player_prog >= 0.7 && opp_prog >= 0.7
                        analysis[:both_high_progress] += 1
                    end
                    
                    # Both low progress (both <50%)
                    if player_prog < 0.5 && opp_prog < 0.5
                        analysis[:both_low_progress] += 1
                    end
                end
            end
        end
    end
    
    # Calculate averages
    if !isempty(p1_progresses)
        analysis[:avg_final_p1_progress] = mean(p1_progresses)
    end
    if !isempty(p2_progresses)
        analysis[:avg_final_p2_progress] = mean(p2_progresses)
    end
    if !isempty(turn_counts)
        analysis[:avg_turns] = mean(turn_counts)
    end
    
    return analysis
end

# ============================================================================
# PLAYER TYPES
# ============================================================================

"""
Player types:
- :bayesian - Smart AI with Bayesian inference and defensive play
- :greedy - Picks best hand by progress, no Bayesian reasoning
- :random_commit - Picks random viable hand at start, commits forever
- :pure_random - Completely random picks and discards
"""

# ============================================================================
# DECISION FUNCTIONS FOR EACH PLAYER TYPE
# ============================================================================

"""
Random-Commit AI: Pick a random viable hand at the start and commit to it forever
"""
function random_commit_decision(game_state::GameState, 
                                committed_hand_id_ref::Ref{Union{Int,Nothing}})
    if isempty(game_state.viable_hands)
        if !isempty(game_state.my_hand)
            return game_state.my_hand[1]
        else
            return nothing
        end
    end
    
    # If we haven't committed yet, pick a random viable hand
    if committed_hand_id_ref[] === nothing
        random_hand = rand(game_state.viable_hands)
        committed_hand_id_ref[] = random_hand.id
    end
    
    # Find our committed hand
    hand_idx = findfirst(h -> h.id == committed_hand_id_ref[], game_state.viable_hands)
    
    if hand_idx === nothing
        # Our committed hand is no longer viable - pick random from hand
        if !isempty(game_state.my_hand)
            return rand(game_state.my_hand)
        else
            return nothing
        end
    end
    
    committed_hand = game_state.viable_hands[hand_idx]
    
    # Discard using same logic as greedy (discard least useful tile)
    needed = tiles_needed_for_hand(committed_hand, game_state.my_hand, game_state.exposed_sets)
    needed_names = Set(t.name for t in needed)
    required_names = Set(t.name for t in committed_hand.required_tiles)
    
    tile_usefulness = Dict{Int, Float64}()
    for (idx, tile) in enumerate(game_state.my_hand)
        if tile.name in needed_names
            tile_usefulness[idx] = 2.0
        elseif tile.name in required_names
            tile_usefulness[idx] = 1.0
        else
            tile_usefulness[idx] = 0.0
        end
    end
    
    if !isempty(tile_usefulness)
        worst_idx = argmin(tile_usefulness)
        return game_state.my_hand[worst_idx]
    end
    
    return !isempty(game_state.my_hand) ? game_state.my_hand[1] : nothing
end

"""
Pure Random AI: Completely random decision making
"""
function pure_random_decision(game_state::GameState)
    if !isempty(game_state.my_hand)
        return rand(game_state.my_hand)
    else
        return nothing
    end
end

# ============================================================================
# GAME SIMULATION
# ============================================================================

"""
Simulate one turn with specified player types
"""
function simulate_turn_multi(game_state::GameState, 
                             game_log::Dict,
                             player1_type::Symbol,
                             player2_type::Symbol,
                             player1_nervousness::Int,
                             player2_nervousness::Int,
                             player1_committed_ref::Ref{Union{Int,Nothing}},
                             player2_committed_ref::Ref{Union{Int,Nothing}})
    
    if game_state.wall_remaining <= 0
        return :wall_empty
    end
    
    turn_num = game_state.turn
    
    # ========================================================================
    # PLAYER 1 TURN
    # ========================================================================
    
    # Draw tile
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
    
    # Make decision based on player type
    discard_tile = nothing
    
    if player1_type == :bayesian
        # Use Bayesian AI with nervousness
        temp_state = GameState(
            game_state.my_hand,
            game_state.discards,
            game_state.opponents,
            game_state.opponent_exposed,
            game_state.wall_remaining,
            game_state.turn,
            game_state.viable_hands[1:min(10, end)],
            game_state.all_hands,
            game_state.committed_hand_id,
            game_state.exposed_sets,
            game_state.opponent_discards,
            game_state.turns_since_progress,
            game_state.last_progress_value
        )
        
        decision = make_decision(temp_state, drawn_tile, [Dict{Int,Int}()], false, player1_nervousness)
        
        if temp_state.committed_hand_id !== nothing
            game_state.committed_hand_id = temp_state.committed_hand_id
        end
        game_state.turns_since_progress = temp_state.turns_since_progress
        game_state.last_progress_value = temp_state.last_progress_value
        
        if decision[1] == :commit && length(decision) >= 3
            discard_tile = decision[3]
        elseif length(decision) >= 2
            discard_tile = decision[2]
        end
        
    elseif player1_type == :greedy
        # Use greedy AI with nervousness
        temp_state = GameState(
            game_state.my_hand,
            game_state.discards,
            game_state.opponents,
            game_state.opponent_exposed,
            game_state.wall_remaining,
            game_state.turn,
            game_state.viable_hands[1:min(10, end)],
            game_state.all_hands,
            game_state.committed_hand_id,
            game_state.exposed_sets,
            game_state.opponent_discards,
            game_state.turns_since_progress,
            game_state.last_progress_value
        )
        
        decision = make_decision(temp_state, drawn_tile, [Dict{Int,Int}()], false, player1_nervousness)
        
        if temp_state.committed_hand_id !== nothing
            game_state.committed_hand_id = temp_state.committed_hand_id
        end
        game_state.turns_since_progress = temp_state.turns_since_progress
        game_state.last_progress_value = temp_state.last_progress_value
        
        if decision[1] == :commit && length(decision) >= 3
            discard_tile = decision[3]
        elseif length(decision) >= 2
            discard_tile = decision[2]
        end
        
    elseif player1_type == :random_commit
        discard_tile = random_commit_decision(game_state, player1_committed_ref)
        
    elseif player1_type == :pure_random
        discard_tile = pure_random_decision(game_state)
    end
    
    # Execute discard
    if discard_tile !== nothing
        idx = findfirst(t -> t.name == discard_tile.name, game_state.my_hand)
        if idx !== nothing
            deleteat!(game_state.my_hand, idx)
            push!(game_state.discards, discard_tile)
        end
    end
    
    # ========================================================================
    # PLAYER 2 (OPPONENT) TURN
    # ========================================================================
    
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
            
            # Opponent decision based on type
            opponent_discard = nothing
            
            if player2_type == :bayesian
                # Bayesian AI for opponent (with diversity awareness)
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
                    [opp_opponent_info],
                    player2_nervousness
                )
                
            elseif player2_type == :greedy
                # Greedy AI for opponent
                opponent_discard, _ = opponent_make_decision_diverse(
                    game_state.opponents[1],
                    game_state.all_hands,
                    all_seen,
                    game_state.opponent_exposed[1],
                    [Dict{Int,Int}()],
                    player2_nervousness
                )
                
            elseif player2_type == :random_commit
                # Create temporary game state for opponent
                temp_opp_state = GameState(
                    game_state.opponents[1],
                    game_state.discards,
                    [game_state.my_hand],
                    [game_state.exposed_sets],
                    game_state.wall_remaining,
                    game_state.turn,
                    opp_viable,
                    game_state.all_hands,
                    nothing,
                    game_state.opponent_exposed[1],
                    [Tile[]],
                    0,
                    nothing
                )
                
                opponent_discard = random_commit_decision(temp_opp_state, player2_committed_ref)
                
            elseif player2_type == :pure_random
                if !isempty(game_state.opponents[1])
                    opponent_discard = rand(game_state.opponents[1])
                end
            end
            
            # Execute opponent discard
            if opponent_discard !== nothing
                opp_idx = findfirst(t -> t.name == opponent_discard.name, game_state.opponents[1])
                if opp_idx !== nothing
                    deleteat!(game_state.opponents[1], opp_idx)
                end
                push!(game_state.opponent_discards[1], opponent_discard)
                push!(game_state.discards, opponent_discard)
            end
        end
    end
    
    game_state.turn += 1
    return :continue
end

"""
Simulate full game with reshuffle capability
"""
function simulate_game_multi(all_hands::Vector{MahjongHand},
                             player1_type::Symbol,
                             player2_type::Symbol,
                             player1_nervousness::Int,
                             player2_nervousness::Int,
                             max_total_turns::Int=200)
    
    game_log = Dict{Symbol, Any}(
        :reshuffled => false,
        :reshuffle_turn => 0
    )
    
    # Committed hand refs for random_commit players
    player1_committed_ref = Ref{Union{Int,Nothing}}(nothing)
    player2_committed_ref = Ref{Union{Int,Nothing}}(nothing)
    
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
        result = simulate_turn_multi(
            game_state, 
            game_log,
            player1_type,
            player2_type,
            player1_nervousness,
            player2_nervousness,
            player1_committed_ref,
            player2_committed_ref
        )
        
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
                
                # Reset committed hands
                game_state.committed_hand_id = nothing
                player1_committed_ref[] = nothing
                player2_committed_ref[] = nothing
                
                # Keep nervousness tracking for Bayesian/Greedy
                # (already persists in game_state)
                
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
Run comprehensive player comparison with CSV export and progress tracking
"""
function run_player_comparison(n_games::Int=200; max_turns::Int=200)
    println("\n" * "="^80)
    println("🎮 COMPREHENSIVE PLAYER COMPARISON")
    println("="^80)
    println("Games per configuration: $n_games")
    println("Max turns per game: $max_turns")
    println("Reshuffle on first draw: enabled")
    
    # Create output directory
    output_dir = "comparison_results_$(Dates.format(now(), "yyyymmdd_HHMMSS"))"
    mkdir(output_dir)
    println("Output directory: $output_dir")
    
    # Load hands once
    println("\nLoading hand patterns...")
    all_hands = generate_mahjong_hands()
    println("✓ Loaded $(length(all_hands)) unique hands\n")
    
    # Player types
    player_types = [:bayesian, :greedy, :random_commit, :pure_random]
    player_names = Dict(
        :bayesian => "Bayesian AI",
        :greedy => "Greedy AI",
        :random_commit => "Random-Commit AI",
        :pure_random => "Pure Random AI"
    )
    
    # Nervousness values to test
    nervousness_values = [10, 5, 3]
    
    # Store all results
    all_results = Dict()
    csv_rows = []
    
    # Generate all unique pairings
    pairings = []
    for i in 1:length(player_types)
        for j in i:length(player_types)
            push!(pairings, (player_types[i], player_types[j]))
        end
    end
    
    println("Testing $(length(pairings)) unique pairings:")
    for (p1, p2) in pairings
        println("  - $(player_names[p1]) vs $(player_names[p2])")
    end
    println()
    
    # Count total configurations for time estimation
    total_configs = 0
    for (p1, p2) in pairings
        p1_can_be_nervous = p1 in [:bayesian, :greedy]
        p2_can_be_nervous = p2 in [:bayesian, :greedy]
        
        if p1_can_be_nervous && p2_can_be_nervous
            total_configs += 1 + length(nervousness_values) + length(nervousness_values) + (length(nervousness_values)^2)
        elseif p1_can_be_nervous || p2_can_be_nervous
            total_configs += 1 + length(nervousness_values)
        else
            total_configs += 1
        end
    end
    
    println("Total configurations to test: $total_configs")
    println("Estimated time: ~$(round(total_configs * n_games * 0.05 / 60, digits=1)) minutes\n")
    
    config_counter = 0
    start_time = time()
    
    # Test each pairing
    for (player1_type, player2_type) in pairings
        println("\n" * "█"^80)
        println("█  $(player_names[player1_type]) vs $(player_names[player2_type])")
        println("█"^80)
        
        # Determine nervousness configurations
        p1_can_be_nervous = player1_type in [:bayesian, :greedy]
        p2_can_be_nervous = player2_type in [:bayesian, :greedy]
        
        configs = []
        
        if p1_can_be_nervous && p2_can_be_nervous
            # Both can be nervous - test all combinations
            push!(configs, ("neither", 999, 999))
            for n1 in nervousness_values
                push!(configs, ("p1_only", n1, 999))
            end
            for n2 in nervousness_values
                push!(configs, ("p2_only", 999, n2))
            end
            for n1 in nervousness_values
                for n2 in nervousness_values
                    push!(configs, ("both", n1, n2))
                end
            end
        elseif p1_can_be_nervous
            # Only player 1 can be nervous
            push!(configs, ("neither", 999, 999))
            for n1 in nervousness_values
                push!(configs, ("p1_only", n1, 999))
            end
        elseif p2_can_be_nervous
            # Only player 2 can be nervous
            push!(configs, ("neither", 999, 999))
            for n2 in nervousness_values
                push!(configs, ("p2_only", 999, n2))
            end
        else
            # Neither can be nervous
            push!(configs, ("neither", 999, 999))
        end
        
        # Run each configuration
        for (config_name, p1_nerv, p2_nerv) in configs
            config_counter += 1
            
            config_desc = if config_name == "neither"
                "Neither nervous"
            elseif config_name == "p1_only"
                "P1 nervous ($p1_nerv)"
            elseif config_name == "p2_only"
                "P2 nervous ($p2_nerv)"
            else
                "Both nervous (P1:$p1_nerv, P2:$p2_nerv)"
            end
            
            # Time estimation
            elapsed = time() - start_time
            avg_time_per_config = elapsed / config_counter
            remaining_configs = total_configs - config_counter
            est_remaining_mins = (remaining_configs * avg_time_per_config) / 60
            
            println("\n" * "-"^80)
            println("  Configuration $config_counter/$total_configs: $config_desc")
            println("  Estimated time remaining: $(round(est_remaining_mins, digits=1)) minutes")
            println("-"^80)
            
            results = Dict(
                :player_won => 0,
                :opponent_won => 0,
                :draw => 0,
                :timeout => 0
            )
            
            games_reshuffled = 0
            wins_after_reshuffle = 0
            wins_before_reshuffle = 0
            
            game_logs = []
            
            # Run games
            for i in 1:n_games
                Random.seed!(i + hash((player1_type, player2_type, p1_nerv, p2_nerv)))
                
                game_log = simulate_game_multi(
                    all_hands,
                    player1_type,
                    player2_type,
                    p1_nerv,
                    p2_nerv,
                    max_turns
                )
                
                push!(game_logs, game_log)
                
                outcome = game_log[:outcome]
                results[outcome] += 1
                
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
                
                if i % 100 == 0
                    print(".")
                    flush(stdout)
                end
            end
            
            println()
            
            # Enhanced draw analysis
            draw_games = [log for log in game_logs if log[:outcome] == :draw]
            draw_analysis = analyze_draw_details(draw_games)
            
            # Print results
            total_decisive = results[:player_won] + results[:opponent_won]
            
            println("\n  🎯 Win Statistics:")
            println("     P1 ($(player_names[player1_type])) wins:  $(results[:player_won])/$n_games ($(round(results[:player_won]/n_games*100, digits=1))%)")
            println("     P2 ($(player_names[player2_type])) wins:  $(results[:opponent_won])/$n_games ($(round(results[:opponent_won]/n_games*100, digits=1))%)")
            println("     Draws:                                    $(results[:draw])/$n_games ($(round(results[:draw]/n_games*100, digits=1))%)")
            println("     Timeouts:                                 $(results[:timeout])/$n_games ($(round(results[:timeout]/n_games*100, digits=1))%)")
            
            if total_decisive > 0
                println("\n  🏆 Decisive Games Only:")
                println("     P1 win rate:   $(round(results[:player_won]/total_decisive*100, digits=1))%")
                println("     P2 win rate:   $(round(results[:opponent_won]/total_decisive*100, digits=1))%")
            end
            
            println("\n  🔄 Reshuffle Statistics:")
            println("     Games reshuffled: $games_reshuffled/$n_games ($(round(games_reshuffled/n_games*100, digits=1))%)")
            
            if games_reshuffled > 0
                reshuffled_games = [log for log in game_logs if log[:reshuffled]]
                r_wins = length([log for log in reshuffled_games if log[:outcome] in [:player_won, :opponent_won]])
                r_draws = length([log for log in reshuffled_games if log[:outcome] == :draw])
                
                println("     Resolved after reshuffle: $r_wins/$games_reshuffled ($(round(r_wins/games_reshuffled*100, digits=1))%)")
                println("     Drew again:               $r_draws/$games_reshuffled ($(round(r_draws/games_reshuffled*100, digits=1))%)")
            end
            
            # Enhanced draw analysis output
            if !isempty(draw_games)
                println("\n  📉 Enhanced Draw Analysis:")
                println("     Total draws:           $(draw_analysis[:total_draws])/$n_games ($(round(draw_analysis[:total_draws]/n_games*100, digits=1))%)")
                println("     Pattern overlap:       $(draw_analysis[:pattern_overlap])/$(draw_analysis[:total_draws]) ($(round(draw_analysis[:pattern_overlap]/draw_analysis[:total_draws]*100, digits=1))%)")
                println("     Similar progress:      $(draw_analysis[:similar_progress])/$(draw_analysis[:total_draws]) ($(round(draw_analysis[:similar_progress]/draw_analysis[:total_draws]*100, digits=1))%)")
                println("     Both stuck (<70%):     $(draw_analysis[:both_stuck])/$(draw_analysis[:total_draws]) ($(round(draw_analysis[:both_stuck]/draw_analysis[:total_draws]*100, digits=1))%)")
                println("     Both high (≥70%):      $(draw_analysis[:both_high_progress])/$(draw_analysis[:total_draws]) ($(round(draw_analysis[:both_high_progress]/draw_analysis[:total_draws]*100, digits=1))%)")
                println("     Both low (<50%):       $(draw_analysis[:both_low_progress])/$(draw_analysis[:total_draws]) ($(round(draw_analysis[:both_low_progress]/draw_analysis[:total_draws]*100, digits=1))%)")
                println("     P1 stuck, P2 ahead:    $(draw_analysis[:p1_stuck_p2_ahead])/$(draw_analysis[:total_draws]) ($(round(draw_analysis[:p1_stuck_p2_ahead]/draw_analysis[:total_draws]*100, digits=1))%)")
                println("     P2 stuck, P1 ahead:    $(draw_analysis[:p2_stuck_p1_ahead])/$(draw_analysis[:total_draws]) ($(round(draw_analysis[:p2_stuck_p1_ahead]/draw_analysis[:total_draws]*100, digits=1))%)")
                println("     Avg final P1 progress: $(round(draw_analysis[:avg_final_p1_progress]*100, digits=1))%")
                println("     Avg final P2 progress: $(round(draw_analysis[:avg_final_p2_progress]*100, digits=1))%")
                println("     Avg turns to draw:     $(round(draw_analysis[:avg_turns], digits=1))")
            end
            
            # Store results
            key = (player1_type, player2_type, config_name, p1_nerv, p2_nerv)
            all_results[key] = Dict(
                :results => results,
                :games_reshuffled => games_reshuffled,
                :wins_before => wins_before_reshuffle,
                :wins_after => wins_after_reshuffle,
                :logs => game_logs,
                :draw_analysis => draw_analysis
            )
            
            # Add to CSV rows
            csv_row = Dict(
                "player1_type" => string(player1_type),
                "player2_type" => string(player2_type),
                "config_name" => config_name,
                "p1_nervousness" => p1_nerv == 999 ? "none" : string(p1_nerv),
                "p2_nervousness" => p2_nerv == 999 ? "none" : string(p2_nerv),
                "total_games" => n_games,
                "p1_wins" => results[:player_won],
                "p2_wins" => results[:opponent_won],
                "draws" => results[:draw],
                "timeouts" => results[:timeout],
                "p1_win_pct" => round(results[:player_won]/n_games*100, digits=2),
                "p2_win_pct" => round(results[:opponent_won]/n_games*100, digits=2),
                "draw_pct" => round(results[:draw]/n_games*100, digits=2),
                "decisive_games" => total_decisive,
                "p1_win_rate_decisive" => total_decisive > 0 ? round(results[:player_won]/total_decisive*100, digits=2) : 0.0,
                "p2_win_rate_decisive" => total_decisive > 0 ? round(results[:opponent_won]/total_decisive*100, digits=2) : 0.0,
                "games_reshuffled" => games_reshuffled,
                "reshuffle_pct" => round(games_reshuffled/n_games*100, digits=2),
                "wins_before_reshuffle" => wins_before_reshuffle,
                "wins_after_reshuffle" => wins_after_reshuffle,
                "draw_pattern_overlap" => draw_analysis[:pattern_overlap],
                "draw_pattern_overlap_pct" => draw_analysis[:total_draws] > 0 ? round(draw_analysis[:pattern_overlap]/draw_analysis[:total_draws]*100, digits=2) : 0.0,
                "draw_similar_progress" => draw_analysis[:similar_progress],
                "draw_both_stuck" => draw_analysis[:both_stuck],
                "draw_both_high_progress" => draw_analysis[:both_high_progress],
                "draw_both_low_progress" => draw_analysis[:both_low_progress],
                "draw_p1_stuck_p2_ahead" => draw_analysis[:p1_stuck_p2_ahead],
                "draw_p2_stuck_p1_ahead" => draw_analysis[:p2_stuck_p1_ahead],
                "draw_avg_p1_progress" => round(draw_analysis[:avg_final_p1_progress]*100, digits=2),
                "draw_avg_p2_progress" => round(draw_analysis[:avg_final_p2_progress]*100, digits=2),
                "draw_avg_turns" => round(draw_analysis[:avg_turns], digits=2)
            )
            push!(csv_rows, csv_row)
            
            # Periodic save every 5 configs
            if config_counter % 5 == 0
                df = DataFrame(csv_rows)
                CSV.write(joinpath(output_dir, "intermediate_results.csv"), df)
                println("\n  💾 Intermediate results saved")
            end
        end
    end
    
    # ========================================================================
    # FINAL CSV EXPORT
    # ========================================================================
    
    println("\n\n" * "="^80)
    println("💾 SAVING RESULTS TO CSV")
    println("="^80)
    
    df = DataFrame(csv_rows)
    csv_path = joinpath(output_dir, "player_comparison_results.csv")
    CSV.write(csv_path, df)
    println("✓ Saved to: $csv_path")
    
    # ========================================================================
    # FINAL SUMMARY
    # ========================================================================
    
    println("\n" * "="^80)
    println("📊 COMPREHENSIVE SUMMARY")
    println("="^80)
    
    for (player1_type, player2_type) in pairings
        println("\n$(player_names[player1_type]) vs $(player_names[player2_type]):")
        
        # Find all configs for this pairing
        pairing_keys = [k for k in keys(all_results) if k[1] == player1_type && k[2] == player2_type]
        
        for key in sort(pairing_keys)
            (_, _, config_name, p1_nerv, p2_nerv) = key
            data = all_results[key]
            results = data[:results]
            total_decisive = results[:player_won] + results[:opponent_won]
            
            config_label = if config_name == "neither"
                "  Neither nervous"
            elseif config_name == "p1_only"
                "  P1 nerv=$p1_nerv"
            elseif config_name == "p2_only"
                "  P2 nerv=$p2_nerv"
            else
                "  Both (P1:$p1_nerv,P2:$p2_nerv)"
            end
            
            println("$config_label:")
            println("    Draws: $(results[:draw])/$n_games ($(round(results[:draw]/n_games*100, digits=1))%)")
            
            if total_decisive > 0
                println("    P1 wins: $(results[:player_won])/$total_decisive decisive ($(round(results[:player_won]/total_decisive*100, digits=1))%)")
                println("    P2 wins: $(results[:opponent_won])/$total_decisive decisive ($(round(results[:opponent_won]/total_decisive*100, digits=1))%)")
            end
        end
    end
    
    total_time = time() - start_time
    println("\n" * "="^80)
    println("✅ Benchmark complete!")
    println("   Total time: $(round(total_time/60, digits=1)) minutes")
    println("   Results saved to: $output_dir/")
    println("="^80)
    
    return all_results
end

# ============================================================================
# MAIN
# ============================================================================

if abspath(PROGRAM_FILE) == @__FILE__
    all_results = run_player_comparison(200, max_turns=200)
end