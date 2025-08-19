# Sparq Flow and HTN Planning Specification

## Overview

Flows in Sparq represent autonomous task networks that guide character behavior. They combine pattern matching and hierarchical task planning to create flexible, goal-oriented behaviors.

## Basic Flow Structure

```sparq
flow HandleUserQuestion do
  @character TechnicalGuide
  @goal "Answer the user's question effectively"
  
  step :evaluate_question do
    when question_type() == :basic and is_new_user?() do
      provide_simple_explanation()
    end
    
    when question_type() == :technical or has_error_message?() do
      perform_technical_analysis()
    end
    
    # Default approach if no guards match
    research_and_respond()
  end
end
```

## Required Attributes

- `@character`: The character executing this flow
- `@goal`: The primary objective of this flow

## Optional Attributes

- `@priority`: Execution priority (`:high`, `:normal`, `:low`)
- `@timeout`: Maximum execution time
- `@retry`: Retry configuration for failed steps

## Step Definition

Steps are the building blocks of flows:

```sparq
step :step_name do
  # Guard clauses determine which approach to use
  when condition_1() do
    action_1()
  end
  
  when condition_2() do
    action_2()
  end
  
  # Default action if no guards match
  default_action()
end
```

## Guard Rules

1. Evaluation Order
   - Guards are evaluated in order of definition
   - First matching guard is executed
   - Default action runs if no guards match

2. Guard Conditions
   - Can use any predicate function
   - Can combine multiple conditions with `and`/`or`
   - Can access character state and context
   - Must return boolean values

## Example Flow

Here's a more detailed flow example:

```sparq
flow DocumentSearch do
  @character Researcher
  @goal "Find relevant documentation"
  @priority :normal
  @timeout :timer.seconds(30)
  @retry %{max_attempts: 3, delay: :timer.seconds(1)}
  
  step :analyze_query do
    when is_specific_reference?(query) do
      fetch_exact_document()
    end
    
    when contains_keywords?(query) do
      perform_keyword_search()
    end
    
    # Default to semantic search
    semantic_search()
  end
  
  step :filter_results do
    when user_is_beginner?() do
      simplify_results()
    end
    
    when user_is_expert?() do
      include_technical_details()
    end
    
    # Default filtering
    standard_filter()
  end
  
  step :present_results do
    format_and_display()
  end
end
```

## HTN Planning Integration

The flow system automatically maps to an HTN planner:

1. Each `step` becomes a Compound Task
   - Contains one or more Methods
   - Represents a goal to achieve
   - Can decompose into subtasks

2. Each `when` block becomes a Method
   - Guard conditions become Method preconditions
   - The actions inside become Primitive Tasks
   - The order of Methods matters - first matching Method is used

3. Each action becomes a Primitive Task
   - Must be something the character knows how to do
   - Maps to concrete actions in the system
   - Has clear success/failure conditions

## Best Practices

1. Flow Design
   - Keep flows focused on a single goal
   - Break complex tasks into clear steps
   - Provide sensible defaults
   - Handle common failure cases

2. Guard Usage
   - Order guards from specific to general
   - Keep conditions clear and testable
   - Avoid complex nested conditions
   - Always provide a default action

3. Error Handling
   - Use retry configuration for flaky operations
   - Set appropriate timeouts
   - Provide graceful degradation paths
   - Log meaningful error information