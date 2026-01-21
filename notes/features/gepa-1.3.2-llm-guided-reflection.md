# GEPA Task 1.3.2: LLM-Guided Reflection - Feature Planning

## Overview

This document provides comprehensive planning for implementing GEPA Task 1.3.2: LLM-Guided Reflection, the core innovation of the GEPA optimization system. This task implements the mechanism where an LLM analyzes execution trajectories and generates targeted improvement suggestions, transforming opaque failures into actionable prompt modifications.

## Status

- **Phase**: 5 (GEPA Optimization)
- **Stage**: 1 (Foundation)
- **Section**: 1.3 (Reflection & Feedback Generation)
- **Task**: 1.3.2 (LLM-Guided Reflection)
- **Status**: Planning
- **Branch**: TBD (suggest: `feature/gepa-1.3.2-llm-reflection`)

## Prerequisites Completed

### Section 1.1: GEPA Optimizer Agent Infrastructure ✅
- Optimizer foundation with GenServer
- Population management
- Task distribution and scheduling
- Evolution cycle coordination
- 40+ passing tests

### Section 1.2: Prompt Evaluation System ✅
- Evaluation agent spawning (Evaluator module)
- Trajectory collection (Trajectory module with 58 passing tests)
- Metrics aggregation (Metrics module)
- Result synchronization (ResultCollector module)

### Section 1.3.1: Trajectory Analysis ✅
- TrajectoryAnalyzer module with comprehensive analysis capabilities
- Failure point identification
- Reasoning step analysis (contradiction, circular reasoning, incomplete logic detection)
- Success pattern extraction
- Comparative analysis between trajectories
- 40 passing tests
- Natural language summarization of analyses

## Context & Motivation

### GEPA's Core Innovation

Traditional prompt optimization uses opaque gradient signals or random mutations. GEPA's key innovation is **using the LLM itself as a reflective coach** that understands failures semantically and suggests specific improvements. This transforms the optimization from blind search into guided exploration.

**Key Insight**: The same LLM that struggles with a prompt can often analyze *why* it struggled and suggest *how* to improve the prompt. This meta-cognitive capability is GEPA's foundation.

### The Reflection Process

```
1. Execute prompt → Capture trajectory (failures, reasoning, outcomes)
2. Analyze trajectory → Extract failure patterns (TrajectoryAnalyzer - DONE)
3. Reflect via LLM → Generate natural language analysis (THIS TASK)
4. Parse suggestions → Extract actionable modifications (THIS TASK)
5. Apply mutations → Create improved prompt variants (Task 1.4.x)
```

### Why Multi-Turn Reflection?

Initial reflection may produce generic suggestions. Multi-turn reflection enables:
- **Clarification**: "What specifically failed in step 3?"
- **Deep Analysis**: "Why did the contradiction occur?"
- **Alternative Strategies**: "What other approaches could work?"
- **Iterative Refinement**: "That suggestion didn't work. What else?"

## Architecture Overview

### Module Structure

```
lib/jido/runner/gepa/reflector.ex       # Main reflection orchestration
lib/jido/runner/gepa/reflection/
  ├── prompt_builder.ex                  # Builds reflection prompts
  ├── suggestion_parser.ex               # Parses LLM responses
  └── conversation_manager.ex            # Manages multi-turn dialogue

test/jido/runner/gepa/reflector_test.exs
test/jido/runner/gepa/reflection/
  ├── prompt_builder_test.exs
  ├── suggestion_parser_test.exs
  └── conversation_manager_test.exs
```

### Data Flow

```
TrajectoryAnalysis
    ↓
ReflectionRequest (create request with analysis)
    ↓
PromptBuilder (format analysis into LLM prompt)
    ↓
Jido.AI.Agent (execute LLM call with structured output)
    ↓
ReflectionResponse (raw LLM response)
    ↓
SuggestionParser (extract structured suggestions)
    ↓
ParsedReflection (actionable insights)
    ↓
[Multi-turn: follow-up questions → iterate]
```

## Task Breakdown

### Task 1.3.2.1: Reflection Prompt Creation

**Goal**: Design prompts that present trajectory analysis and request specific improvements.

#### Prompt Requirements

1. **Context Section**: Present the failed trajectory
   - Original prompt that was being evaluated
   - Task description and expected outcome
   - Actual outcome (failure, partial success, error)
   - Key metrics (duration, step count, quality score)

2. **Analysis Section**: Present TrajectoryAnalyzer findings
   - Failure points with severity and descriptions
   - Reasoning issues detected (contradictions, incomplete logic)
   - Success indicators (if any) to preserve
   - Comparative analysis (if available)

3. **Request Section**: Ask for specific improvements
   - What went wrong and why?
   - What should be changed in the prompt?
   - What should be added to prevent this failure?
   - What should be removed if causing issues?

