defmodule Jido.AI.Effects.PolicyTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Effects.Policy
  alias Jido.Agent.Directive
  alias Jido.Agent.StateOp

  test "default policy allows state ops and safe directives but denies spawn directives" do
    policy = Policy.default()

    assert Policy.allowed?(policy, %StateOp.SetState{attrs: %{flag: true}})
    assert Policy.allowed?(policy, %Directive.Emit{signal: %{type: "ai.test"}})
    refute Policy.allowed?(policy, %Directive.SpawnAgent{agent: __MODULE__, tag: :child})
  end

  test "dispatch constraints compare adapters safely without dynamic atom creation" do
    policy =
      Policy.new(%{
        mode: :allow_list,
        allow: [Directive.Emit],
        constraints: %{emit: %{allowed_dispatches: ["pid", :pubsub]}}
      })

    assert Policy.allowed?(policy, %Directive.Emit{signal: %{type: "ai.test"}, dispatch: {:pid, target: self()}})
    assert Policy.allowed?(policy, %Directive.Emit{signal: %{type: "ai.test"}, dispatch: :pubsub})
    refute Policy.allowed?(policy, %Directive.Emit{signal: %{type: "ai.test"}, dispatch: :bus})
  end

  test "accepts keyword constraints and enforces them" do
    policy =
      Policy.new(
        mode: :allow_list,
        allow: [Directive.Emit],
        constraints: [
          emit: [
            allowed_signal_prefixes: ["ai."],
            allowed_dispatches: [:pid]
          ]
        ]
      )

    assert Policy.allowed?(policy, %Directive.Emit{signal: %{type: "ai.ok"}, dispatch: :pid})
    refute Policy.allowed?(policy, %Directive.Emit{signal: %{type: "foo.ok"}, dispatch: :pid})
    refute Policy.allowed?(policy, %Directive.Emit{signal: %{type: "ai.ok"}, dispatch: :pubsub})
  end

  test "accepts string-keyed constraints and enforces them" do
    policy =
      Policy.new(%{
        "mode" => "allow_list",
        "allow" => [Directive.Emit],
        "constraints" => %{
          "emit" => %{
            "allowed_signal_prefixes" => ["ai."],
            "allowed_dispatches" => ["pid"]
          }
        }
      })

    assert Policy.allowed?(policy, %Directive.Emit{signal: %{type: "ai.ok"}, dispatch: :pid})
    refute Policy.allowed?(policy, %Directive.Emit{signal: %{type: "foo.ok"}, dispatch: :pid})
    refute Policy.allowed?(policy, %Directive.Emit{signal: %{type: "ai.ok"}, dispatch: :pubsub})
  end

  test "empty emit allow-lists deny all emit types, prefixes, and dispatches" do
    emit = %Directive.Emit{signal: %{type: "ai.test"}, dispatch: :pid}

    deny_type =
      Policy.new(%{
        mode: :allow_list,
        allow: [Directive.Emit],
        constraints: %{emit: %{allowed_signal_types: []}}
      })

    deny_prefix =
      Policy.new(%{
        mode: :allow_list,
        allow: [Directive.Emit],
        constraints: %{emit: %{allowed_signal_prefixes: []}}
      })

    deny_dispatch =
      Policy.new(%{
        mode: :allow_list,
        allow: [Directive.Emit],
        constraints: %{emit: %{allowed_dispatches: []}}
      })

    refute Policy.allowed?(deny_type, emit)
    refute Policy.allowed?(deny_prefix, emit)
    refute Policy.allowed?(deny_dispatch, emit)
  end

  test "intersect preserves narrowing when strategy sets an empty dispatch list" do
    policy =
      Policy.intersect(
        %{mode: :allow_list, allow: [Directive.Emit], constraints: %{emit: %{allowed_dispatches: [:pid, :pubsub]}}},
        %{constraints: %{emit: %{allowed_dispatches: []}}}
      )

    assert policy.constraints[:emit][:allowed_dispatches] == []
    refute Policy.allowed?(policy, %Directive.Emit{signal: %{type: "ai.test"}, dispatch: :pid})
  end

  test "schedule constraints enforce max delay when present" do
    policy =
      Policy.new(%{
        mode: :allow_list,
        allow: [Directive.Schedule],
        constraints: %{schedule: %{max_delay_ms: 100}}
      })

    assert Policy.allowed?(policy, %Directive.Schedule{delay_ms: 100, message: :tick})
    refute Policy.allowed?(policy, %Directive.Schedule{delay_ms: 101, message: :tick})
  end
end
