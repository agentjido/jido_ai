# Sparq Language Specification

## 1. Special Agents

### 1.1 The Narrator
- Implicitly available in every script
- Provides omniscient narrative voice
- Can narrate scenes and coordinate transitions
- Maintains story cohesion and flow
- Available through `narrate` command

Core Narrator Commands:
- `narrate`: Scene description/ambiance
- `note`: Script annotations/context
- `transition`: Transition to a new scene

## 1. Core Philosophy
- Story-first approach to conversational AI
- Writer-friendly syntax inspired by screenwriting
- HTN planning engine hidden behind narrative constructs
- Clear separation between interactive and autonomous behaviors

## 2. Top-Level Constructs

### 2.1 Characters
- Must be defined at script root level
- Cannot be defined inside scenes or flows
- Define personality, capabilities, and behavior patterns
- Are autonomous agents with memory and state

Required Character Properties:
- name: Unique identifier
- goal: Primary objective
- backstory: Character history/context

### 2.2 Scenes
- Interactive dialog sections
- Multiple characters can participate
- Organized by story beats
- Support branching and transitions

Core Scene Commands:
- `say`: Character dialog output
- `ask`: Request user input
- `show`: Display media/UI artifacts
- `choice`: Branch point definition

### 2.4 Story Beats
- Named dramatic units within scenes
- Delimited with `beat` keyword blocks
- Can contain multiple interactions
- Support conditional progression
- Track narrative state changes

Story Beat Features:
- Title/identifier
- Pre/post conditions
- Character interactions
- State modifications
- Transition rules

### 2.2.1. Inter-character communication
- `narrate`: Scene description/ambiance
- `note`: Script annotations/context
- `transition`: Transition to a new scene

### 2.3 Flows
- Single-character HTN domains
- Autonomous task execution
- One-way communication to script
- Goal-oriented behavior sequences

Flow Components:
- character: Single assigned character
- goal: Primary objective
- tasks: Hierarchical task definitions
- conditions: Execution requirements
- log: Progress/status logging

### 2.5 Concurrency & Flow Orchestration

Sparq supports concurrent execution and flow orchestration through several key commands:

#### direct
Used to instruct a character to run a flow. Can be synchronous or asynchronous:
```sparq
# Synchronous (default)
direct Character, :flow_name, args

# Asynchronous
direct Character, :flow_name, args, async: true
```

#### wait
Used to block/wait on a previously launched flow from a character:
```sparq
result = wait Character
```

#### parallel
Runs multiple instructions in parallel, collecting results:
```sparq
parallel do
  direct CharacterA, :some_flow, arg, async: true
  direct CharacterB, :another_flow, arg, async: true
end
```

### 2.6 User Input & Listening

Sparq provides sophisticated input handling through ask and listen commands:

#### ask
Prompts for and captures user input:
```sparq
response = ask UserCharacter, "How can I help you?"
```

#### listen
Pattern-matches or classifies user input with fallback handling:
```sparq
listen user_input do
  when match("help *") do
    speak Guide, "I'll help you with that"
    transition :help_flow
  end
  
  when match("* not working") do
    speak Guide, "Let's troubleshoot that"
    transition :troubleshoot_flow
  end
  
  # Fallback for unmatched input
  speak Guide, "Could you rephrase that?"
end
```

## 3. State Management

### 3.1 Character State
- Emotional state
- Knowledge base
- Relationship data
- Goal progress
- Memory contents

### 3.2 Scene State
- Active participants
- Environmental context
- Available choices
- Interaction history
- Local variables

### 3.3 Story State
- Global progression
- Achievement tracking
- Relationship networks
- World state
- Persistent variables

## 4. Control Flow

### 4.1 Transitions
- Between scenes: transition_to
- Within scenes: next_beat
- Conditional: when/unless
- Choice-based: choice blocks
- Automatic: state-triggered

### 4.2 Error Handling
- Graceful degradation
- Fallback responses
- Error recovery states
- Debug logging
- State preservation

## 5. Memory Model

### 5.1 Character Memory
- Short-term: Current interaction
- Working: Active goals/tasks
- Long-term: Learned patterns
- Episodic: Event history

### 5.2 Story Memory
- Global variables
- Character relationships
- World state history
- Achievement records

## 6. Syntax Rules

### 6.1 Block Structure
- Uses do/end blocks
- Proper nesting required
- Clear scope boundaries
- Consistent indentation

### 6.2 Naming Conventions
- Characters: PascalCase
- Scenes: PascalCase
- Flows: PascalCase
- Variables: snake_case
- Constants: SCREAMING_SNAKE_CASE

## 7. Best Practices

### 7.1 Scene Design
- One primary purpose per scene
- Clear entry/exit points
- Reasonable branching limits
- State validation
- Error recovery paths

### 7.2 Character Design
- Consistent personality
- Clear expertise domains
- Reasonable autonomy
- Appropriate memory scope
- Defined boundaries

### 7.3 Flow Design
- Single responsibility
- Clear success criteria
- Proper task decomposition
- Status reporting
- Error handling