4. **Constraints Section**: Guide the response format
   - Provide suggestions in structured format
   - Categorize suggestions (clarity, constraints, examples, structure)
   - Prioritize suggestions by expected impact
   - Be specific and actionable

#### Prompt Template Structure

```elixir
defmodule Jido.Runner.GEPA.Reflection.PromptBuilder do
  @system_prompt """
  You are an expert prompt engineer analyzing failed LLM executions.
  Your goal is to identify why a prompt failed and suggest specific improvements.

  Provide responses in JSON format with this structure:
  {
    "analysis": "Brief analysis of what went wrong",
    "root_causes": ["cause1", "cause2"],
    "suggestions": [
      {
        "type": "add|modify|remove|restructure",
        "category": "clarity|constraint|example|structure",
        "description": "What to change",
        "rationale": "Why this will help",
        "priority": "high|medium|low",
        "specific_text": "Exact text to add/modify (if applicable)"
      }
    ],
    "expected_improvement": "What should improve if these changes are made"
  }
  """

  def build_reflection_prompt(trajectory_analysis, opts \\ []) do
    # Format the request
    """
    # Failed Prompt Execution Analysis

    ## Original Prompt
    #{format_original_prompt(trajectory_analysis)}

    ## Task Context
    #{format_task_context(trajectory_analysis)}

    ## Execution Outcome
    #{format_outcome(trajectory_analysis)}

    ## Failure Analysis
    #{format_failure_points(trajectory_analysis.failure_points)}

    ## Reasoning Issues Detected
    #{format_reasoning_issues(trajectory_analysis.reasoning_issues)}

    ## Trajectory Summary
    #{TrajectoryAnalyzer.summarize(trajectory_analysis, verbosity: :normal)}

    ## Your Task
    Analyze this failed execution and provide specific, actionable suggestions
    to improve the prompt. Focus on addressing the root causes while preserving
    any successful patterns.

    Respond with JSON matching the specified structure.
    """
  end
end
```

#### Implementation Checklist

- [ ] Create `Jido.Runner.GEPA.Reflection.PromptBuilder` module
- [ ] Implement `build_reflection_prompt/2` main function
- [ ] Add formatting functions for each section
  - [ ] `format_original_prompt/1`
  - [ ] `format_task_context/1`
  - [ ] `format_outcome/1`
  - [ ] `format_failure_points/1`
  - [ ] `format_reasoning_issues/1`
  - [ ] `format_comparative_analysis/1` (if available)
- [ ] Support verbosity levels (brief, normal, detailed)
- [ ] Add system prompt configuration options
- [ ] Handle missing/incomplete analysis data gracefully
- [ ] Unit tests for prompt generation (10+ tests)

### Task 1.3.2.2: LLM Call with Structured Output

**Goal**: Execute LLM calls requesting structured JSON responses with improvement suggestions.

#### LLM Integration Strategy

Use Jido.AI.Agent with JSON response format:

```elixir
defmodule Jido.Runner.GEPA.Reflector do
  alias Jido.AI.Agent
  alias Jido.Agent.Server

  def reflect_on_failure(trajectory_analysis, opts \\ []) do
    # Build reflection prompt
    prompt = PromptBuilder.build_reflection_prompt(trajectory_analysis, opts)

    # Configure agent for structured output
    agent_opts = [
      agent: Agent,
      skills: [Jido.AI.Skill],
      ai: [
        model: get_reflection_model(opts),
        prompt: prompt,
        system: PromptBuilder.system_prompt(),
        response_format: :json,
        temperature: 0.3,  # Lower temperature for more focused analysis
        max_tokens: 2000
      ]
    ]

    # Spawn reflection agent
    with {:ok, agent_pid} <- Server.start_link(agent_opts),
         {:ok, signal} <- build_reflection_signal(trajectory_analysis),
         {:ok, response} <- Server.call(agent_pid, signal, opts[:timeout] || 30_000),
         :ok <- cleanup_agent(agent_pid) do

      # Parse the structured response
      parse_reflection_response(response, trajectory_analysis)
    else
      {:error, reason} -> {:error, {:reflection_failed, reason}}
    end
  end

  defp get_reflection_model(opts) do
    # Use high-quality model for reflection (GPT-4, Claude 3.5 Sonnet)
    Keyword.get(opts, :model, {:openai, model: "gpt-4"})
  end
end
```

#### JSON Response Schema

