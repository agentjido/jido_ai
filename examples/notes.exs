Mix.install([
  {:jido_htn, path: "../"},
  {:typedstruct, "~> 0.5.3"}
])

# I want to build a single-use agent - meaning one agent is built for a single purpose - a core purpose
# Skills are "helpers" that can be added on - like having Memory, edit files or track it's tasks
# There's still just one purpose to the Agent

# Agents accept a prompt and tools - and be free wheeling, following a simple ReAct loop by default
# Agents can embed a "workflow", which is more guided
# Workflows should be adapters - meaning you can swap out how a workflow is implemented

# What's a workflow?
# Workflow has data in and data out
# Observable
# Workflows have steps in the middle - but those can be anything
#
# Workflow types:
# - Simple, execute a single tool and return the results
# - Async execution
# - Functional composition
# - Directed Acyclic Graph
# - Data Flow
# - Oban?
# - Broadway?
# - Flow?

# GenStage?
