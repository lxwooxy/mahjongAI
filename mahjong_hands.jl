using Combinatorics

# ============================================================================
# MAHJONG HAND GENERATION (Based on Python rules)
# ============================================================================

include("mahjong_model.jl")


"""
Create a canonical representation of a hand for deduplication
Sorts tiles and normalizes suit order
"""
function canonical_hand_key(hand::MahjongHand)
    # Sort tiles by name to get consistent ordering
    sorted_tiles = sort([t.name for t in hand.required_tiles])
    
    # Normalize suit mentions in pattern name
    # Replace specific suit combinations with placeholder
    normalized_pattern = hand.pattern_name
    for suits in [["Bamboo", "Character", "Dot"], 
                  ["Character", "Dot", "Bamboo"],
                  ["Dot", "Bamboo", "Character"],
                  ["Bamboo", "Dot", "Character"],
                  ["Character", "Bamboo", "Dot"],
                  ["Dot", "Character", "Bamboo"]]
        suit_str = join(suits, "/")
        normalized_pattern = replace(normalized_pattern, suit_str => "ANY_SUITS")
    end
    
    return (sorted_tiles, hand.point_value, normalized_pattern)
end

"""
Generate all possible Mahjong hands based on official card
"""
function generate_mahjong_hands()
    hands = MahjongHand[]
    hand_id = 1
    
    suits = ["Bamboo", "Character", "Dot"]
    dragons = ["Red Dragon", "Green Dragon", "White Dragon"]
    
    # ANY LIKE NUMBERS SECTION
    
    # FFFF 11 111 111 11 (Any 3 Suits, Pairs Must Be Same Suit)
    for num in 1:9
        for (s1, s2, s3) in combinations(suits, 3)
            # Three variations based on which suit has both pairs
            for pair_suit in [s1, s2, s3]
                other_suits = [s for s in [s1, s2, s3] if s != pair_suit]
                tiles = vcat(
                    [Tile("Flower") for _ in 1:4],
                    [Tile("$num $pair_suit") for _ in 1:2],
                    [Tile("$num $(other_suits[1])") for _ in 1:3],
                    [Tile("$num $(other_suits[2])") for _ in 1:3],
                    [Tile("$num $pair_suit") for _ in 1:2]
                )
                push!(hands, MahjongHand(hand_id, 
                    "FFFF $num$num $num$num$num $num$num$num $num$num - $s1/$s2/$s3",
                    tiles, 30))
                hand_id += 1
            end
        end
    end
    
    # FF 1111 D 1111 D 11
    for num in 1:9
        for (s1, s2, s3) in combinations(suits, 3)
            for (d1, d2) in combinations(dragons, 2)
                # Six arrangements of 4,4,2 across three suits
                suit_arrangements = [
                    (s1, s2, s3), (s1, s3, s2),
                    (s2, s1, s3), (s2, s3, s1),
                    (s3, s1, s2), (s3, s2, s1)
                ]
                
                for (suit_4a, suit_4b, suit_2) in suit_arrangements
                    tiles = vcat(
                        [Tile("Flower") for _ in 1:2],
                        [Tile("$num $suit_4a") for _ in 1:4],
                        [Tile(d1)],
                        [Tile("$num $suit_4b") for _ in 1:4],
                        [Tile(d2)],
                        [Tile("$num $suit_2") for _ in 1:2]
                    )
                    push!(hands, MahjongHand(hand_id,
                        "FF $num$num$num$num D $num$num$num$num D $num$num - $s1/$s2/$s3",
                        tiles, 25))
                    hand_id += 1
                end
            end
        end
    end
    
    # FF 111 111 111 DDD (Any 3 Suits, Any Dragon)
    for num in 1:9
        for (s1, s2, s3) in combinations(suits, 3)
            for dragon in dragons
                tiles = vcat(
                    [Tile("Flower") for _ in 1:2],
                    [Tile("$num $s1") for _ in 1:3],
                    [Tile("$num $s2") for _ in 1:3],
                    [Tile("$num $s3") for _ in 1:3],
                    [Tile(dragon) for _ in 1:3]
                )
                push!(hands, MahjongHand(hand_id,
                    "FF $num$num$num $num$num$num $num$num$num DDD - $s1/$s2/$s3",
                    tiles, 30))
                hand_id += 1
            end
        end
    end
    
    # WINDS-DRAGONS SECTION
    push!(hands, MahjongHand(hand_id,
        "NNNN EEEE WWW SSSS",
        vcat([Tile("North Wind") for _ in 1:4],
             [Tile("East Wind") for _ in 1:3],
             [Tile("West Wind") for _ in 1:3],
             [Tile("South Wind") for _ in 1:4]),
        25))
    hand_id += 1
    
    push!(hands, MahjongHand(hand_id,
        "NNN EEEE WWWW SSS",
        vcat([Tile("North Wind") for _ in 1:3],
             [Tile("East Wind") for _ in 1:4],
             [Tile("West Wind") for _ in 1:4],
             [Tile("South Wind") for _ in 1:3]),
        25))
    hand_id += 1
    
    # FF 123 DD DDD DDDD (any 3 consecutive in any suit, any 2, 3, and 4 dragons)
    for suit in suits
        for start in 1:7
            dragon_distributions = [
                (2, 3, 4), (2, 4, 3),
                (3, 2, 4), (3, 4, 2),
                (4, 2, 3), (4, 3, 2)
            ]
            
            for (rd_count, gd_count, wd_count) in dragon_distributions
                tiles = vcat(
                    [Tile("Flower") for _ in 1:2],
                    [Tile("$start $suit"), Tile("$(start+1) $suit"), Tile("$(start+2) $suit")],
                    [Tile("Red Dragon") for _ in 1:rd_count],
                    [Tile("Green Dragon") for _ in 1:gd_count],
                    [Tile("White Dragon") for _ in 1:wd_count]
                )
                push!(hands, MahjongHand(hand_id,
                    "FF $start$(start+1)$(start+2) DD DDD DDDD - $suit",
                    tiles, 25))
                hand_id += 1
            end
        end
    end
    
    # FFF NN EE WWW SSSS
    push!(hands, MahjongHand(hand_id,
        "FFF NN EE WWW SSSS",
        vcat([Tile("Flower") for _ in 1:3],
             [Tile("North Wind") for _ in 1:2],
             [Tile("East Wind") for _ in 1:2],
             [Tile("West Wind") for _ in 1:3],
             [Tile("South Wind") for _ in 1:4]),
        25))
    hand_id += 1
    
    # FFFF DDD NEWS DDD (any 2 different dragons)
    for (d1, d2) in combinations(dragons, 2)
        tiles = vcat(
            [Tile("Flower") for _ in 1:4],
            [Tile(d1) for _ in 1:3],
            [Tile("North Wind"), Tile("East Wind"), Tile("West Wind"), Tile("South Wind")],
            [Tile(d2) for _ in 1:3]
        )
        push!(hands, MahjongHand(hand_id,
            "FFFF DDD NEWS DDD",
            tiles, 25))
        hand_id += 1
    end
    
    # Like Odd Numbers in 3 Suits (NNNN 1 11 111 SSSS)
    for odd in [1, 3, 5, 7, 9]
        for (s1, s2, s3) in permutations(suits, 3)
            tiles = vcat(
                [Tile("North Wind") for _ in 1:4],
                [Tile("$odd $s1")],
                [Tile("$odd $s2") for _ in 1:2],
                [Tile("$odd $s3") for _ in 1:3],
                [Tile("South Wind") for _ in 1:4]
            )
            push!(hands, MahjongHand(hand_id,
                "NNNN $odd $odd$odd $odd$odd$odd SSSS",
                tiles, 25))
            hand_id += 1
        end
    end
    
    # Like Even Numbers in 3 Suits (EEEE 2 22 222 WWWW)
    for even in [2, 4, 6, 8]
        for (s1, s2, s3) in permutations(suits, 3)
            tiles = vcat(
                [Tile("East Wind") for _ in 1:4],
                [Tile("$even $s1")],
                [Tile("$even $s2") for _ in 1:2],
                [Tile("$even $s3") for _ in 1:3],
                [Tile("West Wind") for _ in 1:4]
            )
            push!(hands, MahjongHand(hand_id,
                "EEEE $even $even$even $even$even$even WWWW",
                tiles, 25))
            hand_id += 1
        end
    end
    
    # 2025 SECTION - Complete Implementation
    
    # FF 2025 2025 2025 (any 3 suits)
    tiles = vcat(
        [Tile("Flower") for _ in 1:2],
        [Tile("2 Bamboo"), Tile("White Dragon"), Tile("2 Bamboo"), Tile("5 Bamboo")],
        [Tile("2 Character"), Tile("White Dragon"), Tile("2 Character"), Tile("5 Character")],
        [Tile("2 Dot"), Tile("White Dragon"), Tile("2 Dot"), Tile("5 Dot")]
    )
    push!(hands, MahjongHand(hand_id,
        "FF 2025 2025 2025",
        tiles, 75))
    hand_id += 1
    
    # FFFF 2025 222 222 (Any 3 Suits, Like Pungs 2s or 5s in Opp. Suits)
    for (s1, s2, s3) in combinations(suits, 3)
        # With 2s pungs
        tiles = vcat(
            [Tile("Flower") for _ in 1:4],
            [Tile("2 $s1"), Tile("White Dragon"), Tile("2 $s1"), Tile("5 $s1")],
            [Tile("2 $s2") for _ in 1:3],
            [Tile("2 $s3") for _ in 1:3]
        )
        push!(hands, MahjongHand(hand_id,
            "FFFF 2025 222 222 - $s1/$s2/$s3",
            tiles, 25))
        hand_id += 1
        
        # With 5s pungs
        tiles = vcat(
            [Tile("Flower") for _ in 1:4],
            [Tile("2 $s1"), Tile("White Dragon"), Tile("2 $s1"), Tile("5 $s1")],
            [Tile("5 $s2") for _ in 1:3],
            [Tile("5 $s3") for _ in 1:3]
        )
        push!(hands, MahjongHand(hand_id,
            "FFFF 2025 555 555 - $s1/$s2/$s3",
            tiles, 25))
        hand_id += 1
    end
    
    # 222 0000 222 5555 (Any 2 Suits)
    for (s1, s2) in combinations(suits, 2)
        tiles = vcat(
            [Tile("2 $s1") for _ in 1:3],
            [Tile("White Dragon") for _ in 1:4],
            [Tile("2 $s2") for _ in 1:3],
            [Tile("5 $s2") for _ in 1:4]
        )
        push!(hands, MahjongHand(hand_id,
            "222 0000 222 5555 - $s1/$s2",
            tiles, 25))
        hand_id += 1
    end
    
    # 2025 222 555 DDDD
    for (s1, s2) in permutations(suits, 2)
        for dragon in dragons
            tiles = vcat(
                [Tile("2 $s1"), Tile("White Dragon"), Tile("2 $s1"), Tile("5 $s1")],
                [Tile("2 $s2") for _ in 1:3],
                [Tile("5 $s2") for _ in 1:3],
                [Tile(dragon) for _ in 1:4]
            )
            push!(hands, MahjongHand(hand_id,
                "2025 222 555 DDDD - $s1/$s2",
                tiles, 30))
            hand_id += 1
        end
    end
    
    # FF 222 000 222 555 (Any 3 Suits)
    for (s1, s2, s3) in combinations(suits, 3)
        tiles = vcat(
            [Tile("Flower") for _ in 1:2],
            [Tile("2 $s1") for _ in 1:3],
            [Tile("White Dragon") for _ in 1:3],
            [Tile("2 $s2") for _ in 1:3],
            [Tile("5 $s3") for _ in 1:3]
        )
        push!(hands, MahjongHand(hand_id,
            "FF 222 000 222 555 - $s1/$s2/$s3",
            tiles, 30))
        hand_id += 1
    end
    
    # NN EEE WWW SS 2025
    for suit in suits
        tiles = vcat(
            [Tile("North Wind") for _ in 1:2],
            [Tile("East Wind") for _ in 1:3],
            [Tile("West Wind") for _ in 1:3],
            [Tile("South Wind") for _ in 1:2],
            [Tile("2 $suit"), Tile("White Dragon"), Tile("2 $suit"), Tile("5 $suit")]
        )
        push!(hands, MahjongHand(hand_id,
            "NN EEE WWW SS 2025 - $suit",
            tiles, 30))
        hand_id += 1
        
        # NNN EE WW SSS 2025
        tiles = vcat(
            [Tile("North Wind") for _ in 1:3],
            [Tile("East Wind") for _ in 1:2],
            [Tile("West Wind") for _ in 1:2],
            [Tile("South Wind") for _ in 1:3],
            [Tile("2 $suit"), Tile("White Dragon"), Tile("2 $suit"), Tile("5 $suit")]
        )
        push!(hands, MahjongHand(hand_id,
            "NNN EE WW SSS 2025 - $suit",
            tiles, 30))
        hand_id += 1
    end
    
    # 2468 SECTION - Complete Implementation
    
    # 222 4444 666 8888 (any 1 suit)
    for suit in suits
        tiles = vcat(
            [Tile("2 $suit") for _ in 1:3],
            [Tile("4 $suit") for _ in 1:4],
            [Tile("6 $suit") for _ in 1:3],
            [Tile("8 $suit") for _ in 1:4]
        )
        push!(hands, MahjongHand(hand_id,
            "222 4444 666 8888 - $suit",
            tiles, 25))
        hand_id += 1
    end
    
    # 222 4444 666 8888 (any 2 suits)
    for (s1, s2) in combinations(suits, 2)
        tiles = vcat(
            [Tile("2 $s1") for _ in 1:3],
            [Tile("4 $s1") for _ in 1:4],
            [Tile("6 $s2") for _ in 1:3],
            [Tile("8 $s2") for _ in 1:4]
        )
        push!(hands, MahjongHand(hand_id,
            "222 4444 666 8888 - $s1/$s2",
            tiles, 25))
        hand_id += 1
    end
    
    # FF 2222 + 4444 = 6666 and FF 2222 + 6666 = 8888
    for (s1, s2, s3) in combinations(suits, 3)
        tiles = vcat(
            [Tile("Flower") for _ in 1:2],
            [Tile("2 $s1") for _ in 1:4],
            [Tile("4 $s2") for _ in 1:4],
            [Tile("6 $s3") for _ in 1:4]
        )
        push!(hands, MahjongHand(hand_id,
            "FF 2222 + 4444 = 6666 - $s1/$s2/$s3",
            tiles, 25))
        hand_id += 1
        
        tiles = vcat(
            [Tile("Flower") for _ in 1:2],
            [Tile("2 $s1") for _ in 1:4],
            [Tile("6 $s2") for _ in 1:4],
            [Tile("8 $s3") for _ in 1:4]
        )
        push!(hands, MahjongHand(hand_id,
            "FF 2222 + 6666 = 8888 - $s1/$s2/$s3",
            tiles, 25))
        hand_id += 1
    end
    
    # 22 444 66 888 DDDD
    for suit in suits
        tiles = vcat(
            [Tile("2 $suit") for _ in 1:2],
            [Tile("4 $suit") for _ in 1:3],
            [Tile("6 $suit") for _ in 1:2],
            [Tile("8 $suit") for _ in 1:3],
            [Tile("Red Dragon") for _ in 1:4]
        )
        push!(hands, MahjongHand(hand_id,
            "22 444 66 888 DDDD - $suit",
            tiles, 25))
        hand_id += 1
    end
    
    # FFFF 2468 222 222 (Any 3 Suits, Like Pungs Any Even No.)
    for (s1, s2, s3) in combinations(suits, 3)
        for even in [2, 4, 6, 8]
            tiles = vcat(
                [Tile("Flower") for _ in 1:4],
                [Tile("2 $s1"), Tile("4 $s1"), Tile("6 $s1"), Tile("8 $s1")],
                [Tile("$even $s2") for _ in 1:3],
                [Tile("$even $s3") for _ in 1:3]
            )
            push!(hands, MahjongHand(hand_id,
                "FFFF 2468 $even$even$even $even$even$even - $s1/$s2/$s3",
                tiles, 25))
            hand_id += 1
        end
    end
    
    # FFF 22 44 666 8888 (Any 1 Suit)
    for suit in suits
        tiles = vcat(
            [Tile("Flower") for _ in 1:3],
            [Tile("2 $suit") for _ in 1:2],
            [Tile("4 $suit") for _ in 1:2],
            [Tile("6 $suit") for _ in 1:3],
            [Tile("8 $suit") for _ in 1:4]
        )
        push!(hands, MahjongHand(hand_id,
            "FFF 22 44 666 8888 - $suit",
            tiles, 25))
        hand_id += 1
    end
    
    # 222 4444 666 88 88 (Any 3 Suits)
    for (s1, s2, s3) in combinations(suits, 3)
        tiles = vcat(
            [Tile("2 $s1") for _ in 1:3],
            [Tile("4 $s1") for _ in 1:4],
            [Tile("6 $s1") for _ in 1:3],
            [Tile("8 $s2") for _ in 1:2],
            [Tile("8 $s3") for _ in 1:2]
        )
        push!(hands, MahjongHand(hand_id,
            "222 4444 666 88 88 - $s1/$s2/$s3",
            tiles, 25))
        hand_id += 1
    end
    
    # FF 2222 DDDD 2222 (Any 3 Suits, Like Kongs Any Even No.)
    for (s1, s2, s3) in combinations(suits, 3)
        tiles = vcat(
            [Tile("Flower") for _ in 1:2],
            [Tile("2 $s1") for _ in 1:4],
            [Tile("Red Dragon") for _ in 1:4],
            [Tile("2 $s2") for _ in 1:4]
        )
        push!(hands, MahjongHand(hand_id,
            "FF 2222 DDDD 2222 - $s1/$s2/$s3",
            tiles, 25))
        hand_id += 1
    end
    
    # 22 44 66 88 222 222 (Any 3 Suits, Like Pungs Any Even No.)
    for (s1, s2, s3) in combinations(suits, 3)
        for even in [2, 4, 6, 8]
            tiles = vcat(
                [Tile("2 $s1") for _ in 1:2],
                [Tile("4 $s1") for _ in 1:2],
                [Tile("6 $s1") for _ in 1:2],
                [Tile("8 $s1") for _ in 1:2],
                [Tile("$even $s2") for _ in 1:3],
                [Tile("$even $s3") for _ in 1:3]
            )
            push!(hands, MahjongHand(hand_id,
                "22 44 66 88 $even$even$even $even$even$even - $s1/$s2/$s3",
                tiles, 30))
            hand_id += 1
        end
    end
    
    # NN EE WWW SSS DDDD (Kong Any Dragon)
    for dragon in dragons
        tiles = vcat(
            [Tile("North Wind") for _ in 1:2],
            [Tile("East Wind") for _ in 1:2],
            [Tile("West Wind") for _ in 1:3],
            [Tile("South Wind") for _ in 1:3],
            [Tile(dragon) for _ in 1:4]
        )
        push!(hands, MahjongHand(hand_id,
            "NN EE WWW SSS DDDD ($dragon)",
            tiles, 30))
        hand_id += 1
    end
    
    # 369 SECTION
    
    # 333 6666 666 9999 (2 suits)
    for (s1, s2) in permutations(suits, 2)
        tiles = vcat(
            [Tile("3 $s1") for _ in 1:3],
            [Tile("6 $s1") for _ in 1:4],
            [Tile("6 $s2") for _ in 1:3],
            [Tile("9 $s2") for _ in 1:4]
        )
        push!(hands, MahjongHand(hand_id,
            "333 6666 666 9999 - $s1/$s2",
            tiles, 25))
        hand_id += 1
    end
    
    # 333 6666 666 9999 (3 suits)
    for (s1, s2, s3) in combinations(suits, 3)
        tiles = vcat(
            [Tile("3 $s1") for _ in 1:3],
            [Tile("6 $s1") for _ in 1:4],
            [Tile("6 $s2") for _ in 1:3],
            [Tile("9 $s3") for _ in 1:4]
        )
        push!(hands, MahjongHand(hand_id,
            "333 6666 666 9999 - $s1/$s2/$s3",
            tiles, 25))
        hand_id += 1
    end
    
    # FF 3333+6666=9999 (1 suit)
    for suit in suits
        tiles = vcat(
            [Tile("Flower") for _ in 1:2],
            [Tile("3 $suit") for _ in 1:4],
            [Tile("6 $suit") for _ in 1:4],
            [Tile("9 $suit") for _ in 1:4]
        )
        push!(hands, MahjongHand(hand_id,
            "FF 3333+6666=9999 - $suit",
            tiles, 25))
        hand_id += 1
    end
    
    # FF 3333+6666=9999 (3 suits)
    for (s1, s2, s3) in combinations(suits, 3)
        tiles = vcat(
            [Tile("Flower") for _ in 1:2],
            [Tile("3 $s1") for _ in 1:4],
            [Tile("6 $s2") for _ in 1:4],
            [Tile("9 $s3") for _ in 1:4]
        )
        push!(hands, MahjongHand(hand_id,
            "FF 3333+6666=9999 - $s1/$s2/$s3",
            tiles, 25))
        hand_id += 1
    end
    
    # 3333 DDD 3333 DDD (matching dragons with kongs)
    for (s1, s2) in permutations(suits, 2)
        # Determine dragons for each suit
        dragon1 = if s1 == "Character"
            "Red Dragon"
        elseif s1 == "Dot"
            "White Dragon"
        else  # Bamboo
            "Green Dragon"
        end
        
        dragon2 = if s2 == "Character"
            "Red Dragon"
        elseif s2 == "Dot"
            "White Dragon"
        else  # Bamboo
            "Green Dragon"
        end
        
        tiles = vcat(
            [Tile("3 $s1") for _ in 1:4],
            [Tile(dragon1) for _ in 1:3],
            [Tile("3 $s2") for _ in 1:4],
            [Tile(dragon2) for _ in 1:3]
        )
        push!(hands, MahjongHand(hand_id,
            "3333 DDD 3333 DDD - $s1/$s2",
            tiles, 25))
        hand_id += 1
    end
    
    # FFF 3333 369 9999 (kongs in s1, middle 369 in any suit)
    for s1 in suits
        for s2 in suits
            tiles = vcat(
                [Tile("Flower") for _ in 1:3],
                [Tile("3 $s1") for _ in 1:4],
                [Tile("3 $s2"), Tile("6 $s2"), Tile("9 $s2")],
                [Tile("9 $s1") for _ in 1:4]
            )
            push!(hands, MahjongHand(hand_id,
                "FFF 3333 369 9999 - $s1/$s2",
                tiles, 25))
            hand_id += 1
        end
    end
    
    # 33 66 99 3333 3333 (pairs 33 66 99 in s1, two kongs of 3/6/9 in s2 and s3)
    for (s1, s2, s3) in combinations(suits, 3)
        for kong_num in [3, 6, 9]
            tiles = vcat(
                [Tile("3 $s1") for _ in 1:2],
                [Tile("6 $s1") for _ in 1:2],
                [Tile("9 $s1") for _ in 1:2],
                [Tile("$kong_num $s2") for _ in 1:4],
                [Tile("$kong_num $s3") for _ in 1:4]
            )
            push!(hands, MahjongHand(hand_id,
                "33 66 99 $(kong_num)$(kong_num)$(kong_num)$(kong_num) $(kong_num)$(kong_num)$(kong_num)$(kong_num) - $s1/$s2/$s3",
                tiles, 25))
            hand_id += 1
        end
    end
    
    # FF 333 D 666 D 999 D
    for (s1, s2, s3) in combinations(suits, 3)
        tiles = vcat(
            [Tile("Flower") for _ in 1:2],
            [Tile("3 $s1") for _ in 1:3],
            [Tile("Red Dragon")],
            [Tile("6 $s2") for _ in 1:3],
            [Tile("Green Dragon")],
            [Tile("9 $s3") for _ in 1:3],
            [Tile("White Dragon")]
        )
        push!(hands, MahjongHand(hand_id,
            "FF 333 D 666 D 999 D - $s1/$s2/$s3",
            tiles, 30))
        hand_id += 1
    end
    
    # SINGLES AND PAIRS - high value hands
    
    # NN EW SS 11 22 33 44 (any 4 consecutive)
    for suit in suits
        for start in 1:6
            tiles = vcat(
                [Tile("North Wind") for _ in 1:2],
                [Tile("East Wind"), Tile("West Wind")],
                [Tile("South Wind") for _ in 1:2],
                [Tile("$start $suit") for _ in 1:2],
                [Tile("$(start+1) $suit") for _ in 1:2],
                [Tile("$(start+2) $suit") for _ in 1:2],
                [Tile("$(start+3) $suit") for _ in 1:2]
            )
            push!(hands, MahjongHand(hand_id,
                "NN EW SS $(start)$(start) $(start+1)$(start+1) $(start+2)$(start+2) $(start+3)$(start+3) - $suit",
                tiles, 50))
            hand_id += 1
        end
    end
    
    # FF 2468 DD 2468 DD (any 2 suits with matching dragons)
    for (s1, s2) in permutations(suits, 2)
        # Determine dragons for each suit
        dragon1 = if s1 == "Character"
            "Red Dragon"
        elseif s1 == "Dot"
            "White Dragon"
        else  # Bamboo
            "Green Dragon"
        end
        
        dragon2 = if s2 == "Character"
            "Red Dragon"
        elseif s2 == "Dot"
            "White Dragon"
        else  # Bamboo
            "Green Dragon"
        end
        
        tiles = vcat(
            [Tile("Flower") for _ in 1:2],
            [Tile("2 $s1"), Tile("4 $s1"), Tile("6 $s1"), Tile("8 $s1")],
            [Tile(dragon1) for _ in 1:2],
            [Tile("2 $s2"), Tile("4 $s2"), Tile("6 $s2"), Tile("8 $s2")],
            [Tile(dragon2) for _ in 1:2]
        )
        push!(hands, MahjongHand(hand_id,
            "FF 2468 DD 2468 DD - $s1/$s2",
            tiles, 50))
        hand_id += 1
    end
    
    # 336699 336699 33/66/99 (pairs 3,6,9 in s1 and s2, final pair of 3/6/9 in s3)
    for (s1, s2, s3) in combinations(suits, 3)
        for final_pair in [3, 6, 9]
            tiles = vcat(
                [Tile("3 $s1") for _ in 1:2],
                [Tile("3 $s2") for _ in 1:2],
                [Tile("6 $s1") for _ in 1:2],
                [Tile("6 $s2") for _ in 1:2],
                [Tile("9 $s1") for _ in 1:2],
                [Tile("9 $s2") for _ in 1:2],
                [Tile("$final_pair $s3") for _ in 1:2]
            )
            push!(hands, MahjongHand(hand_id,
                "336699 336699 $(final_pair)$(final_pair) - $s1/$s2/$s3",
                tiles, 50))
            hand_id += 1
        end
    end
    
    # FF 11 22 11 22 11 22 (any 3 suits, any 2 consec)
    for start in 1:8
        for (s1, s2, s3) in combinations(suits, 3)
            tiles = vcat(
                [Tile("Flower") for _ in 1:2],
                [Tile("$start $s1") for _ in 1:2],
                [Tile("$(start+1) $s1") for _ in 1:2],
                [Tile("$start $s2") for _ in 1:2],
                [Tile("$(start+1) $s2") for _ in 1:2],
                [Tile("$start $s3") for _ in 1:2],
                [Tile("$(start+1) $s3") for _ in 1:2]
            )
            push!(hands, MahjongHand(hand_id,
                "FF $(start)$(start) $(start+1)$(start+1) $(start)$(start) $(start+1)$(start+1) $(start)$(start) $(start+1)$(start+1) - $s1/$s2/$s3",
                tiles, 50))
            hand_id += 1
        end
    end
    
    # 11 33 55 77 99 XX XX (pairs of all odds in s1, two additional pairs of any odd in s2 and s3)
    for s1 in suits
        other_suits = [s for s in suits if s != s1]
        for (s2, s3) in combinations(other_suits, 2)
            for odd2 in [1, 3, 5, 7, 9]
                for odd3 in [1, 3, 5, 7, 9]
                    tiles = vcat(
                        [Tile("1 $s1") for _ in 1:2],
                        [Tile("3 $s1") for _ in 1:2],
                        [Tile("5 $s1") for _ in 1:2],
                        [Tile("7 $s1") for _ in 1:2],
                        [Tile("9 $s1") for _ in 1:2],
                        [Tile("$odd2 $s2") for _ in 1:2],
                        [Tile("$odd3 $s3") for _ in 1:2]
                    )
                    push!(hands, MahjongHand(hand_id,
                        "11 33 55 77 99 $(odd2)$(odd2) $(odd3)$(odd3) - $s1/$s2/$s3",
                        tiles, 50))
                    hand_id += 1
                end
            end
        end
    end
    
    # QUINTS
    
    # FF 111 2222 33333
    for (s1, s2, s3) in combinations(suits, 3)
        for start in 1:7
            tiles = vcat(
                [Tile("Flower") for _ in 1:2],
                [Tile("$start $s1") for _ in 1:3],
                [Tile("$(start+1) $s2") for _ in 1:4],
                [Tile("$(start+2) $s3") for _ in 1:5]
            )
            push!(hands, MahjongHand(hand_id,
                "FF $(start)$(start)$(start) $(start+1)$(start+1)$(start+1)$(start+1) $(start+2)$(start+2)$(start+2)$(start+2)$(start+2) - $s1/$s2/$s3",
                tiles, 40))
            hand_id += 1
        end
    end
    
    # 11111 WWWW 22222
    for suit in suits
        for start in 1:8
            for wind in ["North Wind", "East Wind", "West Wind", "South Wind"]
                tiles = vcat(
                    [Tile("$start $suit") for _ in 1:5],
                    [Tile(wind) for _ in 1:4],
                    [Tile("$(start+1) $suit") for _ in 1:5]
                )
                push!(hands, MahjongHand(hand_id,
                    "$(start)$(start)$(start)$(start)$(start) WWWW $(start+1)$(start+1)$(start+1)$(start+1)$(start+1) - $suit",
                    tiles, 45))
                hand_id += 1
            end
        end
    end
    
    # CONSECUTIVE RUN SECTION - Complete Implementation
    
    # 11 222 3333 444 55
    for suit in suits
        tiles = vcat(
            [Tile("1 $suit") for _ in 1:2],
            [Tile("2 $suit") for _ in 1:3],
            [Tile("3 $suit") for _ in 1:4],
            [Tile("4 $suit") for _ in 1:3],
            [Tile("5 $suit") for _ in 1:2]
        )
        push!(hands, MahjongHand(hand_id,
            "11 222 3333 444 55 - $suit",
            tiles, 25))
        hand_id += 1
        
        # 55 666 7777 888 99
        tiles = vcat(
            [Tile("5 $suit") for _ in 1:2],
            [Tile("6 $suit") for _ in 1:3],
            [Tile("7 $suit") for _ in 1:4],
            [Tile("8 $suit") for _ in 1:3],
            [Tile("9 $suit") for _ in 1:2]
        )
        push!(hands, MahjongHand(hand_id,
            "55 666 7777 888 99 - $suit",
            tiles, 25))
        hand_id += 1
    end
    
    # 111 2222 333 4444 (any 1 suit, any 4 consec)
    for s1 in suits
        for start in 1:6
            tiles = vcat(
                [Tile("$start $s1") for _ in 1:3],
                [Tile("$(start+1) $s1") for _ in 1:4],
                [Tile("$(start+2) $s1") for _ in 1:3],
                [Tile("$(start+3) $s1") for _ in 1:4]
            )
            push!(hands, MahjongHand(hand_id,
                "$(start)$(start)$(start) $(start+1)$(start+1)$(start+1)$(start+1) $(start+2)$(start+2)$(start+2) $(start+3)$(start+3)$(start+3)$(start+3) - $s1",
                tiles, 25))
            hand_id += 1
        end
    end
    
    # 111 2222 333 4444 (any 2 suits, any 4 consec)
    for (s1, s2) in combinations(suits, 2)
        for start in 1:6
            tiles = vcat(
                [Tile("$start $s1") for _ in 1:3],
                [Tile("$(start+1) $s1") for _ in 1:4],
                [Tile("$(start+2) $s2") for _ in 1:3],
                [Tile("$(start+3) $s2") for _ in 1:4]
            )
            push!(hands, MahjongHand(hand_id,
                "$(start)$(start)$(start) $(start+1)$(start+1)$(start+1)$(start+1) $(start+2)$(start+2)$(start+2) $(start+3)$(start+3)$(start+3)$(start+3) - $s1/$s2",
                tiles, 25))
            hand_id += 1
        end
    end
    
    # FFFF 1111 22 3333 (any 1 suit, any 3 consec)
    for suit in suits
        for start in 1:7
            tiles = vcat(
                [Tile("Flower") for _ in 1:4],
                [Tile("$start $suit") for _ in 1:4],
                [Tile("$(start+1) $suit") for _ in 1:2],
                [Tile("$(start+2) $suit") for _ in 1:4]
            )
            push!(hands, MahjongHand(hand_id,
                "FFFF $(start)$(start)$(start)$(start) $(start+1)$(start+1) $(start+2)$(start+2)$(start+2)$(start+2) - $suit",
                tiles, 25))
            hand_id += 1
        end
    end
    
    # FFFF 1111 22 3333 (any 3 suits, any 3 consec)
    for (s1, s2, s3) in combinations(suits, 3)
        for start in 1:7
            tiles = vcat(
                [Tile("Flower") for _ in 1:4],
                [Tile("$start $s1") for _ in 1:4],
                [Tile("$(start+1) $s2") for _ in 1:2],
                [Tile("$(start+2) $s3") for _ in 1:4]
            )
            push!(hands, MahjongHand(hand_id,
                "FFFF $(start)$(start)$(start)$(start) $(start+1)$(start+1) $(start+2)$(start+2)$(start+2)$(start+2) - $s1/$s2/$s3",
                tiles, 25))
            hand_id += 1
        end
    end
    
    # FFF 123 4444 5555 (any 3 suits, any 5 consecutive)
    for (s1, s2, s3) in combinations(suits, 3)
        for start in 1:5  # 1-5 for 5 consecutive
            tiles = vcat(
                [Tile("Flower") for _ in 1:3],
                [Tile("$start $s1"), Tile("$(start+1) $s1"), Tile("$(start+2) $s1")],
                [Tile("$(start+3) $s2") for _ in 1:4],
                [Tile("$(start+4) $s3") for _ in 1:4]
            )
            push!(hands, MahjongHand(hand_id,
                "FFF $(start)$(start+1)$(start+2) $(start+3)$(start+3)$(start+3)$(start+3) $(start+4)$(start+4)$(start+4)$(start+4) - $s1/$s2/$s3",
                tiles, 25))
            hand_id += 1
        end
    end
    
    # FFF 111 22 33333 (any 3 suits, any 5 consec)
    for (s1, s2, s3) in combinations(suits, 3)
        for start in 1:5
            tiles = vcat(
                [Tile("Flower") for _ in 1:3],
                [Tile("$start $s1") for _ in 1:3],
                [Tile("$(start+1) $s2") for _ in 1:2],
                [Tile("$(start+2) $s3") for _ in 1:5]
            )
            push!(hands, MahjongHand(hand_id,
                "FFF $(start)$(start)$(start) $(start+1)$(start+1) $(start+2)$(start+2)$(start+2)$(start+2)$(start+2) - $s1/$s2/$s3",
                tiles, 25))
            hand_id += 1
        end
    end
    
    # FF 11 222 3333 DDD (any 1 suit, any 3 consec, matching dragon)
    for suit in suits
        for start in 1:7
            # Determine dragon
            dragon = if suit == "Character"
                "Red Dragon"
            elseif suit == "Dot"
                "White Dragon"
            else  # Bamboo
                "Green Dragon"
            end
            
            tiles = vcat(
                [Tile("Flower") for _ in 1:2],
                [Tile("$start $suit") for _ in 1:2],
                [Tile("$(start+1) $suit") for _ in 1:3],
                [Tile("$(start+2) $suit") for _ in 1:4],
                [Tile(dragon) for _ in 1:3]
            )
            push!(hands, MahjongHand(hand_id,
                "FF $(start)$(start) $(start+1)$(start+1)$(start+1) $(start+2)$(start+2)$(start+2)$(start+2) DDD - $suit",
                tiles, 25))
            hand_id += 1
        end
    end
    
    # 111 222 3333 DD DD (any 1 suit, 2 opp dragons)
    for suit in suits
        for start in 1:7
            # Get opposite dragons
            available_dragons = []
            if suit != "Character"
                push!(available_dragons, "Red Dragon")
            end
            if suit != "Bamboo"
                push!(available_dragons, "Green Dragon")
            end
            if suit != "Dot"
                push!(available_dragons, "White Dragon")
            end
            
            for (d1, d2) in combinations(available_dragons, 2)
                tiles = vcat(
                    [Tile("$start $suit") for _ in 1:3],
                    [Tile("$(start+1) $suit") for _ in 1:3],
                    [Tile("$(start+2) $suit") for _ in 1:4],
                    [Tile(d1) for _ in 1:2],
                    [Tile(d2) for _ in 1:2]
                )
                push!(hands, MahjongHand(hand_id,
                    "$(start)$(start)$(start) $(start+1)$(start+1)$(start+1) $(start+2)$(start+2)$(start+2)$(start+2) DD DD - $suit",
                    tiles, 30))
                hand_id += 1
            end
        end
    end
    
    # 112345 1111 1111 (any 5 consec in s1, two kongs in s2 and s3)
    for (s1, s2, s3) in combinations(suits, 3)
        for start in 1:5
            # Try all numbers in the run for kongs
            for kong_num in start:(start+4)
                tiles = vcat(
                    [Tile("$start $s1") for _ in 1:2],
                    [Tile("$(start+1) $s1")],
                    [Tile("$(start+2) $s1")],
                    [Tile("$(start+3) $s1")],
                    [Tile("$(start+4) $s1")],
                    [Tile("$kong_num $s2") for _ in 1:4],
                    [Tile("$kong_num $s3") for _ in 1:4]
                )
                push!(hands, MahjongHand(hand_id,
                    "$(start)$(start)$(start+1)$(start+2)$(start+3)$(start+4) $(kong_num)$(kong_num)$(kong_num)$(kong_num) $(kong_num)$(kong_num)$(kong_num)$(kong_num) - $s1/$s2/$s3",
                    tiles, 30))
                hand_id += 1
            end
        end
    end
    
    # FF 1 22 333 1 22 333 (any 2 suits, any same 3 consec)
    for (s1, s2) in combinations(suits, 2)
        for start in 1:7
            tiles = vcat(
                [Tile("Flower") for _ in 1:2],
                [Tile("$start $s1")],
                [Tile("$(start+1) $s1") for _ in 1:2],
                [Tile("$(start+2) $s1") for _ in 1:3],
                [Tile("$start $s2")],
                [Tile("$(start+1) $s2") for _ in 1:2],
                [Tile("$(start+2) $s2") for _ in 1:3]
            )
            push!(hands, MahjongHand(hand_id,
                "FF $(start) $(start+1)$(start+1) $(start+2)$(start+2)$(start+2) $(start) $(start+1)$(start+1) $(start+2)$(start+2)$(start+2) - $s1/$s2",
                tiles, 30))
            hand_id += 1
        end
    end
    
    # FF 11111 11 11111 (three different suits)
    for num in 1:9
        for (s1, s2, s3) in combinations(suits, 3)
            tiles = vcat(
                [Tile("Flower") for _ in 1:2],
                [Tile("$num $s1") for _ in 1:5],
                [Tile("$num $s2") for _ in 1:2],
                [Tile("$num $s3") for _ in 1:5]
            )
            push!(hands, MahjongHand(hand_id,
                "FF $(num)$(num)$(num)$(num)$(num) $(num)$(num) $(num)$(num)$(num)$(num)$(num) - $s1/$s2/$s3",
                tiles, 45))
            hand_id += 1
        end
    end
    
    # 13579 SECTION - Complete Implementation
    
    # 11 333 5555 777 99 (any 1 suit)
    for suit in suits
        tiles = vcat(
            [Tile("1 $suit") for _ in 1:2],
            [Tile("3 $suit") for _ in 1:3],
            [Tile("5 $suit") for _ in 1:4],
            [Tile("7 $suit") for _ in 1:3],
            [Tile("9 $suit") for _ in 1:2]
        )
        push!(hands, MahjongHand(hand_id,
            "11 333 5555 777 99 - $suit",
            tiles, 25))
        hand_id += 1
    end
    
    # 11 333 5555 777 99 (3 suits: 1&3 in s1, 5 in s2, 7&9 in s3)
    for (s1, s2, s3) in combinations(suits, 3)
        tiles = vcat(
            [Tile("1 $s1") for _ in 1:2],
            [Tile("3 $s1") for _ in 1:3],
            [Tile("5 $s2") for _ in 1:4],
            [Tile("7 $s3") for _ in 1:3],
            [Tile("9 $s3") for _ in 1:2]
        )
        push!(hands, MahjongHand(hand_id,
            "11 333 5555 777 99 - $s1/$s2/$s3",
            tiles, 25))
        hand_id += 1
    end
    
    # 111 3333 333 5555 (any 2 suits)
    for (s1, s2) in combinations(suits, 2)
        tiles = vcat(
            [Tile("1 $s1") for _ in 1:3],
            [Tile("3 $s1") for _ in 1:4],
            [Tile("3 $s2") for _ in 1:3],
            [Tile("5 $s2") for _ in 1:4]
        )
        push!(hands, MahjongHand(hand_id,
            "111 3333 333 5555 - $s1/$s2",
            tiles, 25))
        hand_id += 1
    end
    
    # 555 7777 777 9999 (any 2 suits)
    for (s1, s2) in combinations(suits, 2)
        tiles = vcat(
            [Tile("5 $s1") for _ in 1:3],
            [Tile("7 $s1") for _ in 1:4],
            [Tile("7 $s2") for _ in 1:3],
            [Tile("9 $s2") for _ in 1:4]
        )
        push!(hands, MahjongHand(hand_id,
            "555 7777 777 9999 - $s1/$s2",
            tiles, 25))
        hand_id += 1
    end
    
    # 1111 333 5555 DDD (any 1 suit with matching dragon)
    for suit in suits
        dragon = if suit == "Character"
            "Red Dragon"
        elseif suit == "Dot"
            "White Dragon"
        else  # Bamboo
            "Green Dragon"
        end
        
        tiles = vcat(
            [Tile("1 $suit") for _ in 1:4],
            [Tile("3 $suit") for _ in 1:3],
            [Tile("5 $suit") for _ in 1:4],
            [Tile(dragon) for _ in 1:3]
        )
        push!(hands, MahjongHand(hand_id,
            "1111 333 5555 DDD - $suit",
            tiles, 25))
        hand_id += 1
    end
    
    # 5555 777 9999 DDD (any 1 suit with matching dragon)
    for suit in suits
        dragon = if suit == "Character"
            "Red Dragon"
        elseif suit == "Dot"
            "White Dragon"
        else  # Bamboo
            "Green Dragon"
        end
        
        tiles = vcat(
            [Tile("5 $suit") for _ in 1:4],
            [Tile("7 $suit") for _ in 1:3],
            [Tile("9 $suit") for _ in 1:4],
            [Tile(dragon) for _ in 1:3]
        )
        push!(hands, MahjongHand(hand_id,
            "5555 777 9999 DDD - $suit",
            tiles, 25))
        hand_id += 1
    end
    
    # FFFF 1111 + 9999 = 10 (1111 and 9999 in s1, final 1+0 any other suit)
    for s1 in suits
        for s2 in suits
            if s1 != s2
                tiles = vcat(
                    [Tile("Flower") for _ in 1:4],
                    [Tile("1 $s1") for _ in 1:4],
                    [Tile("9 $s1") for _ in 1:4],
                    [Tile("1 $s2")],
                    [Tile("White Dragon")]
                )
                push!(hands, MahjongHand(hand_id,
                    "FFFF 1111 + 9999 = 10 - $s1/$s2",
                    tiles, 25))
                hand_id += 1
            end
        end
    end
    
    # FFF 135 7777 9999 (any 1 suit)
    for suit in suits
        tiles = vcat(
            [Tile("Flower") for _ in 1:3],
            [Tile("1 $suit"), Tile("3 $suit"), Tile("5 $suit")],
            [Tile("7 $suit") for _ in 1:4],
            [Tile("9 $suit") for _ in 1:4]
        )
        push!(hands, MahjongHand(hand_id,
            "FFF 135 7777 9999 - $suit",
            tiles, 25))
        hand_id += 1
    end
    
    # FFF 135 7777 9999 (3 suits: 135 in s1, 7777 in s2, 9999 in s3)
    for (s1, s2, s3) in combinations(suits, 3)
        tiles = vcat(
            [Tile("Flower") for _ in 1:3],
            [Tile("1 $s1"), Tile("3 $s1"), Tile("5 $s1")],
            [Tile("7 $s2") for _ in 1:4],
            [Tile("9 $s3") for _ in 1:4]
        )
        push!(hands, MahjongHand(hand_id,
            "FFF 135 7777 9999 - $s1/$s2/$s3",
            tiles, 25))
        hand_id += 1
    end
    
    # 111 333 5555 DD DD (numbers in one suit, dragons opposite)
    for s1 in suits
        # Get opposite dragons
        available_dragons = []
        if s1 != "Character"
            push!(available_dragons, "Red Dragon")
        end
        if s1 != "Bamboo"
            push!(available_dragons, "Green Dragon")
        end
        if s1 != "Dot"
            push!(available_dragons, "White Dragon")
        end
        
        dragon1, dragon2 = available_dragons[1], available_dragons[2]
        
        tiles = vcat(
            [Tile("1 $s1") for _ in 1:3],
            [Tile("3 $s1") for _ in 1:3],
            [Tile("5 $s1") for _ in 1:4],
            [Tile(dragon1) for _ in 1:2],
            [Tile(dragon2) for _ in 1:2]
        )
        push!(hands, MahjongHand(hand_id,
            "111 333 5555 DD DD - $s1",
            tiles, 30))
        hand_id += 1
    end
    
    # 555 777 9999 DD DD (numbers in one suit, dragons opposite)
    for s1 in suits
        # Get opposite dragons
        available_dragons = []
        if s1 != "Character"
            push!(available_dragons, "Red Dragon")
        end
        if s1 != "Bamboo"
            push!(available_dragons, "Green Dragon")
        end
        if s1 != "Dot"
            push!(available_dragons, "White Dragon")
        end
        
        dragon1, dragon2 = available_dragons[1], available_dragons[2]
        
        tiles = vcat(
            [Tile("5 $s1") for _ in 1:3],
            [Tile("7 $s1") for _ in 1:3],
            [Tile("9 $s1") for _ in 1:4],
            [Tile(dragon1) for _ in 1:2],
            [Tile(dragon2) for _ in 1:2]
        )
        push!(hands, MahjongHand(hand_id,
            "555 777 9999 DD DD - $s1",
            tiles, 30))
        hand_id += 1
    end
    
    # 11 333 NEWS 333 55 (any 2 suits)
    for (s1, s2) in permutations(suits, 2)
        tiles = vcat(
            [Tile("1 $s1") for _ in 1:2],
            [Tile("3 $s1") for _ in 1:3],
            [Tile("North Wind"), Tile("East Wind"), Tile("West Wind"), Tile("South Wind")],
            [Tile("3 $s2") for _ in 1:3],
            [Tile("5 $s2") for _ in 1:2]
        )
        push!(hands, MahjongHand(hand_id,
            "11 333 NEWS 333 55 - $s1/$s2",
            tiles, 30))
        hand_id += 1
    end
    
    # 55 777 NEWS 777 99 (any 2 suits)
    for (s1, s2) in permutations(suits, 2)
        tiles = vcat(
            [Tile("5 $s1") for _ in 1:2],
            [Tile("7 $s1") for _ in 1:3],
            [Tile("North Wind"), Tile("East Wind"), Tile("West Wind"), Tile("South Wind")],
            [Tile("7 $s2") for _ in 1:3],
            [Tile("9 $s2") for _ in 1:2]
        )
        push!(hands, MahjongHand(hand_id,
            "55 777 NEWS 777 99 - $s1/$s2",
            tiles, 30))
        hand_id += 1
    end
    
    # 1111 33 55 77 9999 (any 2 suits)
    for (s1, s2) in combinations(suits, 2)
        tiles = vcat(
            [Tile("1 $s1") for _ in 1:4],
            [Tile("3 $s1") for _ in 1:2],
            [Tile("5 $s2") for _ in 1:2],
            [Tile("7 $s2") for _ in 1:2],
            [Tile("9 $s1") for _ in 1:4]
        )
        push!(hands, MahjongHand(hand_id,
            "1111 33 55 77 9999 - $s1/$s2",
            tiles, 30))
        hand_id += 1
    end
    
    # FF 11 33 111 333 55 (any 3 suits)
    for (s1, s2, s3) in combinations(suits, 3)
        tiles = vcat(
            [Tile("Flower") for _ in 1:2],
            [Tile("1 $s1") for _ in 1:2],
            [Tile("3 $s1") for _ in 1:2],
            [Tile("1 $s2") for _ in 1:3],
            [Tile("3 $s2") for _ in 1:3],
            [Tile("5 $s3") for _ in 1:2]
        )
        push!(hands, MahjongHand(hand_id,
            "FF 11 33 111 333 55 - $s1/$s2/$s3",
            tiles, 30))
        hand_id += 1
    end
    
    # FF 55 77 555 777 99 (any 3 suits)
    for (s1, s2, s3) in combinations(suits, 3)
        tiles = vcat(
            [Tile("Flower") for _ in 1:2],
            [Tile("5 $s1") for _ in 1:2],
            [Tile("7 $s1") for _ in 1:2],
            [Tile("5 $s2") for _ in 1:3],
            [Tile("7 $s2") for _ in 1:3],
            [Tile("9 $s3") for _ in 1:2]
        )
        push!(hands, MahjongHand(hand_id,
            "FF 55 77 555 777 99 - $s1/$s2/$s3",
            tiles, 30))
        hand_id += 1
    end
    
    # Remove duplicate hands (same tiles, same points)
    println("Generated $(length(hands)) hands before deduplication")

    seen = Set{Tuple{Vector{String}, Int, String}}()
    unique_hands = MahjongHand[]

    for hand in hands
        key = canonical_hand_key(hand)
        
        if !(key in seen)
            push!(seen, key)
            push!(unique_hands, hand)
        end
    end

    println("Returning $(length(unique_hands)) unique hands after deduplication")
    
    return unique_hands
