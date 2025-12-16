using Gen
using Random

include("mahjong_model.jl")
include("mahjong_hands.jl")

# ============================================================================
# GAME SIMULATION (SIMPLIFIED - NO OPPONENT TRACKING)
# ============================================================================

"""
Simulate a complete turn in Mahjong
"""
function simulate_turn(game_state::GameState, verbose::Bool=true)

    if game_state.wall_remaining <= 0
        if verbose
            println("\nWall is empty! Game over.")
        end
        return nothing
    end
    
    if verbose
        println("\n" * "=" ^ 60)
        println("TURN $(game_state.turn)")
        println("=" ^ 60)
        println("\nWall remaining: $(game_state.wall_remaining)")
        println("Discard pot: $(length(game_state.discards)) tiles")
        println("\nMy hand ($(length(game_state.my_hand)) tiles):")
        for (i, tile) in enumerate(game_state.my_hand)
            println("  $i. $(tile.name)")
        end
        if !isempty(game_state.exposed_sets)
            println("\nExposed sets:")
            for (i, set) in enumerate(game_state.exposed_sets)
                println("  $i. $(join([t.name for t in set], ", "))")
            end
        end
    end
    
    # Draw a tile for me
    wall_tiles = generate_remaining_wall(vcat(
        game_state.my_hand, 
        game_state.discards,
        reduce(vcat, game_state.opponents, init=Tile[])
    ))
    
    if isempty(wall_tiles)
        if verbose
            println("\nWall is empty! Game over.")
        end
        return nothing
    end
    
    drawn_tile = rand(wall_tiles)
    push!(game_state.my_hand, drawn_tile)
    game_state.wall_remaining -= 1
    
    if verbose
        println("\n→ Drew: $(drawn_tile.name)")
    end
    
    # Update viable hands
    # Flatten opponent_exposed properly (it's Vector{Vector{Vector{Tile}}})
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
    
    # Sort viable hands by fewest tiles needed (most achievable first)
    if !isempty(game_state.viable_hands)
        sorted_hands = sort(game_state.viable_hands, by=hand -> length(tiles_needed_for_hand(hand, game_state.my_hand, game_state.exposed_sets)))
        game_state.viable_hands = sorted_hands
    end
    
    if verbose
        println("\nViable hands: $(length(game_state.viable_hands))")
        if !isempty(game_state.viable_hands)
            println("Top 3 most achievable:")
            for (i, hand) in enumerate(game_state.viable_hands[1:min(3, end)])
                needed = tiles_needed_for_hand(hand, game_state.my_hand, game_state.exposed_sets)
                println("  $i. $(hand.pattern_name) ($(hand.point_value) pts) - need $(length(needed)) tiles")
            end
        end
    end
    
    # Check if we won
    for hand in game_state.viable_hands
        needed = tiles_needed_for_hand(hand, game_state.my_hand, game_state.exposed_sets)
        if isempty(needed)
            if verbose
                println("\n" * "🎉" ^ 30)
                println("MAHJONG! Won with: $(hand.pattern_name)")
                println("Points: $(hand.point_value)")
                println("🎉" ^ 30)
            end
            return :won
        end
    end
    
   # Make decision (no opponent analysis)
    hands_to_evaluate = game_state.viable_hands[1:min(10, end)]
    temp_state = GameState(
        game_state.my_hand,
        game_state.discards,
        game_state.opponents,
        game_state.opponent_exposed,
        game_state.wall_remaining,      # 5. Int
        game_state.turn,                # 6. Int
        hands_to_evaluate,              # 7. viable_hands
        game_state.all_hands,           # 8. all_hands
        game_state.committed_hand_id,   # 9. committed_hand_id
        game_state.exposed_sets,        # 10. exposed_sets
        game_state.opponent_discards    # 11. opponent_discards
    )
    
    # Get Monte Carlo scores
    hand_scores = evaluate_hands(temp_state, 30)
    
    # Pass empty opponent data since we're not tracking them
    decision = make_decision(temp_state, drawn_tile, [Dict{Int,Int}()], verbose)

    if temp_state.committed_hand_id !== nothing
        game_state.committed_hand_id = temp_state.committed_hand_id
    end
    
    # Execute decision - discard a tile
    discard_tile = nothing
    if decision[1] == :commit && length(decision) >= 3
        if verbose
            hand_idx = findfirst(h -> h.id == decision[2], game_state.viable_hands)
            if hand_idx !== nothing
                hand = game_state.viable_hands[hand_idx]
                needed = tiles_needed_for_hand(hand, game_state.my_hand, game_state.exposed_sets)
                mc_score = get(hand_scores, hand.id, 0.0)
                println("\n✓ Committed to: $(hand.pattern_name) ($(hand.point_value) pts)")
                println("  Still need $(length(needed)) tiles: $(unique([t.name for t in needed]))")
                println("  Monte Carlo score: $(round(mc_score, digits=3))")
            end
        end
        discard_tile = decision[3]

    elseif length(decision) >= 2
        if verbose && decision[1] == :flexible
            println("\n↔ Staying flexible")
        end
        discard_tile = decision[2]
    end
    
    # Discard my tile
    if discard_tile !== nothing
        idx = findfirst(t -> t.name == discard_tile.name, game_state.my_hand)
        if idx !== nothing
            deleteat!(game_state.my_hand, idx)
            push!(game_state.discards, discard_tile)
            if verbose
                println("→ Discarding: $(discard_tile.name)")
            end
        end
    end
    
    # Simulate opponent turn - they draw and discard strategically
    if !isempty(wall_tiles) && length(wall_tiles) > 1
        # Opponent draws
        game_state.wall_remaining -= 1
        # Recalculate wall after my discard
        wall_tiles_after_my_discard = generate_remaining_wall(vcat(
            game_state.my_hand, 
            game_state.discards,
            reduce(vcat, game_state.opponents, init=Tile[])
        ))

        if !isempty(wall_tiles_after_my_discard)
            opponent_drawn = rand(wall_tiles_after_my_discard)
            
            # Add to opponent's hand (opponent 1)
            push!(game_state.opponents[1], opponent_drawn)
            
            # Opponent makes strategic decision
            # IMPORTANT: Opponent can only see discards and their own hand, NOT player's hand
            all_seen = vcat(game_state.discards, 
                            reduce(vcat, game_state.opponents, init=Tile[]))
            
            opponent_discard, opp_hand_info = opponent_make_decision(
                game_state.opponents[1],
                game_state.all_hands,
                all_seen,
                game_state.opponent_exposed[1]
            )
            
            # Remove from opponent's hand
            opp_idx = findfirst(t -> t.name == opponent_discard.name, game_state.opponents[1])
            if opp_idx !== nothing
                deleteat!(game_state.opponents[1], opp_idx)
            end

            # Track this discard
            push!(game_state.opponent_discards[1], opponent_discard)

            # Infer what opponent is pursuing
            all_seen = vcat(game_state.discards, 
                            reduce(vcat, game_state.opponents, init=Tile[]))

            opponent_posterior = infer_opponent_hands(
                game_state.opponents[1],
                game_state.all_hands,
                all_seen,
                game_state.opponent_discards[1],  # Historical discards
                game_state.opponent_exposed[1],
                100  # Number of particles (higher = more accurate but slower)
            )

            if verbose && !isempty(opponent_posterior)
                println("\n  📊 Opponent Hand Posterior:")
                sorted_posterior = sort(collect(opponent_posterior), by=x->x[2], rev=true)
                
                # Track unique patterns to avoid showing duplicates
                pattern_probs = Dict{String, Float64}()
                for (hand_id, prob) in sorted_posterior
                    hand_idx = findfirst(h -> h.id == hand_id, game_state.all_hands)
                    if hand_idx !== nothing
                        hand_obj = game_state.all_hands[hand_idx]
                        pattern = hand_obj.pattern_name
                        pattern_probs[pattern] = get(pattern_probs, pattern, 0.0) + prob
                    end
                end
                
                # Show unique patterns
                sorted_patterns = sort(collect(pattern_probs), by=x->x[2], rev=true)
                for (i, (pattern, prob)) in enumerate(sorted_patterns[1:min(3, end)])
                    println("     $(i). $(round(prob*100, digits=1))% - $(pattern)")
                end
            end
            
            if verbose
                println("\n→ Opponent drew: $(opponent_drawn.name)")
                if opp_hand_info !== nothing
                    println("  Opponent pursuing: $(opp_hand_info[:hand_name])")
                    println("  Opponent progress: $(opp_hand_info[:progress])%")
                    println("  Opponent needs: $(join(opp_hand_info[:needs], ", "))")
                end
                println("→ Opponent discarded: $(opponent_discard.name)")
            end

            # CHECK: Can I claim this tile?
            can_claim, set_type, completing_tiles = can_claim_tile(opponent_discard, game_state)
            
            if can_claim
                if set_type == :mahjong
                    # WE WON!
                    if verbose
                        println("\n🎉 CLAIMED for MAHJONG!")
                        hand_idx = findfirst(h -> h.id == game_state.committed_hand_id, game_state.viable_hands)
                        if hand_idx !== nothing
                            hand = game_state.viable_hands[hand_idx]
                            println("Won with: $(hand.pattern_name)")
                            println("Points: $(hand.point_value)")
                        end
                    end
                    return :won
                else
                    # Claim for pung/kong
                    claim_tile!(opponent_discard, game_state, set_type, completing_tiles)
                    
                    if verbose
                        println("✋ CLAIMED $(opponent_discard.name) for $(uppercase(string(set_type)))!")
                        println("   Exposed set: $(join([t.name for t in completing_tiles], ", "))")
                        println("   Total exposed sets: $(length(game_state.exposed_sets))")
                    end
                    
                    # Now we must discard since we claimed
                    hand_idx = findfirst(h -> h.id == game_state.committed_hand_id, game_state.viable_hands)
                    if hand_idx !== nothing
                        discard_after_claim = find_best_discard(game_state, game_state.committed_hand_id)
                        if discard_after_claim !== nothing
                            idx = findfirst(t -> t.name == discard_after_claim.name, game_state.my_hand)
                            if idx !== nothing
                                deleteat!(game_state.my_hand, idx)
                                push!(game_state.discards, discard_after_claim)
                                if verbose
                                    println("→ Discarding after claim: $(discard_after_claim.name)")
                                end
                            end
                        end
                    end
                end
            else
                # Tile goes to pot
                push!(game_state.discards, opponent_discard)
                if verbose
                    println("   → Goes to discard pot")
                end
            end
        end
    end
    
    # Increment turn
    game_state.turn += 1
    
    return :continue
