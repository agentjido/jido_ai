# Sparq Scene Specification

## Overview

A scene in Sparq represents a discrete unit of conversation. Each scene contains a series of beats - dramatic moments that combine character dialogue, user interaction, and flow control. The scene system uses Elixir-inspired syntax to create clear, maintainable conversation structures.

## Core Syntax

Scenes follow a declarative structure that emphasizes narrative flow:

```sparq
scene InitialContact do
  @title "First User Contact"
  @characters [TechnicalGuide]
  
  beat :start do
    narrate "A friendly interface appears"
    speak TechnicalGuide, "Hello! How can I help you today?"
    
    choose do
      option "I'm new here", :new_user
      option "I have a question", :has_question
      option "Just browsing", :browsing
    end
  end
  
  beat :new_user do
    speak TechnicalGuide, "Welcome! Let me show you around."
    transition :GettingStarted
  end
  
  beat :has_question do
    speak TechnicalGuide, "What would you like to know?"
    response = ask()
    transition :QuestionHandling
  end
  
  beat :browsing do
    speak TechnicalGuide, "Feel free to explore. I'm here if you need me!"
    transition :Idle
  end
end
```

## Scene Commands

Each beat can use these core commands to create interactions:

```sparq
# Narrative description
narrate "description"

# Character dialogue
speak Character, "message"

# Get user input
response = ask()
response = ask("prompt")

# Present choices
choose do
  option "label", :beat_name
  option "label", :beat_name, when: condition
end

# Move to another scene
transition :NewScene
```

## Concurrency Commands

Scenes support concurrent execution through these commands:

```sparq
# Launch a flow asynchronously
direct Character, :flow_name, args, async: true

# Wait for a character's flow to complete
result = wait Character

# Run multiple flows in parallel
parallel do
  direct CharacterA, :flow_name, args, async: true
  direct CharacterB, :other_flow, args, async: true
end
```

## Input Handling

Scenes provide sophisticated input handling:

```sparq
beat :get_user_intent do
  response = ask UserCharacter, "What would you like help with?"
  
  listen response do
    when match("help *") do
      speak Guide, "I'll help you with that"
      transition :help_flow
    end
    
    when match("* not working") do
      speak Guide, "Let's troubleshoot that"
      transition :troubleshoot_flow
    end
    
    # Fallback
    speak Guide, "I'm not sure I understood. Could you rephrase that?"
  end
end
```

## Behavior Blocks

Scenes can define coordinated behaviors between characters using behavior blocks:

```sparq
behavior coordination_name do
  sync Character1, Character2 do
    movement: [:pattern1, :pattern2]
    timing: [:sync_type1, :sync_type2]
    patterns: [:pattern1, :pattern2]
  end
end
```

Behavior blocks allow:
- Character synchronization
- Movement patterns
- Timing coordination
- Interaction patterns

These behaviors can be referenced in beats to create coordinated character actions.

## Internal Structure

The scene system generates these runtime structures:

```sparq
%Scene{
  title: String.t(),
  characters: [Character.t()],
  beats: %{
    atom() => Beat.t()
  },
  current_beat: atom()
}

%Beat{
  name: atom(),
  commands: [Command.t()],
  transitions: [Transition.t()]
}
```

## Validation Rules

A scene must follow these rules:

1. Required Attributes:
   - `@title`: A descriptive string
   - `@characters`: A list of valid character modules

2. Beat Requirements:
   - Must have a `start` beat
   - All referenced beats must exist
   - Beats must end with either a transition or choice
   - Cannot transition to the same beat

## Extended Example

Here's a more detailed scene showing common interaction patterns:

```sparq
scene TroubleshootingSession do
  @title "Technical Support Interaction"
  @characters [TechnicalGuide]
  
  beat :start do
    narrate "The technical guide reviews the situation"
    speak TechnicalGuide, "I'll help you resolve this issue."
    
    choose do
      option "Error message", :handle_error
      option "Performance issue", :handle_performance
      option "Other problem", :handle_general
    end
  end
  
  beat :handle_error do
    speak TechnicalGuide, "Could you share the error message?"
    error_details = ask()
    
    speak TechnicalGuide, "Let me analyze that for you."
    transition :ErrorAnalysis
  end
  
  beat :handle_performance do
    speak TechnicalGuide, "I'll help you optimize your system."
    
    choose do
      option "Run diagnostics", :run_tests
      option "View recommendations", :show_tips
    end
  end
  
  beat :run_tests do
    narrate "The guide initiates system diagnostics"
    speak TechnicalGuide, "Running performance checks..."
    transition :DiagnosticsScene
  end
  
  beat :show_tips do
    speak TechnicalGuide, "Here are some performance recommendations:"
    narrate "The guide displays a list of optimization tips"
    transition :Recommendations
  end
  
  beat :handle_general do
    speak TechnicalGuide, "Could you describe the issue?"
    problem_description = ask()
    transition :GeneralTroubleshooting
  end
end
```

## Best Practices

Consider these guidelines when writing scenes:

1. Scene Organization
   - Keep scenes focused on a single interaction goal
   - Use meaningful beat names
   - Create clear user paths through the conversation
   - Handle all expected user responses

2. Character Interactions
   - Maintain consistent character voices
   - Use narration to set context
   - Provide meaningful responses to user input
   - Keep dialogue natural and purposeful

3. Flow Control
   - Make transitions logical and clear
   - Provide appropriate choices
   - Allow users to navigate the conversation naturally
   - Handle unexpected inputs gracefully

## Extended Example with Concurrency

Here's a scene demonstrating concurrent character interactions:

```sparq
scene ParallelInvestigation do
  @title "Multi-Character Investigation"
  @characters [TechnicalGuide, DevOpsGuide]
  
  beat :start do
    speak TechnicalGuide, "We'll investigate this together"
    
    parallel do
      direct TechnicalGuide, :analyze_logs, async: true
      direct DevOpsGuide, :check_metrics, async: true
    end
    
    speak TechnicalGuide, "Analysis in progress..."
    transition :gather_results
  end
  
  beat :gather_results do
    log_results = wait TechnicalGuide
    metric_results = wait DevOpsGuide
    
    speak TechnicalGuide, "Here's what we found: #{log_results}"
    speak DevOpsGuide, "And the metrics show: #{metric_results}"
    
    transition :present_findings
  end
end
```