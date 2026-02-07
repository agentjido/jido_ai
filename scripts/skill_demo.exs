#!/usr/bin/env elixir

# Skill System Demo
# Run with: mix run scripts/skill_demo.exs

IO.puts("""
#{IO.ANSI.bright()}#{IO.ANSI.cyan()}
╔══════════════════════════════════════════════════════════════╗
║            Jido.AI.Skill System Demo                         ║
╚══════════════════════════════════════════════════════════════╝
#{IO.ANSI.reset()}
""")

alias Jido.AI.Skill
alias Jido.AI.Skill.{Loader, Registry}

# ============================================================================
# Part 1: Module-based Skills
# ============================================================================

IO.puts("#{IO.ANSI.bright()}1. Module-based Skills#{IO.ANSI.reset()}\n")

defmodule Demo.Skills.Calculator do
  use Jido.AI.Skill,
    name: "calculator",
    description: "Performs mathematical calculations with step-by-step explanations.",
    license: "MIT",
    allowed_tools: ~w(add subtract multiply divide),
    tags: ["math", "utility"],
    body: """
    # Calculator Skill

    ## When to Use
    Activate when users need help with arithmetic or mathematical expressions.

    ## Workflow
    1. Parse the mathematical expression
    2. Break down into individual operations
    3. Execute each operation with the appropriate tool
    4. Combine results and explain

    ## Supported Operations
    - Addition: `add(a, b)`
    - Subtraction: `subtract(a, b)`
    - Multiplication: `multiply(a, b)`
    - Division: `divide(a, b)`
    """
end

spec = Demo.Skills.Calculator.manifest()
IO.puts("  Created module skill: #{IO.ANSI.cyan()}#{spec.name}#{IO.ANSI.reset()}")
IO.puts("  Description: #{spec.description}")
IO.puts("  License: #{spec.license}")
IO.puts("  Allowed tools: #{Enum.join(spec.allowed_tools, ", ")}")
IO.puts("  Tags: #{Enum.join(spec.tags, ", ")}")
IO.puts("")
IO.puts("  Body preview:")
IO.puts("  #{IO.ANSI.faint()}#{String.slice(Demo.Skills.Calculator.body(), 0, 100)}...#{IO.ANSI.reset()}")
IO.puts("")

# ============================================================================
# Part 2: Runtime-loaded SKILL.md Files
# ============================================================================

IO.puts("#{IO.ANSI.bright()}2. Runtime-loaded Skills (SKILL.md)#{IO.ANSI.reset()}\n")

skill_path = "priv/skills/code-review/SKILL.md"

if File.exists?(skill_path) do
  case Loader.load(skill_path) do
    {:ok, runtime_spec} ->
      IO.puts("  Loaded from: #{IO.ANSI.yellow()}#{skill_path}#{IO.ANSI.reset()}")
      IO.puts("  Name: #{IO.ANSI.cyan()}#{runtime_spec.name}#{IO.ANSI.reset()}")
      IO.puts("  Description: #{runtime_spec.description}")
      IO.puts("  License: #{runtime_spec.license}")
      IO.puts("  Allowed tools: #{Enum.join(runtime_spec.allowed_tools, ", ")}")

      if runtime_spec.metadata do
        IO.puts("  Metadata: #{inspect(runtime_spec.metadata)}")
      end

      IO.puts("")
      IO.puts("  Body length: #{String.length(Skill.body(runtime_spec))} characters")
      IO.puts("")

    {:error, reason} ->
      IO.puts("  #{IO.ANSI.red()}Error loading skill: #{inspect(reason)}#{IO.ANSI.reset()}")
  end
else
  IO.puts("  #{IO.ANSI.yellow()}Skill file not found: #{skill_path}#{IO.ANSI.reset()}")
  IO.puts("  Run from project root or create the example skill first.")
  IO.puts("")
end

# ============================================================================
# Part 3: Unified API
# ============================================================================

IO.puts("#{IO.ANSI.bright()}3. Unified API#{IO.ANSI.reset()}\n")

IO.puts("  The same API works for both module and runtime skills:")
IO.puts("")
IO.puts("  # Module skill")
IO.puts("  Skill.manifest(Demo.Skills.Calculator)  # => %Spec{...}")
IO.puts("  Skill.body(Demo.Skills.Calculator)      # => \"# Calculator...\"")
IO.puts("  Skill.allowed_tools(Demo.Skills.Calculator) # => [\"add\", ...]")
IO.puts("")

# Demonstrate with module
IO.puts("  #{IO.ANSI.faint()}Skill.manifest(Demo.Skills.Calculator).name => #{IO.ANSI.reset()}#{Skill.manifest(Demo.Skills.Calculator).name}")
IO.puts("  #{IO.ANSI.faint()}Skill.allowed_tools(Demo.Skills.Calculator) => #{IO.ANSI.reset()}#{inspect(Skill.allowed_tools(Demo.Skills.Calculator))}")
IO.puts("")

# ============================================================================
# Part 4: Registry
# ============================================================================

IO.puts("#{IO.ANSI.bright()}4. Skill Registry#{IO.ANSI.reset()}\n")

# Start the registry
{:ok, _pid} = Registry.start_link()

# Register the module skill's spec
Registry.register(spec)
IO.puts("  Registered: #{spec.name}")

# Load runtime skills if available
if File.exists?("priv/skills") do
  case Registry.load_from_paths(["priv/skills"]) do
    {:ok, count} ->
      IO.puts("  Loaded #{count} skill(s) from priv/skills/")

    {:error, reason} ->
      IO.puts("  #{IO.ANSI.yellow()}Warning: #{inspect(reason)}#{IO.ANSI.reset()}")
  end
