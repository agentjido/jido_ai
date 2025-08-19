# HTN Plan Repair via Model Transformation: Summary and Overview

## Core Problem
Hierarchical Task Network (HTN) planning systems face a critical challenge when plans fail during execution. While classical planning systems can simply restart planning from the current state (re-planning), this approach doesn't work well for HTN planning because the hierarchical nature of HTN plans enforces important constraints that must be preserved even after failures.

## Key Concepts

### HTN Planning Fundamentals
HTN planning involves two types of tasks:
1. Primitive tasks - equivalent to classical planning actions that cause state transitions
2. Abstract tasks - higher-level tasks that are decomposed into subtasks through methods

The hierarchical structure in HTN planning is more than just a performance optimization - it enforces crucial constraints on valid solutions. For example, certain actions might only be allowed in specific combinations or sequences.

### The Plan Repair Problem
When a plan fails during execution, the system encounters:
- A partially executed plan prefix
- An unexpected state that differs from what was predicted
- The need to generate a new valid plan that:
  - Starts with the already executed actions
  - Accounts for the unexpected state changes
  - Maintains hierarchical constraints from the original problem

### Why Simple Re-Planning Fails
The paper uses an excellent example of a toll road system to illustrate why simple re-planning is insufficient:
- A car must pay a toll for each segment driven in a toll area
- The hierarchy ensures that each toll segment is matched with a payment
- If re-planning ignores the already executed segments, it might generate a plan with incorrect number of toll payments

## Novel Contribution
The paper's key innovation is a transformation-based approach that:
1. Converts the plan repair problem into a standard HTN planning problem
2. Allows the use of existing HTN planners without modification
3. Guarantees that solutions will maintain hierarchical constraints

## Theoretical Properties
The transformation preserves important theoretical properties:
- Maintains the problem class (totally ordered, tail-recursive, or acyclic HTN)
- Results in at most quadratic size increase relative to input
- Preserves the formal semantics of the original problem

## Significance
This approach offers several advantages:
1. Eliminates need for specialized repair algorithms
2. Leverages existing HTN planner optimizations
3. Provides a clean theoretical framework for plan repair
4. Makes plan repair more accessible to practical applications

The work bridges an important gap between theoretical HTN planning and practical robotic or workflow systems that need to handle execution failures gracefully.

# HTN Plan Repair Implementation Approach

## Core Transformation Strategy

### Input Components
1. Original HTN Planning Problem P = (L, C, A, M, s₀, tnᵢ, g, δ)
   - L: state features
   - C: compound (abstract) tasks
   - A: primitive actions
   - M: decomposition methods
   - s₀: initial state
   - tnᵢ: initial task network
   - g: goal state
   - δ: state transition function

2. Execution Information
   - Failed solution plan
   - Decomposition tree showing how solution was derived
   - Sequence of executed actions
   - Unexpected state changes (F⁺, F⁻)

### Transformation Steps

#### 1. State Tracking Setup
```
For each position i in the executed prefix:
- Create new state feature lᵢ
- Add l₀ to initial state
- Add lₘ to goal state (m = length of prefix)
```

#### 2. Action Transformation
```
For each action aᵢ in executed prefix:
- Create new action a'ᵢ with:
  preconditions = prec(aᵢ) ∪ {lᵢ₋₁}
  add effects = add(aᵢ) ∪ {lᵢ}
  delete effects = del(aᵢ) ∪ {lᵢ₋₁}

For last action in prefix:
- Add unexpected state changes (F⁺, F⁻) to effects

For all original actions a:
- Add lₘ to preconditions
```

#### 3. Hierarchy Adaptation
```
For each action a in domain:
- Create new abstract task c'ₐ
- Create method to decompose c'ₐ into a
- If a appears in prefix:
  - Create method to decompose c'ₐ into corresponding a'

For each method m in original domain:
- Replace primitive tasks with corresponding abstract tasks
```

## Implementation Considerations

### Data Structures
1. Position Tracking
```
struct StatePosition {
    int position;
    string state_feature;
    set<string> active_conditions;
}
```

2. Action Mapping
```
struct ActionMapping {
    string original_action;
    string transformed_action;
    set<string> prefix_positions;
}
```

3. Method Translation
```
struct MethodTranslation {
    TaskNetwork original_network;
    TaskNetwork transformed_network;
    map<string, string> task_mappings;
}
```

### Key Algorithms

#### 1. Prefix Encoding
```pseudocode
function encodePrefixSequence(prefix, domain):
    positions = createPositionFeatures(prefix.length)
    new_actions = []
    
    for i, action in enumerate(prefix):
        new_action = transformAction(action, positions[i], positions[i+1])
        if i == prefix.length - 1:
            addUnexpectedEffects(new_action)
        new_actions.append(new_action)
    
    return new_actions
```

#### 2. Method Transformation
```pseudocode
function transformMethods(domain, action_mappings):
    new_methods = []
    
    for method in domain.methods:
        new_method = copyMethod(method)
        for task in new_method.subtasks:
            if isPrimitive(task):
                replaceWithAbstract(task, action_mappings)
        new_methods.append(new_method)
    
    return new_methods
```

#### 3. Solution Validation
```pseudocode
function validateSolution(solution, prefix):
    # Verify prefix appears at start
    if not startsWith(solution, prefix):
        return false
        
    # Verify hierarchical constraints
    if not validateHierarchy(solution):
        return false
        
    # Verify state progression
    if not validateStates(solution):
        return false
        
    return true
```

## Testing Strategy

1. Correctness Testing
   - Verify prefix preservation
   - Validate hierarchical constraints
   - Check state progression
   - Test unexpected state handling

2. Performance Testing
   - Measure transformation overhead
   - Compare with direct replanning
   - Evaluate scaling with prefix length
   - Test domain size impact

3. Edge Cases
   - Empty prefix
   - Full plan execution
   - Multiple failures
   - Cyclic hierarchies
   - Complex state changes

## Integration Guidelines

1. Planner Integration
   - Input format conversion
   - Solution translation
   - Error handling
   - Performance monitoring

2. Execution System Integration
   - State monitoring
   - Failure detection
   - Plan validation
   - Recovery coordination

3. Domain Engineering
   - Method design patterns
   - Hierarchy guidelines
   - State representation
   - Error modeling