using Gen
using Distributions
using Random

# Include hand generation
# Note: Comment this out if running standalone without mahjong_hands.jl
# include("mahjong_hands.jl")

# Declare function if not including mahjong_hands.jl
function tiles_needed_for_hand end
function get_viable_hands end

# ============================================================================
# GAME STATE STRUCTURES
# ============================================================================

struct Tile
    name::String  # e.g., "3 Bamboo", "Red Dragon", "Flower", "North Wind"
end

Base.:(==)(t1::Tile, t2::Tile) = t1.name == t2.name
Base.hash(t::Tile, h::UInt) = hash(t.name, h)

struct MahjongHand
    id::Int
    pattern_name::String
    required_tiles::Vector{Tile}
    point_value::Int
end

mutable struct GameState
    my_hand::Vector{Tile}
    discards::Vector{Tile}
    opponents::Vector{Vector{Tile}}
    opponent_exposed::Vector{Vector{Vector{Tile}}}
    wall_remaining::Int
    turn::Int
    viable_hands::Vector{MahjongHand}
    all_hands::Vector{MahjongHand}
    committed_hand_id::Union{Int, Nothing}
    exposed_sets::Vector{Vector{Tile}}
    opponent_discards::Vector{Vector{Tile}}
    
    turns_since_progress::Int          # How many turns without progress
    last_progress_value::Union{Float64, Nothing}  # Last progress percentage
end

# ============================================================================
# TILE PROBABILITY TRACKING
# ============================================================================

"""
Calculate probability of drawing needed tiles from wall
"""
function tile_probability(needed_tiles::Vector{Tile}, 
                         seen_tiles::Vector{Tile}, 
                         wall_remaining::Int)
    if isempty(needed_tiles)
        return 1.0
    end
    
    # Count unique needed tiles and their availability
    unseen_count = 0
    for needed in unique(needed_tiles)
        count_in_seen = count(t -> t.name == needed.name, seen_tiles)
        total_count = tile_total_count(needed)
        unseen_count += max(0, total_count - count_in_seen)
    end
    
    if wall_remaining == 0
        return 0.0
    end
    
    # Probability at least one needed tile appears in next few draws
    return 1.0 - ((wall_remaining - unseen_count) / wall_remaining)^min(5, wall_remaining)
end

function tile_total_count(tile::Tile)
    if tile.name == "Flower"
        return 8  # American Mahjong has 8 jokers (called flowers here)
    elseif occursin("Dragon", tile.name) || occursin("Wind", tile.name)
        return 4
    else
        return 4  # 4 of each suited tile
    end
end

# ============================================================================
# PATTERN EVALUATION
# ============================================================================

function tiles_needed_for_hand(hand::MahjongHand, my_tiles::Vector{Tile}, exposed_sets::Vector{Vector{Tile}}=Vector{Tile}[])
    needed = Tile[]
    
    required_counts = Dict{String, Int}()
    for tile in hand.required_tiles
        required_counts[tile.name] = get(required_counts, tile.name, 0) + 1
    end
    
    have_counts = Dict{String, Int}()
    # Count tiles in hand
    for tile in my_tiles
        have_counts[tile.name] = get(have_counts, tile.name, 0) + 1
    end
    # Count tiles in exposed sets
    for set in exposed_sets
        for tile in set
            have_counts[tile.name] = get(have_counts, tile.name, 0) + 1
        end
    end
    
    for (tile_name, required) in required_counts
        have = get(have_counts, tile_name, 0)
        if have < required
            for _ in 1:(required - have)
                push!(needed, Tile(tile_name))
            end
        end
    end
    
    return needed
end

"""
Calculate how many tiles (outs) would advance a hand
"""
function calculate_outs(hand::MahjongHand, 
                       current_hand::Vector{Tile},
                       seen_tiles::Vector{Tile})
    needed = tiles_needed_for_hand(hand, current_hand)
    
    # Get unique tiles that are still available
    outs = Tile[]
    unique_needed = unique(needed)
    
    for tile in unique_needed
        count_in_seen = count(t -> t.name == tile.name, seen_tiles)
        if count_in_seen < tile_total_count(tile)
            push!(outs, tile)
        end
    end
    
    return length(outs), outs
end

"""
Check if we can claim a discarded tile to complete a set
Returns: (can_claim::Bool, set_type::Symbol, completing_tiles::Vector{Tile})
set_type can be :pung (3 of a kind), :kong (4 of a kind), or :mahjong (winning)
"""
function can_claim_tile(tile::Tile, game_state::GameState)
    # Only claim if we've committed to a hand
    if game_state.committed_hand_id === nothing
        return (false, :none, Tile[])
    end
    
    # Find the committed hand
    hand_idx = findfirst(h -> h.id == game_state.committed_hand_id, game_state.viable_hands)
    if hand_idx === nothing
        return (false, :none, Tile[])
    end
    
    committed_hand = game_state.viable_hands[hand_idx]
    
    # Check if this tile is needed for the hand
    needed = tiles_needed_for_hand(committed_hand, game_state.my_hand)
    if !any(t -> t.name == tile.name, needed)
        return (false, :none, Tile[])
    end
    
    # Count how many of this tile we have
    count_in_hand = count(t -> t.name == tile.name, game_state.my_hand)
    
    # Check for Mahjong (winning)
    if length(needed) == 1 && needed[1].name == tile.name
        return (true, :mahjong, Tile[tile])
    end
    
    # Check for pung (need 3 total, have 2)
    if count_in_hand == 2
        matching_tiles = [t for t in game_state.my_hand if t.name == tile.name]
        return (true, :pung, vcat(matching_tiles, [tile]))
    end
    
    # Check for kong (need 4 total, have 3)
    if count_in_hand == 3
        matching_tiles = [t for t in game_state.my_hand if t.name == tile.name]
        return (true, :kong, vcat(matching_tiles, [tile]))
    end
    
    return (false, :none, Tile[])
