defmodule Jido.AI.Effects.PolicyTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Effects.Policy
  alias Jido.Agent.Directive
  alias Jido.AI.Effects.State
  alias Jido.Plugin.Dispatch.Send
  alias Jido.Plugin.Scheduler.Schedule

  defp signal(type \\ "ai.test"),
    do: Jido.Signal.new!(type, %{}, %{source: "/effects/test"})

  test "default policy allows complete state and safe directives but denies spawn directives" do
    policy = Policy.default()

    assert Policy.allowed?(policy, %State{state: %{flag: true}})
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

    assert Policy.allowed?(policy, %Directive.Emit{
             signal: %{type: "ai.test"},
             dispatch: {:pid, target: self()}
           })

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
        %{
          mode: :allow_list,
          allow: [Directive.Emit],
          constraints: %{emit: %{allowed_dispatches: [:pid, :pubsub]}}
        },
        %{constraints: %{emit: %{allowed_dispatches: []}}}
      )

    assert policy.constraints[:emit][:allowed_dispatches] == []
    refute Policy.allowed?(policy, %Directive.Emit{signal: %{type: "ai.test"}, dispatch: :pid})
  end

  test "schedule constraints enforce max delay when present" do
    policy =
      Policy.new(%{
        mode: :allow_list,
        allow: [Schedule],
        constraints: %{schedule: %{max_delay_ms: 100}}
      })

    assert Policy.allowed?(policy, %Schedule{
             delay_ms: 100,
             signal: Jido.Signal.new!("ai.tick", %{}, %{source: "/effects/test"})
           })

    refute Policy.allowed?(policy, %Schedule{
             delay_ms: 101,
             signal: signal("ai.tick")
           })
  end

  test "normalizes modes, matchers, and invalid policy input" do
    default = Policy.default()
    assert Policy.new(default) == default
    assert Policy.new(nil) == default
    assert Policy.new(:invalid) == default

    allow_all = Policy.new(%{"mode" => "allow_all", "allow" => []})
    assert Policy.allowed?(allow_all, %State{state: %{}})

    deny_all = Policy.new(mode: "deny_all", deny: [])
    refute Policy.allowed?(deny_all, %State{state: %{}})

    allow_list =
      Policy.new(%{
        mode: "not-a-mode",
        allow: MapSet.new([State]),
        deny: [],
        constraints: :invalid
      })

    assert allow_list.mode == :allow_list
    assert Policy.allowed?(allow_list, %State{state: %{}})
    refute Policy.allowed?(allow_list, :not_a_struct)

    module_name = Atom.to_string(State)
    from_strings = Policy.new(allow: [module_name, "Elixir.Unknown.Policy.Matcher", 17], deny: [])
    assert from_strings.allow == MapSet.new([State])
  end

  test "filters lists and single effects while preserving order" do
    state = %State{state: %{value: 1}}
    spawn = %Directive.SpawnAgent{agent: __MODULE__, tag: :child}

    assert Policy.filter(nil, [state, spawn, state]) == {[state, state], [spawn]}
    assert Policy.filter(%{mode: :deny_all}, state) == {[], [state]}
  end

  test "enforces signal type and prefix constraints for atom and string maps" do
    policy =
      Policy.new(
        allow: [Directive.Emit],
        deny: [],
        constraints: %{
          emit: %{
            allowed_signal_types: "ai.allowed",
            allowed_signal_prefixes: "ai."
          }
        }
      )

    assert Policy.allowed?(policy, %Directive.Emit{signal: %{type: "ai.allowed"}})
    assert Policy.allowed?(policy, %Directive.Emit{signal: %{"type" => "ai.allowed"}})
    refute Policy.allowed?(policy, %Directive.Emit{signal: %{type: "ai.other"}})
    refute Policy.allowed?(policy, %Directive.Emit{signal: %{value: "missing"}})
  end

  test "normalizes dispatch targets and applies the same constraints to Send" do
    policy =
      Policy.new(
        allow: [Directive.Emit, Send],
        deny: [],
        constraints: %{emit: %{allowed_dispatches: [:default, :pid, "pubsub", " ", 17]}}
      )

    emit = fn dispatch -> %Directive.Emit{signal: %{type: "ai.test"}, dispatch: dispatch} end

    assert Policy.allowed?(policy, emit.(nil))
    assert Policy.allowed?(policy, emit.({:pid, target: self()}))
    assert Policy.allowed?(policy, emit.([:pid, :pubsub]))
    refute Policy.allowed?(policy, emit.([:pid, :bus]))
    refute Policy.allowed?(policy, emit.(%{adapter: :pid}))

    assert Policy.allowed?(policy, %Send{signal: signal(), target: :pid})
    refute Policy.allowed?(policy, %Send{signal: signal(), target: :bus})
  end

  test "normalizes malformed constraints without widening explicit empty constraints" do
    policy =
      Policy.new(
        allow: [Directive.Emit, Schedule],
        deny: [],
        constraints: [emit: :invalid, schedule: :invalid]
      )

    assert Policy.allowed?(policy, %Directive.Emit{signal: %{type: "ai.test"}})
    assert Policy.allowed?(policy, %Schedule{delay_ms: 10, signal: signal()})

    invalid_max =
      Policy.new(
        allow: [Schedule],
        deny: [],
        constraints: %{schedule: %{max_delay_ms: -1}}
      )

    assert Policy.allowed?(invalid_max, %Schedule{delay_ms: -1, signal: signal()})

    bounded =
      Policy.new(
        allow: [Schedule],
        deny: [],
        constraints: %{schedule: %{max_delay_ms: 10}}
      )

    refute Policy.allowed?(bounded, %Schedule{delay_ms: -1, signal: signal()})
    refute Policy.allowed?(bounded, %Schedule{delay_ms: :invalid, signal: signal()})
  end

  test "intersects every mode combination and narrows allow sets" do
    policies = %{
      deny_all: %{mode: :deny_all, allow: [State], deny: []},
      allow_all: %{mode: :allow_all, allow: [], deny: []},
      allow_list: %{mode: :allow_list, allow: [State, Directive.Emit], deny: []}
    }

    expected = %{
      {:deny_all, :deny_all} => :deny_all,
      {:deny_all, :allow_all} => :deny_all,
      {:deny_all, :allow_list} => :deny_all,
      {:allow_all, :deny_all} => :deny_all,
      {:allow_all, :allow_all} => :allow_all,
      {:allow_all, :allow_list} => :allow_list,
      {:allow_list, :deny_all} => :deny_all,
      {:allow_list, :allow_all} => :allow_list,
      {:allow_list, :allow_list} => :allow_list
    }

    for {{left, right}, mode} <- expected do
      policy = Policy.intersect(policies[left], policies[right])
      assert policy.mode == mode
    end

    narrowed =
      Policy.intersect(
        %{mode: :allow_list, allow: [State, Directive.Emit], deny: []},
        %{mode: :allow_list, allow: [State], deny: [Directive.Emit]}
      )

    assert narrowed.allow == MapSet.new([State])
    assert MapSet.member?(narrowed.deny, Directive.Emit)
  end

  test "intersects emit and schedule constraints field by field" do
    agent = %{
      mode: :allow_all,
      deny: [],
      constraints: %{
        emit: %{
          allowed_signal_prefixes: ["ai.", "app."],
          allowed_signal_types: ["ai.ok", "app.ok"],
          allowed_dispatches: [:pid, :pubsub]
        },
        schedule: %{max_delay_ms: 200}
      }
    }

    strategy = %{
      mode: :allow_all,
      deny: [],
      constraints: %{
        emit: %{
          allowed_signal_prefixes: ["ai."],
          allowed_signal_types: ["ai.ok"],
          allowed_dispatches: [:pid]
        },
        schedule: %{max_delay_ms: 100}
      }
    }

    policy = Policy.intersect(agent, strategy)

    assert policy.constraints.emit == %{
             allowed_signal_prefixes: ["ai."],
             allowed_signal_types: ["ai.ok"],
             allowed_dispatches: [:pid]
           }

    assert policy.constraints.schedule == %{max_delay_ms: 100}

    left_only = Policy.intersect(agent, %{mode: :allow_all, deny: []})
    assert left_only.constraints.emit == Policy.new(agent).constraints.emit
    assert left_only.constraints.schedule == %{max_delay_ms: 200}

    right_only = Policy.intersect(%{mode: :allow_all, deny: []}, strategy)
    assert right_only.constraints.emit == Policy.new(strategy).constraints.emit
    assert right_only.constraints.schedule == %{max_delay_ms: 100}
  end

  test "intersects partially specified constraint fields" do
    policy =
      Policy.intersect(
        %{
          mode: :allow_all,
          deny: [],
          constraints: %{emit: %{allowed_signal_types: ["ai.ok"]}, schedule: %{}}
        },
        %{
          mode: :allow_all,
          deny: [],
          constraints: %{emit: %{allowed_dispatches: [:pid]}, schedule: %{}}
        }
      )

    assert policy.constraints.emit == %{
             allowed_signal_types: ["ai.ok"],
             allowed_dispatches: [:pid]
           }

    assert policy.constraints.schedule == %{}
  end
end