end

IO.puts("")
IO.puts("  Registered skills: #{inspect(Registry.list())}")
IO.puts("")

# Lookup by name
case Registry.lookup("calculator") do
  {:ok, found_spec} ->
    IO.puts("  Lookup 'calculator': #{IO.ANSI.green()}found#{IO.ANSI.reset()} (#{found_spec.description})")

  {:error, _} ->
    IO.puts("  Lookup 'calculator': #{IO.ANSI.red()}not found#{IO.ANSI.reset()}")
end

IO.puts("")

# ============================================================================
# Part 5: Skill Resolution
# ============================================================================

IO.puts("#{IO.ANSI.bright()}5. Skill Resolution#{IO.ANSI.reset()}\n")

IO.puts("  Skill.resolve/1 accepts modules, specs, or string names:")
IO.puts("")

# Resolve module
case Skill.resolve(Demo.Skills.Calculator) do
  {:ok, s} -> IO.puts("  resolve(Demo.Skills.Calculator) => #{IO.ANSI.green()}:ok#{IO.ANSI.reset()}, name: #{s.name}")
  {:error, e} -> IO.puts("  resolve(Demo.Skills.Calculator) => #{IO.ANSI.red()}:error#{IO.ANSI.reset()}, #{inspect(e)}")
end

# Resolve spec directly
case Skill.resolve(spec) do
  {:ok, s} -> IO.puts("  resolve(%Spec{...}) => #{IO.ANSI.green()}:ok#{IO.ANSI.reset()}, name: #{s.name}")
  {:error, e} -> IO.puts("  resolve(%Spec{...}) => #{IO.ANSI.red()}:error#{IO.ANSI.reset()}, #{inspect(e)}")
end

# Resolve by name
case Skill.resolve("calculator") do
  {:ok, s} -> IO.puts("  resolve(\"calculator\") => #{IO.ANSI.green()}:ok#{IO.ANSI.reset()}, name: #{s.name}")
  {:error, e} -> IO.puts("  resolve(\"calculator\") => #{IO.ANSI.red()}:error#{IO.ANSI.reset()}, #{inspect(e)}")
end

# Try resolving unknown
case Skill.resolve("unknown-skill") do
  {:ok, _} -> IO.puts("  resolve(\"unknown-skill\") => #{IO.ANSI.green()}:ok#{IO.ANSI.reset()}")
  {:error, _} -> IO.puts("  resolve(\"unknown-skill\") => #{IO.ANSI.red()}:error#{IO.ANSI.reset()} (expected)")
end

IO.puts("")

# ============================================================================
# Summary
# ============================================================================

# ============================================================================
# Part 6: Skill Prompt Rendering
# ============================================================================

IO.puts("#{IO.ANSI.bright()}6. Skill Prompt Rendering#{IO.ANSI.reset()}\n")

alias Jido.AI.Skill.Prompt

IO.puts("  Skills can be rendered into agent system prompts:")
IO.puts("")

# Show a preview of the rendered prompt
rendered = Prompt.render([Demo.Skills.Calculator], include_body: false)
IO.puts("  #{IO.ANSI.faint()}Prompt.render([Calculator], include_body: false):#{IO.ANSI.reset()}")
IO.puts("")

rendered
|> String.split("\n")
|> Enum.take(8)
|> Enum.each(fn line -> IO.puts("    #{IO.ANSI.cyan()}#{line}#{IO.ANSI.reset()}") end)

IO.puts("")

# Show tool filtering
IO.puts("  Tool filtering based on skill allowed_tools:")
IO.puts("")

mock_tools = [MockAdd, MockSubtract, MockMultiply, MockDivide, MockWeather]

defmodule MockAdd do
  def name, do: "add"
end

defmodule MockSubtract do
  def name, do: "subtract"
end

defmodule MockMultiply do
  def name, do: "multiply"
end

defmodule MockDivide do
  def name, do: "divide"
end

defmodule MockWeather do
  def name, do: "weather"
end

allowed = Prompt.collect_allowed_tools([Demo.Skills.Calculator])
IO.puts("  #{IO.ANSI.faint()}Allowed tools from Calculator skill:#{IO.ANSI.reset()} #{inspect(allowed)}")

filtered = Prompt.filter_tools([MockAdd, MockSubtract, MockMultiply, MockDivide, MockWeather], [Demo.Skills.Calculator])
IO.puts("  #{IO.ANSI.faint()}Filtered tools (5 -> #{length(filtered)}):#{IO.ANSI.reset()} #{inspect(Enum.map(filtered, & &1.name()))}")

IO.puts("")

IO.puts("""
#{IO.ANSI.bright()}#{IO.ANSI.cyan()}
╔══════════════════════════════════════════════════════════════╗
║                      Demo Complete!                          ║
╚══════════════════════════════════════════════════════════════╝
#{IO.ANSI.reset()}
Try these commands:

  #{IO.ANSI.yellow()}mix jido_ai.skill list priv/skills#{IO.ANSI.reset()}
  #{IO.ANSI.yellow()}mix jido_ai.skill show priv/skills/code-review/SKILL.md --body#{IO.ANSI.reset()}
  #{IO.ANSI.yellow()}mix jido_ai.skill validate priv/skills#{IO.ANSI.reset()}

Example agent using skills:

  #{IO.ANSI.yellow()}Jido.AI.Examples.CalculatorAgent#{IO.ANSI.reset()}

""")