end

"""
Claim a discarded tile and expose the set
"""
function claim_tile!(tile::Tile, game_state::GameState, set_type::Symbol, completing_tiles::Vector{Tile})
    # Add the claimed tile to hand
    push!(game_state.my_hand, tile)
    
    # Remove the completing tiles from hand and add to exposed sets
    for t in completing_tiles
        idx = findfirst(t2 -> t2.name == t.name, game_state.my_hand)
        if idx !== nothing
            deleteat!(game_state.my_hand, idx)
        end
    end
    
    push!(game_state.exposed_sets, completing_tiles)
end

# ============================================================================
# BAYESIAN OPPONENT INFERENCE
# ============================================================================

"""
Calculate likelihood that opponent pursuing given hand would discard a tile
P(discard tile | pursuing hand)
"""
function likelihood_discard_given_hand(discard_tile::Tile, 
                                      opponent_hand::Vector{Tile},
                                      pursuing_hand::MahjongHand,
                                      exposed_sets::Vector{Vector{Tile}})
    
    # What does opponent need for this hand?
    needed = tiles_needed_for_hand(pursuing_hand, opponent_hand, exposed_sets)
    needed_names = Set(t.name for t in needed)
    
    # What's required for the hand pattern?
    required_names = Set(t.name for t in pursuing_hand.required_tiles)
    
    # Calculate how many of each tile they need
    required_counts = Dict{String, Int}()
    for tile in pursuing_hand.required_tiles
        required_counts[tile.name] = get(required_counts, tile.name, 0) + 1
    end
    
    have_counts = Dict{String, Int}()
    for tile in opponent_hand
        have_counts[tile.name] = get(have_counts, tile.name, 0) + 1
    end
    for set in exposed_sets
        for tile in set
            have_counts[tile.name] = get(have_counts, tile.name, 0) + 1
        end
    end
    
    # Categorize the discarded tile
    if discard_tile.name in needed_names
        # They discarded something they STILL NEED - very unlikely!
        return 0.05
    elseif discard_tile.name in required_names
        # It's part of the pattern
        required = get(required_counts, discard_tile.name, 0)
        have = get(have_counts, discard_tile.name, 0)
        
        if have > required
            # They have excess - likely to discard
            return 0.7
        else
            # They have exactly what they need - unlikely to discard
            return 0.1
        end
    else
        # Not part of pattern at all - very likely to discard
        return 0.9
    end
end

"""
Gen model for opponent's hand pursuit given their discards
This is a generative model: given a hand, generate likely discards
"""
@gen function opponent_inference_model(opponent_hand::Vector{Tile},
                                      viable_hands::Vector{MahjongHand},
                                      observed_discards::Vector{Tile},
                                      exposed_sets::Vector{Vector{Tile}})
    
    n_hands = length(viable_hands)
    if n_hands == 0
        return nothing
    end
    
    # Prior: uniform over viable hands
    # (Could be informed by point values: higher points = more likely)
    hand_idx ~ categorical(ones(n_hands) / n_hands)
    pursuing_hand = viable_hands[hand_idx]
    
    # Likelihood: for each observed discard, how likely is it given this hand?
    for (i, discard) in enumerate(observed_discards)
        prob = likelihood_discard_given_hand(discard, opponent_hand, 
                                            pursuing_hand, exposed_sets)
        # Use bernoulli with probability as a proxy for likelihood
        # If prob is high (0.9), we expect to see this discard
        {(:discard, i)} ~ bernoulli(prob)
    end
    
    return pursuing_hand
end

"""
For opponent: track what pattern they're pursuing for player's diversity logic
This is a simplified version - just returns their best hand pattern
"""
function get_opponent_likely_pattern(opponent_hand::Vector{Tile},
                                    all_hands::Vector{MahjongHand},
                                    seen_tiles::Vector{Tile},
                                    exposed_sets::Vector{Vector{Tile}})
    
    viable_hands = get_viable_hands(all_hands, opponent_hand, seen_tiles, exposed_sets)
    
    if isempty(viable_hands)
        return nothing
    end
    
    # Find best hand (most progress)
    best_hand = nothing
    best_progress = -Inf
    
    for hand in viable_hands
        total_needed = length(hand.required_tiles)
        still_needed = length(tiles_needed_for_hand(hand, opponent_hand, exposed_sets))
        tiles_we_have = total_needed - still_needed
        progress = tiles_we_have / total_needed
        score = progress + (hand.point_value / 1000.0)
        
        if score > best_progress
            best_progress = progress
            best_hand = hand
        end
    end
    
    return best_hand !== nothing ? best_hand.pattern_name : nothing
end


"""
Perform inference to get posterior distribution over opponent hands
Returns: Dict mapping hand_id => probability
"""
function infer_opponent_hands(opponent_hand::Vector{Tile},
                             all_hands::Vector{MahjongHand},
                             seen_tiles::Vector{Tile},
                             observed_discards::Vector{Tile},
                             exposed_sets::Vector{Vector{Tile}},
                             n_particles::Int=100)
    
    # Get viable hands for opponent
    viable_hands = get_viable_hands(all_hands, opponent_hand, seen_tiles, exposed_sets)
    
    if isempty(viable_hands) || isempty(observed_discards)
        # No information - return uniform
        return Dict{Int, Float64}()
    end
    
    # Create observations choicemap
    # We observe that opponent DID discard these tiles (all true)
    observations = Gen.choicemap()
    for (i, discard) in enumerate(observed_discards)
        observations[(:discard, i)] = true
    end
    
    # Importance sampling
    traces = []
    weights = Float64[]
    
    for _ in 1:n_particles
        try
            # Generate trace with observations
            (trace, weight) = Gen.generate(
                opponent_inference_model,
                (opponent_hand, viable_hands, observed_discards, exposed_sets),
                observations
            )
            push!(traces, trace)
            push!(weights, weight)
        catch e
            # Skip if generation fails
            continue
        end
    end
    
    if isempty(traces)
        return Dict{Int, Float64}()
    end
    
    # Normalize weights to get probabilities
    log_total_weight = logsumexp(weights)
    normalized_weights = exp.(weights .- log_total_weight)
    
    # Count how many particles support each hand
    hand_probs = Dict{Int, Float64}()
    for (trace, weight) in zip(traces, normalized_weights)
        hand = Gen.get_retval(trace)
        if hand !== nothing
            hand_probs[hand.id] = get(hand_probs, hand.id, 0.0) + weight
        end
    end
    
    return hand_probs
