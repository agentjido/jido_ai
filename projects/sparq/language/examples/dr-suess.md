# Dr. Seuss Style Sparq Example

This example shows how to create whimsical, playful interactions using Sparq's scene, flow, and tool system.

## The Rainy Day Scene

```sparq
scene RainyDayFun do
  @title "A Very Rainy Day"
  @characters [CatInHat, ThingOne, ThingTwo]
  
  # Define the synchronized behaviors of Thing One and Thing Two
  behavior things_coordination do
    sync ThingOne, ThingTwo do
      movement: [:mirror, :alternate, :chase]
      timing: [:synchronized, :alternating]
      patterns: [:circle, :figure_eight, :spiral]
    end
  end
  
  beat :start do
    narrate "The rain! The rain! 
            The rain makes the day very plain!"
    
    speak CatInHat, "Do not fret! Do not fear!
                     The Cat in the Hat is finally here!"
    
    choose do
      option "Let's play a game!", :play_game
      option "Can you clean this mess?", :clean_mess
      option "I'm a bit worried...", :provide_comfort
    end
  end
  
  beat :play_game do
    speak CatInHat, "Oh what fun! What fun!
                     Let me show you game number ONE!"
    transition :FunAndGames
  end
  
  beat :clean_mess do
    speak CatInHat, "A mess you say? Oh what a sight!
                     But worry not, we'll make it right!"
    transition :CleaningTime
  end
  
  beat :provide_comfort do
    speak CatInHat, "Now, now, no need to fret or fear,
                     The Cat in the Hat has tricks right here!"
    transition :ComfortScene
  end
end
```

## The Cat's Cleanup Flow

```sparq
flow CleanupProcess do
  @character CatInHat
  @goal "Clean up the mess in a fun and entertaining way"
  @timeout :timer.minutes(5)  # The Cat works fast!
  
  step :assess_mess do
    when mess_level() == :extreme do
      deploy_cleaning_machine()
    end
    
    when mess_level() == :moderate do
      coordinate_thing_cleanup()
    end
    
    # Default for small messes
    simple_cleanup()
  end
  
  step :entertain_while_cleaning do
    when children_attention() < 0.5 do
      perform_juggling_act()
    end
    
    maintain_excitement()
  end
  
  step :final_flourish do
    when everything_clean?() do
      perform_victory_dance()
    end
    
    # If not quite done
    promise_to_return()
  end
end
```

## The Cat's Special Tools

```sparq
tool CleaningMachine do
  @description "The Cat's marvelous cleaning contraption"
  @input_type :mess_details
  @output_type :cleanup_result
  @timeout :timer.seconds(30)
  
  def run(mess, context) do
    case activate_machine(mess) do
      {:ok, result} -> {:ok, "The machine whirred and purred, and the mess was gone!"}
      {:error, _} -> {:error, "Oh dear! The machine seems to have a case of the hiccups!"}
    end
  end
end

tool ThingCoordinator do
  @description "Coordinates Thing One and Thing Two for synchronized cleanup"
  @input_type :cleanup_plan
  @output_type :coordination_result
  
  def run(plan, context) do
    case coordinate_things(plan) do
      {:ok, _} -> {:ok, "Thing One and Thing Two, they knew what to do!"}
      {:error, reason} -> {:error, "Oh my! The Things got tangled in a knot!"}
    end
  end
end

tool TrickGenerator do
  @description "Generates entertaining tricks to keep children amazed"
  @input_type :entertainment_need
  @output_type :trick_sequence
  
  def run(need, context) do
    case generate_trick_sequence(need) do
      {:ok, tricks} -> {:ok, "A trick up my sleeve, you won't believe!"}
      {:error, _} -> {:error, "Even the best tricks sometimes need a rest!"}
    end
  end
end
```

## The Parallel Play Scene

```sparq
scene ParallelPlaytime do
  @title "Double the Fun!"
  @characters [CatInHat, ThingOne, ThingTwo]
  
  beat :start do
    speak CatInHat, "Now watch with glee, as Things One and Two
                     Show what they can do, just for you!"
    
    parallel do
      direct ThingOne, :juggle_fun, items: [:fish, :cake, :rake], async: true
      direct ThingTwo, :balance_act, items: [:books, :ship, :dish], async: true
    end
    
    speak CatInHat, "Round and round, up and down,
                     The best show in this part of town!"
    
    transition :watch_performance
  end
  
  beat :watch_performance do
    thing_one_result = wait ThingOne
    thing_two_result = wait ThingTwo
    
    speak CatInHat, "#{thing_one_result} and #{thing_two_result}
                     What a show! What a sight!
                     Wasn't that a pure delight?"
                     
    response = ask UserCharacter, "What did you think of our show?"
    
    listen response do
      when match("* amazing *") do
        speak CatInHat, "Amazing indeed! That's just what we need!"
        transition :encore_performance
      end
      
      when match("* more *") do
        speak CatInHat, "More you say? Well okay!"
        transition :bonus_tricks
      end
      
      # Default response in rhyme
      speak CatInHat, "Whatever you say, makes my day!"
      transition :wrap_up
    end
  end
end
```

## The Things' Parallel Flows

```sparq
flow JuggleFun do
  @character ThingOne
  @goal "Juggle items in an entertaining pattern"
  
  step :prepare_items do
    when items_ready?() do
      start_juggling_sequence()
    end
  end
  
  step :perform_tricks do
    direct CatInHat, :provide_commentary, async: true
    execute_juggling_routine()
  end
end

flow BalanceAct do
  @character ThingTwo
  @goal "Balance items in impossible ways"
  
  step :stack_items do
    when items_stable?() do
      begin_balancing_act()
    end
  end
  
  step :add_complexity do
    direct CatInHat, :build_suspense, async: true
    perform_balance_routine()
  end
end
```

This example demonstrates:
1. Scene structure with playful dialogue and choices
2. Flow control with the Cat's cleanup process
3. Tools for special abilities and coordination
4. Consistent error handling with whimsical messages
5. Character coordination with Thing One and Thing Two