```json
{
  "analysis": "The prompt lacks clear step-by-step instructions, causing the model to skip critical reasoning steps and jump to conclusions.",

  "root_causes": [
    "No explicit instruction to 'think step by step'",
    "Missing constraint about showing intermediate work",
    "Unclear what constitutes a complete answer"
  ],

  "suggestions": [
    {
      "type": "add",
      "category": "structure",
      "description": "Add explicit chain-of-thought trigger",
      "rationale": "Forces the model to break down reasoning into steps, preventing premature conclusions",
      "priority": "high",
      "specific_text": "Let's approach this step by step:\n1. First, identify...\n2. Then, analyze...\n3. Finally, conclude..."
    },
    {
      "type": "add",
      "category": "constraint",
      "description": "Add requirement to show intermediate work",
      "rationale": "Makes reasoning visible and checkable, reducing logical errors",
      "priority": "high",
      "specific_text": "Show all intermediate calculations and reasoning."
    },
    {
      "type": "modify",
      "category": "clarity",
      "description": "Clarify what a complete answer requires",
      "rationale": "Prevents incomplete responses",
      "priority": "medium",
      "specific_text": "A complete answer must include: [1] your reasoning process, [2] the final answer, [3] confidence level."
    }
  ],

  "expected_improvement": "With these changes, the model should break down problems systematically, show its work, and provide complete answers. This should reduce logic errors and incomplete responses by approximately 60-80%."
}
```

#### Implementation Checklist

- [ ] Implement `Reflector.reflect_on_failure/2` main function
- [ ] Add agent spawning for reflection
- [ ] Configure structured JSON output
- [ ] Handle LLM call errors and retries
- [ ] Add timeout handling (with configurable timeout)
- [ ] Support multiple LLM providers (OpenAI, Anthropic, local)
- [ ] Add response validation (JSON schema check)
- [ ] Implement agent cleanup after reflection
- [ ] Add logging for reflection requests and responses
- [ ] Unit tests with mocked LLM responses (15+ tests)

### Task 1.3.2.3: Reflection Parsing

**Goal**: Extract actionable insights from LLM reflection responses into structured data.

#### Data Structures

```elixir
defmodule Jido.Runner.GEPA.Reflection do
  use TypedStruct

  @type suggestion_type :: :add | :modify | :remove | :restructure
  @type suggestion_category :: :clarity | :constraint | :example | :structure | :other
  @type priority :: :low | :medium | :high | :critical

  typedstruct module: Suggestion do
    @moduledoc """
    A specific, actionable suggestion for improving a prompt.
    """

    field(:type, suggestion_type(), enforce: true)
    field(:category, suggestion_category(), enforce: true)
    field(:description, String.t(), enforce: true)
    field(:rationale, String.t(), enforce: true)
    field(:priority, priority(), default: :medium)
    field(:specific_text, String.t() | nil)
    field(:metadata, map(), default: %{})
  end

  typedstruct module: ParsedReflection do
    @moduledoc """
    Complete parsed reflection analysis with suggestions.
    """

    field(:trajectory_id, String.t(), enforce: true)
    field(:analysis, String.t(), enforce: true)
    field(:root_causes, list(String.t()), default: [])
    field(:suggestions, list(Suggestion.t()), default: [])
    field(:expected_improvement, String.t())
    field(:confidence, float(), default: 0.5)
    field(:reflection_time_ms, non_neg_integer())
    field(:model_used, String.t())
    field(:metadata, map(), default: %{})
  end

  typedstruct module: ReflectionRequest do
    @moduledoc """
    Request for LLM reflection on a trajectory analysis.
    """

    field(:trajectory_analysis, TrajectoryAnalyzer.TrajectoryAnalysis.t(), enforce: true)
    field(:context, map(), default: %{})
    field(:options, keyword(), default: [])
  end

  typedstruct module: ReflectionResponse do
    @moduledoc """
    Raw response from LLM reflection call.
    """

    field(:raw_response, String.t(), enforce: true)
    field(:parsed_json, map() | nil)
    field(:signal, Jido.Signal.t(), enforce: true)
    field(:duration_ms, non_neg_integer())
  end
end
```

#### Parsing Implementation