end

"""
Helper: logsumexp for numerical stability
"""
function logsumexp(log_weights::Vector{Float64})
    if isempty(log_weights)
        return -Inf
    end
    max_weight = maximum(log_weights)
    return max_weight + log(sum(exp.(log_weights .- max_weight)))
end

"""
Update opponent tracking with new discard observation
Call this each time opponent discards
"""
function update_opponent_inference!(game_state::GameState, 
                                   opponent_idx::Int,
                                   discarded_tile::Tile)
    
    # Track opponent's discards (we'll need to add this to GameState)
    # For now, just re-infer from all seen discards
    
    opponent_hand = game_state.opponents[opponent_idx]
    opponent_exposed = game_state.opponent_exposed[opponent_idx]
    
    # Get all tiles opponent has discarded
    # (This is approximate - we'd need to track which discards are theirs)
    # For simplicity, assume we can identify opponent discards
    
    # Perform inference
    seen_tiles = vcat(game_state.my_hand, game_state.discards,
                     reduce(vcat, game_state.opponents, init=Tile[]))
    
    # Get opponent's recent discards (last 5-10)
    # This is a placeholder - need to track discards per opponent
    observed_discards = Tile[]  # Would need to extract from game_state
    
    posterior = infer_opponent_hands(
        opponent_hand,
        game_state.all_hands,
        seen_tiles,
        observed_discards,
        opponent_exposed
    )
    
    return posterior
end

"""
Enhanced make_decision with pattern diversity awareness
Avoids committing to hands the opponent is likely pursuing
"""
function make_decision_diverse(game_state::GameState,
                              tile_just_drawn::Tile,
                              opponent_hands::Vector{Dict{Int,Int}},
                              verbose::Bool=false)
    
    if isempty(game_state.viable_hands)
        if !isempty(game_state.my_hand)
            return (:flexible, game_state.my_hand[1])
        else
            return (:flexible, nothing)
        end
    end
    
    # Get opponent's likely hands (if we have posterior)
    opponent_likely_patterns = Set{String}()
    if !isempty(opponent_hands) && !isempty(opponent_hands[1])
        # Get top 3 hands opponent might be pursuing
        sorted_opp = sort(collect(opponent_hands[1]), by=x->x[2], rev=true)
        for (hand_id, count) in sorted_opp[1:min(3, end)]
            hand_idx = findfirst(h -> h.id == hand_id, game_state.all_hands)
            if hand_idx !== nothing
                push!(opponent_likely_patterns, game_state.all_hands[hand_idx].pattern_name)
            end
        end
    end
    
    # Find the hand we're closest to completing WITH diversity penalty
    best_hand = nothing
    best_score = -Inf
    
    for hand in game_state.viable_hands
        # Count how many tiles we already have for this hand
        total_needed = length(hand.required_tiles)
        still_needed = length(tiles_needed_for_hand(hand, game_state.my_hand, game_state.exposed_sets))
        tiles_we_have = total_needed - still_needed
        
        # Progress = fraction of hand completed
        progress = tiles_we_have / total_needed
        
        # Base score: progress + point value tie-breaker
        score = progress + (hand.point_value / 1000.0)
        
        # DIVERSITY PENALTY: If opponent is pursuing this pattern, penalize it
        if hand.pattern_name in opponent_likely_patterns
            diversity_penalty = 0.15  # 15% penalty
            score -= diversity_penalty
            
            if verbose
                println("  ⚠️  Pattern conflict: $(hand.pattern_name)")
                println("     Applying -$(diversity_penalty) penalty")
            end
        end
        
        if score > best_score
            best_score = score
            best_hand = hand
        end
    end
    
    if best_hand === nothing
        if !isempty(game_state.my_hand)
            return (:flexible, game_state.my_hand[1])
        else
            return (:flexible, nothing)
        end
    end
    
    # Check if we should commit (have at least half the tiles)
    total_needed = length(best_hand.required_tiles)
    still_needed = length(tiles_needed_for_hand(best_hand, game_state.my_hand, game_state.exposed_sets))
    tiles_we_have = total_needed - still_needed
    progress = tiles_we_have / total_needed
    
    # Commit if we have ≥50% of the tiles
    if progress >= 0.5
        game_state.committed_hand_id = best_hand.id
        return (:commit, best_hand.id, find_best_discard(game_state, best_hand.id, verbose))
    else
        # Stay flexible - keep options open
        return (:flexible, find_flexible_discard_simple(game_state))
    end
end