end

"""
Check if a hand can still be completed given current tiles and discards
"""
function is_hand_viable(hand::MahjongHand, my_tiles::Vector{Tile}, 
                        seen_tiles::Vector{Tile}, exposed_sets::Vector{Vector{Tile}}=Vector{Tile}[])
    # Count tiles we have vs need
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
    
    seen_counts = Dict{String, Int}()
    for tile in seen_tiles
        seen_counts[tile.name] = get(seen_counts, tile.name, 0) + 1
    end
    
    # Check if we can still get required tiles
    for (tile_name, needed) in required_counts
        have = get(have_counts, tile_name, 0)
        seen = get(seen_counts, tile_name, 0)
        
        # Determine max available (4 for most tiles, 8 for flowers/jokers)
        max_available = if tile_name == "Flower"
            8
        elseif occursin("Dragon", tile_name) || occursin("Wind", tile_name)
            4
        else
            4
        end
        
        # CRITICAL FIX: seen_tiles should include everything visible
        # Don't subtract 'have' - seen_tiles should already include our hand
        still_available = max_available - seen
        
        # If we need more than what's available, hand is not viable
        if (needed - have) > still_available
            return false
        end
    end
    
    return true
end
"""
Calculate tiles needed to complete a hand
"""
function tiles_needed_for_hand(hand::MahjongHand, my_tiles::Vector{Tile})
    needed = Tile[]
    
    required_counts = Dict{String, Int}()
    for tile in hand.required_tiles
        required_counts[tile.name] = get(required_counts, tile.name, 0) + 1
    end
    
    have_counts = Dict{String, Int}()
    for tile in my_tiles
        have_counts[tile.name] = get(have_counts, tile.name, 0) + 1
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
Get all viable hands given current state
"""
function get_viable_hands(all_hands::Vector{MahjongHand}, 
                         my_tiles::Vector{Tile}, 
                         seen_tiles::Vector{Tile},
                         exposed_sets::Vector{Vector{Tile}}=Vector{Tile}[])
    viable = MahjongHand[]
    
    for hand in all_hands
        if is_hand_viable(hand, my_tiles, seen_tiles, exposed_sets)
            push!(viable, hand)
        end
    end
    
    return viable
end

# Export functions
export generate_mahjong_hands, is_hand_viable, tiles_needed_for_hand, get_viable_hands