```elixir
defmodule Jido.Runner.GEPA.Reflection.SuggestionParser do
  alias Jido.Runner.GEPA.Reflection.{Suggestion, ParsedReflection}

  def parse_reflection_response(response, trajectory_analysis) do
    start_time = System.monotonic_time(:millisecond)

    with {:ok, json} <- extract_json(response),
         {:ok, validated} <- validate_schema(json),
         {:ok, suggestions} <- parse_suggestions(validated["suggestions"]),
         {:ok, reflection} <- build_parsed_reflection(validated, suggestions, trajectory_analysis) do

      duration = System.monotonic_time(:millisecond) - start_time
      {:ok, %{reflection | reflection_time_ms: duration}}
    else
      {:error, reason} -> {:error, {:parsing_failed, reason}}
    end
  end

  defp extract_json(response) do
    # Handle various response formats
    content = extract_content_from_signal(response)

    # Try to parse as JSON
    case Jason.decode(content) do
      {:ok, json} -> {:ok, json}
      {:error, _} ->
        # Try to extract JSON from markdown code blocks
        case extract_json_from_markdown(content) do
          {:ok, json} -> {:ok, json}
          {:error, _} -> {:error, :invalid_json}
        end
    end
  end

  defp validate_schema(json) do
    # Validate required fields
    required = ["analysis", "suggestions"]

    if Enum.all?(required, &Map.has_key?(json, &1)) do
      {:ok, json}
    else
      {:error, :missing_required_fields}
    end
  end

  defp parse_suggestions(suggestions_json) when is_list(suggestions_json) do
    suggestions =
      suggestions_json
      |> Enum.map(&parse_single_suggestion/1)
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.map(fn {:ok, s} -> s end)

    {:ok, suggestions}
  end

  defp parse_single_suggestion(suggestion_json) do
    # Parse and validate each suggestion
    %Suggestion{
      type: parse_suggestion_type(suggestion_json["type"]),
      category: parse_suggestion_category(suggestion_json["category"]),
      description: suggestion_json["description"] || "",
      rationale: suggestion_json["rationale"] || "",
      priority: parse_priority(suggestion_json["priority"]),
      specific_text: suggestion_json["specific_text"],
      metadata: suggestion_json["metadata"] || %{}
    }
    |> validate_suggestion()
  end

  defp build_parsed_reflection(json, suggestions, trajectory_analysis) do
    %ParsedReflection{
      trajectory_id: trajectory_analysis.trajectory_id,
      analysis: json["analysis"] || "",
      root_causes: json["root_causes"] || [],
      suggestions: suggestions,
      expected_improvement: json["expected_improvement"],
      confidence: calculate_confidence(json, suggestions),
      model_used: extract_model_from_metadata(json),
      metadata: %{
        suggestion_count: length(suggestions),
        high_priority_count: count_high_priority(suggestions),
        categories: extract_categories(suggestions)
      }
    }
    |> Ok.wrap()
  end

  defp calculate_confidence(json, suggestions) do
    # Calculate confidence based on:
    # - Number and quality of suggestions
    # - Specificity of suggestions (presence of specific_text)
    # - Coherence of root cause analysis
    base = 0.5

    # More suggestions = higher confidence (up to a point)
    suggestion_bonus = min(length(suggestions) * 0.1, 0.3)

    # Specific text provided = higher confidence
    specific_bonus =
      suggestions
      |> Enum.count(&(&1.specific_text != nil))
      |> Kernel./(max(length(suggestions), 1))
      |> Kernel.*(0.2)

    (base + suggestion_bonus + specific_bonus)
    |> max(0.0)
    |> min(1.0)
  end
end
```

#### Implementation Checklist

- [ ] Create `Reflection.SuggestionParser` module
- [ ] Implement JSON extraction from various formats
  - [ ] Raw JSON
  - [ ] Markdown code blocks
  - [ ] Mixed text/JSON responses
- [ ] Add JSON schema validation
- [ ] Implement suggestion parsing
  - [ ] Type parsing and validation
  - [ ] Category parsing and validation
  - [ ] Priority parsing and validation
- [ ] Build complete ParsedReflection struct
- [ ] Add confidence calculation
- [ ] Handle malformed responses gracefully
- [ ] Add detailed error reporting
- [ ] Unit tests for parsing (20+ tests)
  - [ ] Valid JSON responses
  - [ ] Malformed JSON
  - [ ] Missing fields
  - [ ] Invalid types/categories
  - [ ] Edge cases

### Task 1.3.2.4: Multi-Turn Reflection

**Goal**: Support follow-up questions for deeper understanding of failures.

#### Multi-Turn Conversation Flow

```
Turn 1: Initial reflection
  ↓
Parse suggestions
  ↓
Evaluate if clarification needed:
  - Generic suggestions? → Ask for specifics
  - Unclear root cause? → Ask for deeper analysis
  - Multiple failures? → Ask which to prioritize
  ↓
Turn 2: Clarification request
  ↓
Parse refined suggestions
  ↓
Continue until satisfied or max turns reached
```

#### Conversation Manager