"""
Opponent AI: Greedy with randomness and hand-switching
Returns: (tile_to_discard, debug_info)
"""
function opponent_make_decision_diverse(opponent_hand::Vector{Tile},
                                       all_hands::Vector{MahjongHand},
                                       seen_tiles::Vector{Tile},
                                       exposed_sets::Vector{Vector{Tile}},
                                       opponent_hands::Vector{Dict{Int,Int}},
                                       nervousness_threshold::Int=5)  
    
    # Get viable hands for opponent
    viable_hands = get_viable_hands(all_hands, opponent_hand, seen_tiles, exposed_sets)
    
    if isempty(viable_hands)
        return (rand(opponent_hand), nothing)
    end
    
    # Find best hand (most progress) WITH randomness (30%)
    best_hand = nothing
    best_progress = -Inf
    
    for hand in viable_hands
        total_needed = length(hand.required_tiles)
        still_needed = length(tiles_needed_for_hand(hand, opponent_hand, exposed_sets))
        tiles_we_have = total_needed - still_needed
        progress = tiles_we_have / total_needed
        
        # Add randomness (30%) to break ties and create diversity
        score = progress + (hand.point_value / 1000.0)
        
        if score > best_progress
            best_progress = score
            best_hand = hand
        end
    end
    
    if best_hand === nothing
        return (rand(opponent_hand), nothing)
    end
    
    # Use simplified discard logic
    needed = tiles_needed_for_hand(best_hand, opponent_hand, exposed_sets)
    needed_names = Set(t.name for t in needed)
    required_names = Set(t.name for t in best_hand.required_tiles)
    
    # Score tiles
    tile_usefulness = Dict{Int, Float64}()
    for (idx, tile) in enumerate(opponent_hand)
        if tile.name in needed_names
            tile_usefulness[idx] = 2.0  # Still need
        elseif tile.name in required_names
            tile_usefulness[idx] = 1.0  # Have enough
        else
            tile_usefulness[idx] = 0.0  # Not needed
        end
    end
    
    # Prepare debug info
    total_needed = length(best_hand.required_tiles)
    still_needed_count = length(needed)
    tiles_we_have = total_needed - still_needed_count
    progress_pct = round(tiles_we_have / total_needed * 100, digits=1)
    
    debug_info = Dict(
        :hand_name => best_hand.pattern_name,
        :progress => progress_pct,
        :needs => unique([t.name for t in needed])
    )
    
    if !isempty(tile_usefulness)
        worst_idx = argmin(tile_usefulness)
        return (opponent_hand[worst_idx], debug_info)
    end
    
    return (rand(opponent_hand), debug_info)
end

"""
Enhanced opponent_make_decision that can use inference
"""
function opponent_make_decision_bayesian(opponent_hand::Vector{Tile},
                                        all_hands::Vector{MahjongHand},
                                        seen_tiles::Vector{Tile},
                                        exposed_sets::Vector{Vector{Tile}},
                                        observed_discards::Vector{Tile})
    
    # Get viable hands
    viable_hands = get_viable_hands(all_hands, opponent_hand, seen_tiles, exposed_sets)
    
    if isempty(viable_hands)
        return (rand(opponent_hand), nothing)
    end
    
    # If we have discard history, use Bayesian inference
    if !isempty(observed_discards)
        posterior = infer_opponent_hands(
            opponent_hand,
            all_hands,
            seen_tiles,
            observed_discards,
            exposed_sets
        )
        
        # Choose hand with highest posterior probability
        if !isempty(posterior)
            best_hand_id = argmax(posterior)
            best_hand = findfirst(h -> h.id == best_hand_id, viable_hands)
            
            if best_hand !== nothing
                committed_hand = viable_hands[best_hand]
                
                # Use same discard logic as before
                needed = tiles_needed_for_hand(committed_hand, opponent_hand, exposed_sets)
                needed_names = Set(t.name for t in needed)
                required_names = Set(t.name for t in committed_hand.required_tiles)
                
                # Score tiles
                tile_usefulness = Dict{Int, Float64}()
                for (idx, tile) in enumerate(opponent_hand)
                    if tile.name in needed_names
                        tile_usefulness[idx] = 2.0
                    elseif tile.name in required_names
                        tile_usefulness[idx] = 1.0
                    else
                        tile_usefulness[idx] = 0.0
                    end
                end
                
                debug_info = Dict(
                    :hand_name => committed_hand.pattern_name,
                    :progress => 0.0,  # Calculate if needed
                    :needs => unique([t.name for t in needed]),
                    :inference => "Bayesian"
                )
                
                if !isempty(tile_usefulness)
                    worst_idx = argmin(tile_usefulness)
                    return (opponent_hand[worst_idx], debug_info)
                end
            end
        end
    end
    
    # Fallback to greedy method
    best_hand = nothing
    best_progress = -Inf
    
    for hand in viable_hands
        total_needed = length(hand.required_tiles)
        still_needed = length(tiles_needed_for_hand(hand, opponent_hand, exposed_sets))
        tiles_we_have = total_needed - still_needed
        progress = tiles_we_have / total_needed
        score = progress + (hand.point_value / 1000.0)
        
        if score > best_progress
            best_progress = progress
            best_hand = hand
        end
    end
    
    if best_hand === nothing
        return (rand(opponent_hand), nothing)
    end
    
    needed = tiles_needed_for_hand(best_hand, opponent_hand, exposed_sets)
    needed_names = Set(t.name for t in needed)
    required_names = Set(t.name for t in best_hand.required_tiles)
    
    tile_usefulness = Dict{Int, Float64}()
    for (idx, tile) in enumerate(opponent_hand)
        if tile.name in needed_names
            tile_usefulness[idx] = 2.0
        elseif tile.name in required_names
            tile_usefulness[idx] = 1.0
        else
            tile_usefulness[idx] = 0.0
        end
    end
    
    total_needed = length(best_hand.required_tiles)
    still_needed_count = length(needed)
    tiles_we_have = total_needed - still_needed_count
    progress_pct = round(tiles_we_have / total_needed * 100, digits=1)
    
    debug_info = Dict(
        :hand_name => best_hand.pattern_name,
        :progress => progress_pct,
        :needs => unique([t.name for t in needed]),
        :inference => "Greedy"
    )
    
    if !isempty(tile_usefulness)
        worst_idx = argmin(tile_usefulness)
        return (opponent_hand[worst_idx], debug_info)
    end
    
    return (rand(opponent_hand), debug_info)