end

"""
Run a full game simulation
"""
function simulate_game(; max_turns=50, verbose=true)
    if verbose
        println("\n" * "🀄" ^ 30)
        println("Starting New Mahjong Game")
        println("🀄" ^ 30)
    end
    
    # Generate all possible hands
    all_hands = generate_mahjong_hands()
    if verbose
        println("\nLoaded $(length(all_hands)) hands from card")
    end
    
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
            my_hand,                    # 1. my_hand
            Tile[],                     # 2. discards
            [opponent_hand],            # 3. opponents
            [Vector{Tile}[]],           # 4. opponent_exposed
            length(all_tiles) - 26,     # 5. wall_remaining (Int!)
            1,                          # 6. turn (Int!)
            viable_hands,               # 7. viable_hands
            all_hands,                  # 8. all_hands
            nothing,                    # 9. committed_hand_id
            Vector{Tile}[],             # 10. exposed_sets
            [Tile[]]                    # 11. opponent_discards
        )
    
    if verbose
        println("Starting with $(length(viable_hands)) viable hands\n")
    end
    
    # Play turns
    for turn in 1:max_turns
        result = simulate_turn(game_state, verbose)
        
        if result == :won
            if verbose
                println("\n" * "🏆" ^ 30)
                println("VICTORY in $(game_state.turn - 1) turns!")
                println("🏆" ^ 30)
            end
            return :won
        elseif result === nothing
            if verbose
                println("\nGame ended - wall exhausted")
            end
            return :draw
        end
    end
    
    if verbose
        println("\nMax turns reached")
    end
    return :timeout
end

# ============================================================================
# MAIN
# ============================================================================

if abspath(PROGRAM_FILE) == @__FILE__
    Random.seed!(42)
    simulate_game(max_turns=70, verbose=true)
end

# julia --project=. run_simulation.jl