```elixir
defmodule Jido.Runner.GEPA.Reflection.ConversationManager do
  alias Jido.Runner.GEPA.Reflection.{ParsedReflection, Suggestion}

  @max_turns 3
  @clarification_threshold 0.6

  defstruct [
    :trajectory_analysis,
    :turns,
    :current_turn,
    :agent_pid,
    :conversation_history,
    :max_turns
  ]

  def start_conversation(trajectory_analysis, opts \\ []) do
    %__MODULE__{
      trajectory_analysis: trajectory_analysis,
      turns: [],
      current_turn: 0,
      conversation_history: [],
      max_turns: Keyword.get(opts, :max_turns, @max_turns)
    }
  end

  def conduct_reflection(conversation, opts \\ []) do
    # Spawn persistent agent for multi-turn conversation
    with {:ok, agent_pid} <- spawn_reflection_agent(opts),
         {:ok, final_conversation} <- reflection_loop(conversation, agent_pid, opts),
         :ok <- cleanup_agent(agent_pid) do

      # Return best reflection from all turns
      {:ok, select_best_reflection(final_conversation)}
    end
  end

  defp reflection_loop(conversation, agent_pid, opts) do
    if conversation.current_turn >= conversation.max_turns do
      {:ok, conversation}
    else
      # Execute reflection turn
      with {:ok, reflection} <- execute_turn(conversation, agent_pid, opts),
           updated_conversation <- add_turn(conversation, reflection) do

        # Decide if we need another turn
        if needs_clarification?(reflection) do
          # Generate follow-up question
          follow_up = generate_follow_up(reflection, conversation)
          reflection_loop(updated_conversation, agent_pid,
            Keyword.put(opts, :follow_up, follow_up))
        else
          {:ok, updated_conversation}
        end
      end
    end
  end

  defp needs_clarification?(reflection) do
    # Clarification needed if:
    # - Confidence below threshold
    # - Suggestions too generic (no specific_text)
    # - Root causes unclear
    cond do
      reflection.confidence < @clarification_threshold -> true

      generic_suggestions?(reflection.suggestions) -> true

      vague_root_causes?(reflection.root_causes) -> true

      true -> false
    end
  end

  defp generate_follow_up(reflection, conversation) do
    cond do
      # Generic suggestions → Ask for specifics
      generic_suggestions?(reflection.suggestions) ->
        """
        Your suggestions are helpful but somewhat general. Can you provide more
        specific guidance? For each suggestion, please include:
        1. The exact text to add or modify in the prompt
        2. Where in the prompt this change should be made
        3. An example of before/after
        """

      # Unclear root causes → Deep dive
      vague_root_causes?(reflection.root_causes) ->
        """
        Can you dive deeper into the root causes? Specifically:
        1. Which failure was most critical?
        2. What chain of events led to this failure?
        3. What underlying assumption in the prompt caused this?
        """

      # Multiple failure types → Prioritize
      multiple_failure_types?(reflection) ->
        """
        There are multiple types of failures. Can you prioritize which to address first?
        Which change would have the highest impact on success rate?
        """

      # Default: Ask for alternatives
      true ->
        """
        Are there alternative approaches to solving this failure?
        What other strategies could improve the prompt?
        """
    end
  end

  defp select_best_reflection(conversation) do
    # Select the turn with highest confidence and most specific suggestions
    conversation.turns
    |> Enum.max_by(&score_reflection/1)
  end

  defp score_reflection(reflection) do
    confidence_score = reflection.confidence * 0.4

    specificity_score =
      reflection.suggestions
      |> Enum.count(&(&1.specific_text != nil))
      |> Kernel./(max(length(reflection.suggestions), 1))
      |> Kernel.*(0.3)

    priority_score =
      reflection.suggestions
      |> Enum.count(&(&1.priority == :high))
      |> Kernel./(max(length(reflection.suggestions), 1))
      |> Kernel.*(0.3)

    confidence_score + specificity_score + priority_score
  end
end
```

#### Implementation Checklist

- [ ] Create `Reflection.ConversationManager` module
- [ ] Implement conversation state management
- [ ] Add multi-turn reflection loop
- [ ] Implement clarification detection
  - [ ] Confidence threshold check
  - [ ] Generic suggestion detection
  - [ ] Vague root cause detection
- [ ] Add follow-up question generation
  - [ ] Template for requesting specifics
  - [ ] Template for deeper analysis
  - [ ] Template for prioritization
  - [ ] Template for alternatives
- [ ] Implement reflection scoring
- [ ] Add conversation history tracking
- [ ] Support configurable max turns
- [ ] Handle agent lifecycle for persistent conversation
- [ ] Unit tests for multi-turn logic (15+ tests)

## Data Structures Summary

```elixir
# Request
ReflectionRequest
  trajectory_analysis: TrajectoryAnalysis.t()
  context: map()
  options: keyword()

# Response (raw)
ReflectionResponse
  raw_response: String.t()
  parsed_json: map() | nil
  signal: Signal.t()
  duration_ms: integer()

# Parsed (structured)
Suggestion
  type: :add | :modify | :remove | :restructure
  category: :clarity | :constraint | :example | :structure | :other
  description: String.t()
  rationale: String.t()
  priority: :low | :medium | :high | :critical
  specific_text: String.t() | nil
  metadata: map()

ParsedReflection
  trajectory_id: String.t()
  analysis: String.t()
  root_causes: [String.t()]
  suggestions: [Suggestion.t()]
  expected_improvement: String.t()
  confidence: float()
  reflection_time_ms: integer()
  model_used: String.t()
  metadata: map()
```

## Integration Points

### Input: TrajectoryAnalyzer (Section 1.3.1) ✅

```elixir
# TrajectoryAnalyzer provides structured analysis
analysis = TrajectoryAnalyzer.analyze(trajectory,
  include_reasoning_analysis: true,
  include_success_patterns: true
)

# Analysis contains:
# - failure_points: [FailurePoint.t()]
# - reasoning_issues: [ReasoningIssue.t()]
# - success_indicators: [SuccessIndicator.t()]
# - overall_quality: :poor | :fair | :good | :excellent

# Feed to Reflector
{:ok, reflection} = Reflector.reflect_on_failure(analysis)
```