end

# ============================================================================
# GEN MODELS (kept for potential future use)
# ============================================================================

"""
Generative model for opponent's hand given observations
"""
@gen function opponent_hand_model(observed_pauses::Vector{Tile},
                                 observed_picks::Vector{Tile},
                                 observed_discards::Vector{Tile},
                                 available_hands::Vector{MahjongHand})
    
    # Prior: uniform over all hands
    n_hands = length(available_hands)
    if n_hands == 0
        return nothing
    end
    
    hand_idx ~ categorical(ones(n_hands) / n_hands)
    hand = available_hands[hand_idx]
    
    # Generate tiles they likely need based on hand
    # Assume they have some tiles already
    assumed_opponent_tiles = observed_picks[1:min(5, length(observed_picks))]
    needed_tiles = tiles_needed_for_hand(hand, assumed_opponent_tiles)
    needed_names = Set(tile.name for tile in needed_tiles)
    
    # Likelihood: pauses indicate needed tiles
    for (i, pause_tile) in enumerate(observed_pauses)
        # Higher probability if pause_tile is in needed_tiles
        prob_pause = pause_tile.name in needed_names ? 0.8 : 0.1
        {(:pause, i)} ~ bernoulli(prob_pause)
    end
    
    # Likelihood: picks indicate hand pursuit
    for (i, pick_tile) in enumerate(observed_picks)
        prob_pick = pick_tile.name in needed_names ? 0.7 : 0.2
        {(:pick, i)} ~ bernoulli(prob_pick)
    end
    
    return hand
end

"""
Generative model for tile draws from wall
"""
@gen function tile_draw_model(wall_tiles::Vector{Tile})
    n_tiles = length(wall_tiles)
    if n_tiles == 0
        return nothing
    end
    idx ~ categorical(ones(n_tiles) / n_tiles)
    return wall_tiles[idx]
end



"""
Monte Carlo simulation of hand completion
"""
@gen function simulate_hand_completion(hand::MahjongHand,
                                      current_hand::Vector{Tile},
                                      wall_tiles::Vector{Tile},
                                      n_draws::Int)
    
    my_tiles = copy(current_hand)
    tiles_to_complete = length(tiles_needed_for_hand(hand, my_tiles))
    
    for draw in 1:n_draws
        if tiles_to_complete == 0
            return (true, draw)
        end
        
        if isempty(wall_tiles)
            return (false, draw)
        end
        
        # Draw a tile
        tile ~ tile_draw_model(wall_tiles)
        if tile !== nothing
            push!(my_tiles, tile)
        end
        
        # Check if we're closer to completion
        tiles_to_complete = length(tiles_needed_for_hand(hand, my_tiles))
    end
    
    return (tiles_to_complete == 0, n_draws)
end

# ============================================================================
# INFERENCE AND DECISION MAKING
# ============================================================================

"""
Infer opponent's likely hand using particle filtering
"""
function infer_opponent_hand(opponent_obs::Dict,
                            available_hands::Vector{MahjongHand},
                            n_particles::Int=100)
    
    if isempty(available_hands)
        return Dict{Int, Int}()
    end
    
    # Create observations for conditioning
    observations = Gen.choicemap()
    for (i, pause) in enumerate(get(opponent_obs, :pauses, Tile[]))
        observations[(:pause, i)] = true
    end
    for (i, pick) in enumerate(get(opponent_obs, :picks, Tile[]))
        observations[(:pick, i)] = true
    end
    
    # Particle filter
    traces = []
    for _ in 1:n_particles
        try
            trace, _ = Gen.generate(opponent_hand_model,
                                   (get(opponent_obs, :pauses, Tile[]),
                                    get(opponent_obs, :picks, Tile[]),
                                    get(opponent_obs, :discards, Tile[]),
                                    available_hands))
            push!(traces, trace)
        catch e
            # Skip if generation fails
            continue
        end
    end
    
    # Get hand distribution from particles
    hand_counts = Dict{Int, Int}()
    for trace in traces
        hand = Gen.get_retval(trace)
        if hand !== nothing
            hand_counts[hand.id] = get(hand_counts, hand.id, 0) + 1
        end
    end
    
    return hand_counts
end

function generate_remaining_wall(seen_tiles::Vector{Tile})
    # Generate all tiles in American Mahjong set
    all_tiles = Tile[]
    
    suits = ["Bamboo", "Character", "Dot"]
    
    # Add numbered tiles (1-9 in each suit, 4 of each)
    for suit in suits
        for num in 1:9
            for _ in 1:4
                push!(all_tiles, Tile("$num $suit"))
            end
        end
    end
    
    # Add dragons (4 of each)
    for dragon in ["Red Dragon", "Green Dragon", "White Dragon"]
        for _ in 1:4
            push!(all_tiles, Tile(dragon))
        end
    end
    
    # Add winds (4 of each)
    for wind in ["North Wind", "East Wind", "West Wind", "South Wind"]
        for _ in 1:4
            push!(all_tiles, Tile(wind))
        end
    end
    
    # Add flowers/jokers (8 total)
    for _ in 1:8
        push!(all_tiles, Tile("Flower"))
    end
    
    # Remove seen tiles
    seen_counts = Dict{String, Int}()
    for tile in seen_tiles
        seen_counts[tile.name] = get(seen_counts, tile.name, 0) + 1
    end
    
    remaining = Tile[]
    for tile in all_tiles
        count_seen = get(seen_counts, tile.name, 0)
        if count_seen > 0
            seen_counts[tile.name] = count_seen - 1
        else
            push!(remaining, tile)
        end
    end
    
    return remaining
end

# ============================================================================
# DECISION LOGIC - SIMPLIFIED
# ============================================================================

