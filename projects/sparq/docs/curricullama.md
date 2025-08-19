# CURRICULAMA: Automatically Learning HTN Methods from Landmarks

## Overview and Motivation

This paper presents CURRICULAMA, an innovative algorithm that automates the learning of Hierarchical Task Network (HTN) planning methods by leveraging two key concepts: landmarks and curriculum learning. The work addresses a significant challenge in HTN planning - the need for human domain experts to manually specify decomposition methods.

## Key Problems Solved

Traditional HTN planning faces several challenges that CURRICULAMA addresses:

1. Manual Knowledge Engineering Burden: HTN planning typically requires domain experts to hand-craft decomposition methods, which is time-consuming and requires specialized expertise.

2. Partial Automation Limitations: While existing approaches like HTN-MAKER partially automate method learning, they still require human input for task annotation.

3. Curriculum Design: Previous approaches needed humans to design the learning curriculum - deciding what to learn first and how to build up complexity.

## Core Innovation

CURRICULAMA introduces a fully automated approach by combining:

1. Landmark Analysis
   - Landmarks are facts that must be true in any solution to a planning problem
   - They provide natural waypoints that help structure the learning process
   - The ordering between landmarks creates a backbone for learning decomposition methods

2. Curriculum Learning
   - Orders the learning process from simpler to more complex methods
   - Uses landmarks to automatically generate this curriculum
   - Builds new methods by incorporating previously learned simpler methods

## Key Technical Contributions

1. Automated Task Annotation
   - Eliminates HTN-MAKER's requirement for manual task annotation
   - Uses landmarks to automatically identify meaningful subgoals
   - Generates appropriate task decompositions based on landmark analysis

2. Sound Learning Framework
   - Proves that learned methods can solve equivalent hierarchical planning problems
   - Ensures completeness of the learned method set
   - Maintains solution quality comparable to manually engineered approaches

3. Efficient Implementation
   - Achieves similar convergence rates to HTN-MAKER
   - Requires minimal additional computational overhead
   - Successfully learns complete method sets across various domains

## Experimental Validation

The paper validates CURRICULAMA across multiple planning domains:
- Blocks World
- Logistics
- Rover
- Satellite
- Zeno Travel

Key findings show that CURRICULAMA:
- Achieves similar convergence rates to HTN-MAKER
- Produces plans of comparable quality
- Requires only marginal additional computation time (0.2-0.8 seconds per problem)
- Successfully eliminates the need for manual task annotation

## Significance

CURRICULAMA represents a significant step forward in automated planning by:
1. Eliminating the need for manual knowledge engineering in HTN planning
2. Demonstrating that landmark analysis can effectively guide structural knowledge learning
3. Showing how curriculum learning principles can be automated in planning domains
4. Providing a framework that could be extended to other structural knowledge learning techniques

The approach opens new possibilities for automated planning systems that can learn and improve their capabilities without human intervention, while maintaining the advantages of hierarchical planning approaches.

# CURRICULAMA: Technical Implementation Approach

## System Architecture

CURRICULAMA consists of two main components that work together to learn HTN methods:

1. CURRICUGEN: Generates curricula from landmarks
2. CURRICULEARN: Learns HTN methods using the generated curricula

## CURRICUGEN Implementation

### Input Processing
- Takes a classical planning problem P = (Σ, s₀, g)
- Σ: domain description
- s₀: initial state
- g: goal state

### Landmark Extraction Process
1. Generates landmark graph using hₘ Landmarks algorithm
   - Identifies facts that must be true in any solution
   - Creates nodes representing landmarks
   - Establishes ordering relationships between landmarks

2. Adds reasonable orders to the landmark graph
   - Natural ordering: landmark i must occur before landmark j
   - Necessary ordering: landmark i must occur immediately before j
   - Greedy-necessary: landmark i must occur before first occurrence of j
   - Reasonable ordering: landmark j must reoccur after first occurrence of i

### Curriculum Generation
1. Iterates through landmarks in order
2. For each landmark:
   - Uses classical planner to find solution from current state to landmark
   - Updates current state by applying solution
   - Creates annotated task with landmark as goal
   - Generates curriculum steps by tracing backward through plan

### Curriculum Step Structure
Each step contains:
- Beginning index (b)
- Ending index (e)
- Annotated task (τ)

## CURRICULEARN Implementation

### Method Learning Process
1. Takes input:
   - Domain description (Σ)
   - Initial state (s₀)
   - Execution trace (π)
   - Curriculum (C)
   - Current method set (M)

2. For each curriculum step:
   - Analyzes subtrace π[b,e]
   - Learns new methods for task τ
   - Maintains indexed method instances for reuse

### Method Learning Algorithm
1. Performs hierarchical goal regression over plan trace
2. Learns preconditions and subtasks of HTN methods
3. Indexes learned methods by:
   - Beginning index of subtrace
   - Ending index of subtrace

## Integration Mechanism

### Method Synthesis
1. Combines previously learned methods as subtasks
2. Ensures proper ordering of subtasks
3. Maintains completeness of method set

### Soundness Guarantees
1. Ensures learned methods can solve equivalent hierarchical problems
2. Maintains proper decomposition hierarchy
3. Preserves solution quality

## Implementation Considerations

### Performance Optimizations
1. Efficient landmark graph generation
2. Optimized curriculum step generation
3. Method indexing for quick retrieval

### Robustness Features
1. Handles partial orders in landmark graphs
2. Manages redundant methods
3. Deals with suboptimal landmark orderings

### Scaling Considerations
1. Manages method set growth
2. Handles increasing problem complexity
3. Maintains performance with larger domains

## Testing and Validation

### Verification Process
1. Confirms method soundness
2. Validates decomposition correctness
3. Ensures solution completeness

### Performance Metrics
1. Convergence rate measurement
2. Plan quality assessment
3. Computational overhead tracking

## Future Enhancement Areas

### Potential Improvements
1. More sophisticated landmark ordering strategies
2. Enhanced method generalization
3. Improved curriculum optimization

### Extensibility Points
1. Integration with other learning approaches
2. Application to different planning paradigms
3. Enhancement of landmark analysis