### Output: Mutation Operators (Section 1.4 - Future)

```elixir
# ParsedReflection provides structured suggestions for mutation
reflection.suggestions
|> Enum.filter(&(&1.priority in [:high, :critical]))
|> Enum.each(fn suggestion ->
  case suggestion.type do
    :add -> MutationOperators.addition_mutation(prompt, suggestion)
    :modify -> MutationOperators.edit_mutation(prompt, suggestion)
    :remove -> MutationOperators.deletion_mutation(prompt, suggestion)
    :restructure -> MutationOperators.restructure_mutation(prompt, suggestion)
  end
end)
```

### Integration with Jido.AI.Agent

```elixir
# Reflector uses Jido.AI.Agent for LLM calls
alias Jido.AI.Agent
alias Jido.Agent.Server

# Agent configuration
agent_opts = [
  agent: Agent,
  skills: [Jido.AI.Skill],
  ai: [
    model: {:openai, model: "gpt-4"},
    prompt: reflection_prompt,
    system: system_prompt,
    response_format: :json,
    temperature: 0.3,
    max_tokens: 2000
  ]
]

# Start agent, execute reflection, cleanup
{:ok, agent_pid} = Server.start_link(agent_opts)
{:ok, response} = Server.call(agent_pid, signal, timeout)
:ok = GenServer.stop(agent_pid)
```

## Testing Strategy

### Unit Tests

#### PromptBuilder Tests (10+ tests)
```elixir
defmodule Jido.Runner.GEPA.Reflection.PromptBuilderTest do
  use ExUnit.Case
  alias Jido.Runner.GEPA.Reflection.PromptBuilder

  describe "build_reflection_prompt/2" do
    test "includes all required sections" do
      analysis = build_trajectory_analysis()
      prompt = PromptBuilder.build_reflection_prompt(analysis)

      assert prompt =~ "Original Prompt"
      assert prompt =~ "Task Context"
      assert prompt =~ "Execution Outcome"
      assert prompt =~ "Failure Analysis"
      assert prompt =~ "Reasoning Issues"
      assert prompt =~ "Your Task"
    end

    test "formats failure points correctly" do
      # Test failure point formatting
    end

    test "handles missing analysis fields gracefully" do
      # Test with incomplete analysis
    end

    # ... more tests
  end
end
```

#### Reflector Tests (15+ tests with mocks)
```elixir
defmodule Jido.Runner.GEPA.ReflectorTest do
  use ExUnit.Case
  use Mimic

  alias Jido.Runner.GEPA.Reflector
  alias Jido.Runner.GEPA.TestHelper

  setup :set_mimic_global

  describe "reflect_on_failure/2" do
    setup do
      # Setup mock LLM responses
      TestHelper.setup_mock_model(:openai,
        scenario: :reflection_success,
        response: build_reflection_json()
      )
    end

    test "successfully reflects on failed trajectory" do
      analysis = build_failed_analysis()

      {:ok, reflection} = Reflector.reflect_on_failure(analysis)

      assert %ParsedReflection{} = reflection
      assert length(reflection.suggestions) > 0
      assert reflection.analysis != ""
    end

    test "handles LLM timeout gracefully" do
      # Test timeout handling
    end

    test "retries on temporary failures" do
      # Test retry logic
    end

    # ... more tests
  end
end
```

#### SuggestionParser Tests (20+ tests)
```elixir
defmodule Jido.Runner.GEPA.Reflection.SuggestionParserTest do
  use ExUnit.Case
  alias Jido.Runner.GEPA.Reflection.SuggestionParser

  describe "parse_reflection_response/2" do
    test "parses valid JSON response" do
      response = build_valid_response()
      analysis = build_trajectory_analysis()

      {:ok, parsed} = SuggestionParser.parse_reflection_response(response, analysis)

      assert %ParsedReflection{} = parsed
      assert length(parsed.suggestions) > 0
    end

    test "extracts JSON from markdown code blocks" do
      # Test markdown extraction
    end

    test "handles malformed JSON gracefully" do
      # Test error handling
    end

    test "validates suggestion types" do
      # Test type validation
    end

    # ... more tests
  end
end
```

#### ConversationManager Tests (15+ tests)
```elixir
defmodule Jido.Runner.GEPA.Reflection.ConversationManagerTest do
  use ExUnit.Case
  alias Jido.Runner.GEPA.Reflection.ConversationManager

  describe "conduct_reflection/2" do
    test "executes single turn when confidence high" do
      # Test single-turn path
    end

    test "requests clarification when suggestions generic" do
      # Test multi-turn trigger
    end

    test "respects max_turns limit" do
      # Test turn limit
    end

    test "selects best reflection from multiple turns" do
      # Test reflection scoring
    end

    # ... more tests
  end
end
```