"""
Main decision function: commit to a hand once you have half the tiles needed
Now with hand-switching if stuck (nervousness threshold)
"""
function make_decision(game_state::GameState,
                      tile_just_drawn::Tile,
                      opponent_hands::Vector{Dict{Int,Int}},
                      verbose::Bool=false,
                      nervousness_threshold::Int=5)  
    
    if isempty(game_state.viable_hands)
        if !isempty(game_state.my_hand)
            return (:flexible, game_state.my_hand[1])
        else
            return (:flexible, nothing)
        end
    end
    
    # Check if we should switch hands (if committed and stuck)
    should_switch = false
    if game_state.committed_hand_id !== nothing
        # Calculate current progress
        hand_idx = findfirst(h -> h.id == game_state.committed_hand_id, game_state.viable_hands)
        if hand_idx !== nothing
            committed_hand = game_state.viable_hands[hand_idx]
            total_needed = length(committed_hand.required_tiles)
            still_needed = length(tiles_needed_for_hand(committed_hand, game_state.my_hand, game_state.exposed_sets))
            current_progress = (total_needed - still_needed) / total_needed
            
            # Check if we made progress
            if game_state.last_progress_value === nothing
                game_state.last_progress_value = current_progress
                game_state.turns_since_progress = 0
            elseif current_progress > game_state.last_progress_value
                # Made progress! Reset counter
                game_state.last_progress_value = current_progress
                game_state.turns_since_progress = 0
            else
                # No progress this turn
                game_state.turns_since_progress += 1
            end
            
            # Check nervousness threshold
            if game_state.turns_since_progress >= nervousness_threshold
                should_switch = true
                if verbose
                    println("  😰 SWITCHING HANDS - No progress for $(game_state.turns_since_progress) turns!")
                    println("     Stuck at $(round(current_progress*100, digits=1))% on $(committed_hand.pattern_name)")
                end
            end
        end
    end
    
    # Find the hand we're closest to completing
    best_hand = nothing
    best_progress = -Inf
    
    for hand in game_state.viable_hands
        # Skip currently committed hand if we're switching
        if should_switch && game_state.committed_hand_id !== nothing && hand.id == game_state.committed_hand_id
            continue
        end
        
        # Count how many tiles we already have for this hand
        total_needed = length(hand.required_tiles)
        still_needed = length(tiles_needed_for_hand(hand, game_state.my_hand, game_state.exposed_sets))
        tiles_we_have = total_needed - still_needed
        
        # Progress = fraction of hand completed
        progress = tiles_we_have / total_needed
        
        # Tie-breaker: prefer higher point value
        score = progress + (hand.point_value / 1000.0)
        
        if score > best_progress
            best_progress = score
            best_hand = hand
        end
    end
    
    if best_hand === nothing
        if !isempty(game_state.my_hand)
            return (:flexible, game_state.my_hand[1])
        else
            return (:flexible, nothing)
        end
    end
    
    # If we switched, reset committed hand and tracking
    if should_switch
        if verbose && best_hand !== nothing
            println("     → Switching to: $(best_hand.pattern_name)")
        end
        game_state.committed_hand_id = nothing
        game_state.turns_since_progress = 0
        game_state.last_progress_value = nothing
    end
    
    # Check if we should commit (have at least half the tiles)
    total_needed = length(best_hand.required_tiles)
    still_needed = length(tiles_needed_for_hand(best_hand, game_state.my_hand, game_state.exposed_sets))
    tiles_we_have = total_needed - still_needed
    progress = tiles_we_have / total_needed
    
    # Commit if we have ≥50% of the tiles
    if progress >= 0.5
        # Initialize tracking ONLY if we just switched (not if continuing same hand)
        if should_switch
            game_state.last_progress_value = progress
            game_state.turns_since_progress = 0
        end
        
        game_state.committed_hand_id = best_hand.id
        return (:commit, best_hand.id, find_best_discard(game_state, best_hand.id, verbose))
    else
        # Stay flexible - keep options open
        return (:flexible, find_flexible_discard_simple(game_state))
    end
end

"""
Opponent AI: Makes decisions for computer-controlled opponents
Returns: (tile_to_discard, debug_info)
"""
function opponent_make_decision(opponent_hand::Vector{Tile},
                               all_hands::Vector{MahjongHand},
                               seen_tiles::Vector{Tile},
                               exposed_sets::Vector{Vector{Tile}})
    
    # Get viable hands for opponent
    viable_hands = get_viable_hands(all_hands, opponent_hand, seen_tiles, exposed_sets)
    
    if isempty(viable_hands)
        # No viable hands - discard random tile
        return (rand(opponent_hand), nothing)
    end
    
    # Find best hand (most progress)
    best_hand = nothing
    best_progress = -Inf
    
    for hand in viable_hands
        total_needed = length(hand.required_tiles)
        still_needed = length(tiles_needed_for_hand(hand, opponent_hand, exposed_sets))
        tiles_we_have = total_needed - still_needed
        progress = tiles_we_have / total_needed
        score = progress + (hand.point_value / 1000.0)
        
        if score > best_progress
            best_progress = progress
            best_hand = hand
        end
    end
    
    if best_hand === nothing
        return (rand(opponent_hand), nothing)
    end
    
    # Use simplified discard logic
    needed = tiles_needed_for_hand(best_hand, opponent_hand, exposed_sets)
    needed_names = Set(t.name for t in needed)
    required_names = Set(t.name for t in best_hand.required_tiles)
    
    # Score tiles
    tile_usefulness = Dict{Int, Float64}()
    for (idx, tile) in enumerate(opponent_hand)
        if tile.name in needed_names
            tile_usefulness[idx] = 2.0  # Still need
        elseif tile.name in required_names
            tile_usefulness[idx] = 1.0  # Have enough
        else
            tile_usefulness[idx] = 0.0  # Not needed
        end
    end
    
    # Prepare debug info
    total_needed = length(best_hand.required_tiles)
    still_needed_count = length(needed)
    tiles_we_have = total_needed - still_needed_count
    progress_pct = round(tiles_we_have / total_needed * 100, digits=1)
    
    debug_info = Dict(
        :hand_name => best_hand.pattern_name,
        :progress => progress_pct,
        :needs => unique([t.name for t in needed])
    )
    
    if !isempty(tile_usefulness)
        worst_idx = argmin(tile_usefulness)
        return (opponent_hand[worst_idx], debug_info)
    end
    
    return (rand(opponent_hand), debug_info)
