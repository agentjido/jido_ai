# Updated Conversational DSL Design Document

## Core Philosophy
Our DSL merges screenwriting metaphors with multi-agent automation capabilities, enhanced with a hierarchical task network (HTN) planning system. The goal is to make complex conversational AI scripting accessible to writers and content creators while maintaining sophisticated capabilities for advanced use cases.

## Key Design Principles
1. Clarity over cleverness 
2. Fail gracefully and visibly
3. Make common patterns easy, make complex patterns possible
4. Maintain the screenwriting metaphor throughout
5. Keep the learning curve gentle for non-programmers
6. Ensure proper separation of concerns
7. Enable reusability and modularity

## Primary Components

### 1. Characters (Agents)
Characters represent AI agents with defined personalities, expertise areas, behavioral traits, and capabilities.

```ruby
character TechnicalGuide do
  archetype "Friendly Expert"
  voice "casual and encouraging"
  expertise ["getting started", "troubleshooting"]
  background "Former developer who loves teaching"
  memory_model "pod-based"
  tools ["documentation_search", "code_analysis"]
end
```

### 2. Scenes (Interactive Dialog)
Scenes handle all direct user interactions and must include at least one character.

```ruby
scene InitialContact do
  cast TechnicalGuide
  
  TechnicalGuide speaks "Welcome! How can I help?"
  
  choice "Show me the basics" do
    transition_to BasicTutorial
  end
  
  choice "I have a question" do
    transition_to SpecificHelp
  end

  on_timeout do
    transition_to Engagement
  end
end
```

### 3. Flows (Autonomous Processing)
Flows manage autonomous agent interactions and background processes using HTN planning.

```ruby
flow AnalyzeIssue do
  input :description
  
  task "Initial Analysis" do
    AIAnalyst examines description
    severity = AIAnalyst.assess_severity
  end
  
  when needs_more_info do
    return_to_scene ClarifyDetails
  end

  when severity > threshold do
    escalate_to ExpertAnalysis
  end
end
```

### 4. Tasks (HTN Components)
Tasks represent atomic units of work that can be composed into larger behaviors.

```ruby
primitive_task ResearchDocumentation do
  preconditions do
    has_query_terms?
    documentation_available?
  end
  
  effects do
    set :research_complete, true
    update :knowledge_base
  end

  operator :search_docs
end

compound_task ProvideAnswer do
  method research_and_respond do
    conditions do
      needs_research?
      documentation_available?
    end
    
    subtasks [
      ResearchDocumentation,
      FormulateResponse,
      DeliverResponse
    ]
  end

  method direct_response do
    conditions do
      knowledge_available?
    end
    
    subtasks [
      FormulateResponse,
      DeliverResponse
    ]
  end
end
```

### 5. Memory Systems
Hierarchical memory management system with multiple layers:

1. Short-term (Scene Context)
   - Current conversation state
   - Recent interactions
   - Temporary variables

2. Working Memory (Flow State)
   - Active goals and plans
   - Current task context
   - Intermediate results

3. Long-term (Character Memory)
   - Conversation history
   - Learned patterns
   - User preferences
   - Domain knowledge

4. Shared Memory (Pod-based)
   - Cross-character knowledge
   - Global state
   - System configurations

### 6. State Management
Comprehensive state tracking across different scopes:

1. Conversation State
   - Dialog history
   - User intent
   - Emotional context
   - Turn management

2. Character State
   - Current goals
   - Knowledge state
   - Behavioral state
   - Task progress

3. Scene State
   - Active participants
   - Available choices
   - Environmental context
   - Timeout status

4. Flow State
   - Task queue
   - Process status
   - Resource utilization
   - Error states

## Implementation Architecture

### 1. Core Systems

#### 1.1 Parser & Interpreter
- Lexer implementation
- Parser implementation
- AST definition
- Error handling
- Runtime evaluation

#### 1.2 Planning System
- HTN planner implementation
- Task decomposition
- Plan validation
- Execution monitoring
- Replanning triggers

#### 1.3 Memory Manager
- Pod-based storage
- Memory hierarchy
- State persistence
- Access control
- Garbage collection

### 2. Runtime Components

#### 2.1 Scene Manager
- Scene lifecycle
- State transitions
- Context management
- Error boundaries
- Event handling

#### 2.2 Flow Controller
- Task orchestration
- Resource management
- Error recovery
- State preservation
- Flow composition

#### 2.3 Character Engine
- Behavior execution
- Memory access
- Tool integration
- State updates
- Inter-character communication

## Development Roadmap

### Phase 1: Core Infrastructure (Weeks 1-8)
1. Basic parser and interpreter
2. HTN planning system
3. Memory management foundation
4. Scene manager prototype

### Phase 2: Runtime Systems (Weeks 9-16)
1. Flow controller implementation
2. Character engine development
3. State management system
4. Event handling framework

### Phase 3: Tools & Integration (Weeks 17-24)
1. Development environment
2. Debugging tools
3. Testing framework
4. Documentation system

### Phase 4: Advanced Features (Weeks 25-32)
1. Complex planning capabilities
2. Advanced memory systems
3. Multi-character coordination
4. Performance optimization

## Success Criteria
- All core features implemented and tested
- Documentation complete and reviewed
- Performance benchmarks met
- Security requirements satisfied
- Integration tests passing
- User acceptance testing completed
- Development tools functioning
- Deployment procedures verified

## Next Steps
1. Finalize state management architecture
2. Develop event handling framework
3. Create formal specification for scene-flow interactions
4. Design testing framework
5. Implement basic prototype focusing on core features

## Open Questions
1. How should we handle versioning of scenes and flows?
2. What is the right balance between declarative and imperative syntax?
3. How do we handle internationalization?
4. What is the best way to document complex conversational patterns?
5. How should we manage resource allocation for multiple concurrent conversations?