### Integration Tests

```elixir
defmodule Jido.Runner.GEPA.ReflectionIntegrationTest do
  use ExUnit.Case
  use Mimic

  alias Jido.Runner.GEPA.{Reflector, TrajectoryAnalyzer}

  setup :set_mimic_global

  describe "end-to-end reflection workflow" do
    setup do
      TestHelper.setup_mock_model(:openai, scenario: :reflection_success)
    end

    test "analyzes trajectory and generates reflection" do
      # Build failed trajectory
      trajectory = build_failed_trajectory()

      # Analyze trajectory
      analysis = TrajectoryAnalyzer.analyze(trajectory)

      # Reflect on analysis
      {:ok, reflection} = Reflector.reflect_on_failure(analysis)

      # Verify structured output
      assert %ParsedReflection{} = reflection
      assert reflection.trajectory_id == trajectory.id
      assert length(reflection.suggestions) > 0

      # Verify suggestion quality
      high_priority = Enum.filter(reflection.suggestions,
        &(&1.priority == :high))
      assert length(high_priority) > 0

      # Verify specificity
      specific = Enum.filter(reflection.suggestions,
        &(&1.specific_text != nil))
      assert length(specific) > 0
    end

    test "multi-turn reflection improves specificity" do
      # Test that second turn provides more specific suggestions
    end
  end
end
```

### Mock Infrastructure

Use existing test infrastructure:
- `Jido.Runner.GEPA.TestHelper` for mocking
- `Jido.Runner.GEPA.TestFixtures` for test data
- `Mimic` for function stubbing

```elixir
# Add to TestFixtures
def build_reflection_json(scenario \\ :success) do
  case scenario do
    :success ->
      %{
        "analysis" => "The prompt lacks clear step-by-step instructions...",
        "root_causes" => ["No CoT trigger", "Unclear constraints"],
        "suggestions" => [
          %{
            "type" => "add",
            "category" => "structure",
            "description" => "Add CoT trigger",
            "rationale" => "Forces systematic reasoning",
            "priority" => "high",
            "specific_text" => "Let's think step by step:"
          }
        ],
        "expected_improvement" => "Should improve reasoning quality by 60%"
      }

    :generic ->
      # Generic suggestions without specific text

    :vague ->
      # Vague root causes
  end
end
```

## Implementation Phases

### Phase 1: Foundation (Days 1-2)
- [ ] Create module structure
- [ ] Define TypedStruct data structures
- [ ] Implement PromptBuilder
- [ ] Unit tests for PromptBuilder
- [ ] **Deliverable**: Reflection prompts generated from TrajectoryAnalysis

### Phase 2: LLM Integration (Days 3-4)
- [ ] Implement Reflector.reflect_on_failure/2
- [ ] Add agent spawning and LLM calls
- [ ] Implement response handling
- [ ] Add error handling and retries
- [ ] Unit tests with mocked LLM
- [ ] **Deliverable**: Basic reflection working with mocked LLM

### Phase 3: Parsing (Days 5-6)
- [ ] Implement SuggestionParser
- [ ] Add JSON extraction from various formats
- [ ] Implement suggestion validation
- [ ] Build ParsedReflection
- [ ] Add confidence calculation
- [ ] Unit tests for parsing
- [ ] **Deliverable**: Structured suggestions from LLM responses

### Phase 4: Multi-Turn (Days 7-8)
- [ ] Implement ConversationManager
- [ ] Add clarification detection
- [ ] Implement follow-up generation
- [ ] Add reflection scoring
- [ ] Unit tests for multi-turn
- [ ] **Deliverable**: Multi-turn reflection working

### Phase 5: Integration & Testing (Days 9-10)
- [ ] Integration tests with TrajectoryAnalyzer
- [ ] End-to-end workflow tests
- [ ] Performance testing
- [ ] Documentation
- [ ] Code review and refinement
- [ ] **Deliverable**: Complete, tested Task 1.3.2

## Performance Considerations

### LLM Call Latency
- **Single reflection**: 2-5 seconds (depends on model)
- **Multi-turn**: 5-15 seconds (2-3 turns)
- **Mitigation**: Cache reflections for similar failures

### Token Usage
- **Prompt size**: ~1000-2000 tokens (trajectory analysis)
- **Response size**: ~500-1000 tokens (suggestions)
- **Total per reflection**: ~1500-3000 tokens
- **Cost**: ~$0.03-0.06 per reflection (GPT-4)

### Concurrency
- Each reflection spawns independent agent
- Safe for parallel execution
- No shared state between reflections
- Resource pooling for LLM calls

## Error Handling

### LLM Errors
```elixir
case Reflector.reflect_on_failure(analysis) do
  {:ok, reflection} ->
    # Success path

  {:error, {:reflection_failed, :timeout}} ->
    # Retry with longer timeout

  {:error, {:reflection_failed, :llm_error}} ->
    # Try different model or fallback

  {:error, {:parsing_failed, reason}} ->
    # Log for improvement, use partial results
end
```