end


"""
Simplified flexible discard - just discard tiles not needed by most viable hands
"""
function find_flexible_discard_simple(game_state::GameState)
    if isempty(game_state.my_hand)
        return nothing
    end
    
    # Count how many viable hands each tile is needed for
    tile_value = Dict{Int, Int}()
    
    for (idx, tile) in enumerate(game_state.my_hand)
        value_count = 0
        
        for hand in game_state.viable_hands
            needed = tiles_needed_for_hand(hand, game_state.my_hand, game_state.exposed_sets)
            # If this tile IS needed for this hand, it's valuable
            if any(t -> t.name == tile.name, needed)
                value_count += 1
            end
        end
        
        tile_value[idx] = value_count
    end
    
    # Discard tile needed by fewest hands (least valuable)
    if !isempty(tile_value)
        worst_idx = argmin(tile_value)
        return game_state.my_hand[worst_idx]
    end
    
    return game_state.my_hand[1]
end

function find_best_discard(game_state::GameState, hand_id::Int, verbose::Bool=false)
    # Return tile least useful for committed hand, while avoiding tiles opponent needs
    
    if isempty(game_state.my_hand)
        return nothing
    end
    
    # Find the hand we're committing to
    hand_idx = findfirst(h -> h.id == hand_id, game_state.viable_hands)
    if hand_idx === nothing
        return game_state.my_hand[1]
    end
    
    committed_hand = game_state.viable_hands[hand_idx]
    
    # Get what we still need
    needed = tiles_needed_for_hand(committed_hand, game_state.my_hand, game_state.exposed_sets)
    needed_names = Set(t.name for t in needed)
    
    # Count how many of each tile the hand requires
    required_counts = Dict{String, Int}()
    for tile in committed_hand.required_tiles
        required_counts[tile.name] = get(required_counts, tile.name, 0) + 1
    end
    
    # Count how many we currently have (in hand + exposed)
    have_counts = Dict{String, Int}()
    for tile in game_state.my_hand
        have_counts[tile.name] = get(have_counts, tile.name, 0) + 1
    end
    for set in game_state.exposed_sets
        for tile in set
            have_counts[tile.name] = get(have_counts, tile.name, 0) + 1
        end
    end
    
    # Score tiles by usefulness TO US
    tile_usefulness = Dict{Int, Float64}()
    
    if verbose
        println("\n  [DEBUG] Scoring tiles for discard:")
    end
    
    for (idx, tile) in enumerate(game_state.my_hand)
        required_count = get(required_counts, tile.name, 0)
        have_count = get(have_counts, tile.name, 0)
        
        if tile.name in needed_names
            # We still need more of this tile - VERY useful, DON'T discard
            tile_usefulness[idx] = 3.0
        elseif required_count > 0 && have_count <= required_count
            # Part of the hand and we have exactly the right amount - useful, DON'T discard
            tile_usefulness[idx] = 2.0
        elseif required_count > 0 && have_count > required_count
            # Part of the hand but we have EXTRA - okay to discard the excess
            tile_usefulness[idx] = 1.0
        else
            # Not part of the hand at all - DEFINITELY discard
            tile_usefulness[idx] = 0.0
        end
        
        if verbose
            println("    $(tile.name): base_score=$(tile_usefulness[idx])")
        end
    end
    
    # ========================================================================
    # BAYESIAN DEFENSIVE ADJUSTMENT
    # ========================================================================
    # Penalize tiles that opponent likely needs (avoid helping them win!)
    
    if !isempty(game_state.opponents) && !isempty(game_state.opponent_discards[1])
        if verbose
            println("\n  [DEBUG] Running Bayesian inference...")
            println("    Opponent has discarded $(length(game_state.opponent_discards[1])) tiles")
        end
        
        # Run Bayesian inference on opponent
        all_seen = vcat(game_state.discards, 
                       reduce(vcat, game_state.opponents, init=Tile[]))
        
        opponent_posterior = infer_opponent_hands(
            game_state.opponents[1],
            game_state.all_hands,
            all_seen,
            game_state.opponent_discards[1],
            game_state.opponent_exposed[1],
            50  # Use fewer particles for speed during game
        )
        
        if verbose
            if isempty(opponent_posterior)
                println("    ⚠️  Inference returned empty posterior!")
            else
                println("    ✓ Inference successful - $(length(opponent_posterior)) candidate hands")
            end
        end
        
        if !isempty(opponent_posterior)
            if verbose
                println("\n  [DEBUG] Computing danger scores:")
            end
            
            # For each tile we might discard, calculate danger score
            for (idx, tile) in enumerate(game_state.my_hand)
                danger_score = 0.0
                
                # Check each hand opponent might be pursuing
                for (opp_hand_id, prob) in opponent_posterior
                    hand_idx = findfirst(h -> h.id == opp_hand_id, game_state.all_hands)
                    if hand_idx !== nothing
                        opp_hand = game_state.all_hands[hand_idx]
                        
                        # What does opponent need for this hand?
                        opp_needed = tiles_needed_for_hand(
                            opp_hand, 
                            game_state.opponents[1],
                            game_state.opponent_exposed[1]
                        )
                        
                        # If opponent needs this tile, it's dangerous to discard
                        if any(t -> t.name == tile.name, opp_needed)
                            # Weight danger by probability opponent is pursuing this hand
                            danger_score += prob
                            
                            if verbose && prob > 0.1
                                println("      $(tile.name) needed by $(opp_hand.pattern_name) (p=$(round(prob*100, digits=1))%)")
                            end
                        end
                    end
                end
                
                # Apply penalty proportional to danger
                old_score = tile_usefulness[idx]
                penalty_weight = 1.5
                tile_usefulness[idx] += danger_score * penalty_weight
                
                if verbose && danger_score > 0.01
                    println("    $(tile.name): danger=$(round(danger_score, digits=3)), penalty=$(round(danger_score * penalty_weight, digits=3)), old=$(round(old_score, digits=2)) → new=$(round(tile_usefulness[idx], digits=2))")
                end
            end
        end
    else
        if verbose
            if isempty(game_state.opponents)
                println("\n  [DEBUG] No opponents to analyze")
            elseif isempty(game_state.opponent_discards[1])
                println("\n  [DEBUG] Opponent hasn't discarded yet - no inference data")
            end
        end
    end
    
    # Return least useful tile (now accounting for both our needs AND opponent danger)
    if !isempty(tile_usefulness)
        if verbose
            println("\n  [DEBUG] Final scores (lower = more likely to discard):")
            sorted_tiles = sort(collect(tile_usefulness), by=x->x[2])
            for (idx, score) in sorted_tiles[1:min(5, end)]
                println("    $(game_state.my_hand[idx].name): $(round(score, digits=2))")
            end
        end
        
        worst_idx = argmin(tile_usefulness)
        
        if verbose
            println("  [DEBUG] ✓ Chose to discard: $(game_state.my_hand[worst_idx].name)")
        end
        
        return game_state.my_hand[worst_idx]
    end
    
    return game_state.my_hand[1]