### Graceful Degradation
1. **Parsing fails**: Return partial reflection with high-level analysis
2. **Generic suggestions**: Trigger multi-turn for specificity
3. **Low confidence**: Request human review or use conservative mutations
4. **Complete failure**: Fall back to rule-based mutation

## Success Criteria

### Functional Requirements
- [ ] Generate reflection prompts from TrajectoryAnalysis
- [ ] Execute LLM calls with structured JSON output
- [ ] Parse suggestions into actionable data structures
- [ ] Support multi-turn reflection (2-3 turns)
- [ ] Handle errors gracefully with fallbacks

### Quality Metrics
- [ ] Suggestion specificity: >70% include specific_text
- [ ] Suggestion priority: >50% marked high or critical
- [ ] Confidence: Average >0.6 for single-turn, >0.8 for multi-turn
- [ ] Parsing success rate: >95%
- [ ] Multi-turn trigger rate: 20-30% (when needed)

### Performance Metrics
- [ ] Reflection latency: <5s single-turn, <15s multi-turn
- [ ] Token efficiency: <3000 tokens per reflection
- [ ] Success rate: >90% produce usable suggestions

### Test Coverage
- [ ] Unit tests: 60+ tests across all modules
- [ ] Integration tests: 10+ end-to-end scenarios
- [ ] All tests passing
- [ ] Edge cases covered

## Risks & Mitigations

### Risk: LLM produces generic suggestions
**Mitigation**: Multi-turn clarification; template follow-ups

### Risk: JSON parsing fails on malformed responses
**Mitigation**: Multiple extraction strategies; graceful degradation

### Risk: High cost from excessive LLM calls
**Mitigation**: Caching; configurable max_turns; fast models for clarification

### Risk: Low-quality reflections from cheap models
**Mitigation**: Use GPT-4/Claude 3.5 for reflection; cost justified by quality

### Risk: Timeout on long trajectory analysis
**Mitigation**: Filter trajectories before reflection; configurable timeouts

## Future Enhancements (Post-1.3.2)

### Reflection Caching
- Cache similar failure patterns
- Reuse suggestions for similar trajectories
- Build library of common improvements

### Reflection Templates
- Pre-built templates for common failure types
- Domain-specific reflection strategies
- Task-type-specific analysis

### Ensemble Reflection
- Multiple models reflect on same failure
- Aggregate suggestions from different perspectives
- Vote on best suggestions

### Human-in-the-Loop
- Flag low-confidence reflections for review
- Learn from human feedback
- Improve reflection prompts over time

## Documentation Checklist

- [ ] Module documentation (@moduledoc)
- [ ] Function documentation (@doc)
- [ ] Type specifications (@spec)
- [ ] Usage examples in docs
- [ ] Integration guide
- [ ] Architecture diagrams
- [ ] API reference
- [ ] Migration guide (if breaking changes)

## Review Checklist

Before considering Task 1.3.2 complete:

- [ ] All subtasks implemented (1.3.2.1 - 1.3.2.4)
- [ ] TypedStruct data structures defined
- [ ] Reflection prompts generating correctly
- [ ] LLM integration working with Jido.AI.Agent
- [ ] JSON parsing handling multiple formats
- [ ] Multi-turn conversation logic working
- [ ] 60+ unit tests passing
- [ ] 10+ integration tests passing
- [ ] Mock infrastructure working
- [ ] Error handling comprehensive
- [ ] Performance acceptable (<15s multi-turn)
- [ ] Documentation complete
- [ ] Code review completed
- [ ] Integration with TrajectoryAnalyzer verified
- [ ] Ready for Task 1.3.3 (Suggestion Generation)

## References

### Existing Codebase
- `/home/ducky/code/agentjido/cot/lib/jido/runner/gepa/trajectory_analyzer.ex` - Analysis input
- `/home/ducky/code/agentjido/cot/lib/jido/runner/gepa/trajectory.ex` - Trajectory data
- `/home/ducky/code/agentjido/cot/lib/jido_ai/agent.ex` - LLM agent
- `/home/ducky/code/agentjido/cot/test/support/gepa_test_helper.ex` - Test mocking

### Phase 5 Documentation
- `/home/ducky/code/agentjido/cot/notes/planning/phase-05.md` - Overall plan
- Lines 164-173: Task 1.3.2 requirements

### Related Tasks
- Task 1.3.1: Trajectory Analysis (COMPLETE - prerequisite)
- Task 1.3.3: Improvement Suggestion Generation (NEXT)
- Task 1.3.4: Feedback Aggregation (FUTURE)
- Task 1.4.x: Mutation Operators (FUTURE - uses reflection output)

---

**Document Version**: 1.0
**Created**: 2025-10-23
**Author**: Claude (Planning Agent)
**Status**: Ready for Implementation