end

# ============================================================================

# Keep old functions for backward compatibility
function find_flexible_discard(game_state::GameState, hand_scores::Dict{Int,Float64})
    return find_flexible_discard_simple(game_state)
end

function evaluate_hands(game_state::GameState, n_simulations::Int=50)
    # Dummy function for backward compatibility - not used in simplified version
    return Dict{Int, Float64}()
end

# ============================================================================
# EXAMPLE USAGE
# ============================================================================

function run_example()
    println("Mahjong Probabilistic Model - Simplified Version")
    println("=" ^ 50)
    println("Rule: Commit to a hand once you have ≥50% of tiles")
    
    # Load all hands from the card
    println("\nLoading all mahjong hands from card...")
    # Note: In actual use, include the mahjong_hands.jl file
    # all_hands = generate_mahjong_hands()
    # For now, create a simple test hand
    test_hand = MahjongHand(
        1,
        "FF 333 666 999 DDD - Bamboo",
        vcat(
            [Tile("Flower") for _ in 1:2],
            [Tile("3 Bamboo") for _ in 1:3],
            [Tile("6 Bamboo") for _ in 1:3],
            [Tile("9 Bamboo") for _ in 1:3],
            [Tile("Red Dragon") for _ in 1:3]
        ),
        30
    )
    
    all_hands = [test_hand]
    println("Loaded $(length(all_hands)) hands")
    
    # Create a simple game state
    my_hand = [
        Tile("3 Bamboo"),
        Tile("6 Bamboo"),
        Tile("Flower"),
        Tile("Red Dragon"),
        Tile("Red Dragon"),
        Tile("9 Bamboo")
    ]
    
    println("\nMy starting hand:")
    for tile in my_hand
        println("  - $(tile.name)")
    end
    
    # Check which hands are viable
    seen_tiles = copy(my_hand)
    viable = get_viable_hands(all_hands, my_hand, seen_tiles)
    
    println("\nViable hands: $(length(viable))")
    for hand in viable
        println("  - $(hand.pattern_name) ($(hand.point_value) points)")
        needed = tiles_needed_for_hand(hand, my_hand)
        total = length(hand.required_tiles)
        have = total - length(needed)
        progress = have / total * 100
        println("    Progress: $have/$total tiles ($(round(progress, digits=1))%)")
        println("    Still need: $(unique([t.name for t in needed]))")
    end
    
    # Create game state
    game_state = GameState(
        my_hand,
        Tile[],
        [opponent_hand],
        [Vector{Tile}[]],
        [Tile[]],          
        length(all_tiles) - 26,
        1,
        viable_hands,
        all_hands,
        nothing,
        Vector{Tile}[]
    )
    
    println("\n" * "=" ^ 50)
    println("Making decision...")
    
    # Simulate opponent observations
    opponent_hands = [Dict{Int,Int}(), Dict{Int,Int}(), Dict{Int,Int}()]
    
    decision = make_decision(game_state, Tile("7 Bamboo"), opponent_hands)
    
    println("\nDecision: $(decision[1])")
    if decision[1] == :commit && length(decision) >= 2
        hand = findfirst(h -> h.id == decision[2], viable)
        if hand !== nothing
            println("  ✓ Committing to: $(viable[hand].pattern_name)")
            total = length(viable[hand].required_tiles)
            needed = tiles_needed_for_hand(viable[hand], my_hand)
            have = total - length(needed)
            println("  Progress: $have/$total tiles ($(round(have/total*100, digits=1))%)")
        end
        if length(decision) >= 3 && decision[3] !== nothing
            println("  Discard: $(decision[3].name)")
        end
    elseif length(decision) >= 2 && decision[2] !== nothing
        println("  ↔ Staying flexible")
        println("  Discard: $(decision[2].name)")
    end
    
    println("\n" * "=" ^ 50)
    println("Model initialized and tested successfully!")
end

# Run example if executing directly
if abspath(PROGRAM_FILE) == @__FILE__
    run_example()
end