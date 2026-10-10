defmodule Jido.AI.Reasoning.ReAct.Transformers.SystemOneTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.AI.Reasoning.ReAct.{Config, RequestTransformer, Runner}
  alias Jido.AI.Reasoning.ReAct.Transformers.SystemOne

  # Answers are plain maps: the transformer depends only on the documented shape
  # (`:noul`, `:probabilities`, `:score`), so any client's structs that carry those
  # fields work too.
  defmodule StubClient do
    @behaviour Jido.AI.SystemOne.Client

    @impl true
    def evaluate(state, questions, opts) do
      if owner = opts[:owner], do: send(owner, {:system_one_call, state, questions})

      case Keyword.fetch!(opts, :answers) do
        fun when is_function(fun, 2) -> fun.(state, questions)
        answers -> {:ok, answers, %{latency_ms: 7, model: "stub"}}
      end
    end
  end

  defmodule Add do
    use Jido.Action,
      name: "add",
      description: "Adds two numbers",
      schema: Zoi.object(%{a: Zoi.integer(), b: Zoi.integer()})

    def run(%{a: a, b: b}, _context), do: {:ok, %{sum: a + b}}
  end

  defmodule Gcd do
    use Jido.Action,
      name: "gcd",
      description: "Greatest common divisor of two integers",
      schema: Zoi.object(%{a: Zoi.integer(), b: Zoi.integer()})

    def run(%{a: a, b: b}, _context), do: {:ok, %{gcd: Integer.gcd(a, b)}}
  end

  defmodule CountWords do
    use Jido.Action,
      name: "count_words",
      description: "Counts words in a text",
      schema: Zoi.object(%{text: Zoi.string()})

    def run(%{text: t}, _context), do: {:ok, %{count: length(String.split(t))}}
  end

  defmodule Router do
    use Jido.AI.Reasoning.ReAct.Transformers.SystemOne,
      client: Jido.AI.Reasoning.ReAct.Transformers.SystemOneTest.StubClient,
      top_k: 2,
      models: {:fast, :capable, :reasoning}
  end

  @tools %{"add" => Add, "gcd" => Gcd, "count_words" => CountWords}
  @request %{messages: [%{role: :user, content: "gcd of 1071 and 462"}], llm_opts: [], tools: @tools, model: :fast}

  defp answers(needs, probs, depth) do
    %{
      "needs_tool" => %{noul: needs},
      "tool" => %{probabilities: probs},
      "depth" => %{score: depth}
    }
  end

  defp transform(answers, opts \\ []) do
    opts = Keyword.merge([client: StubClient, client_opts: [answers: answers]], opts)
    SystemOne.transform(@request, %{iteration: 1}, %{observability: %{}}, %{request_id: "req-1"}, opts)
  end

  describe "tool gating" do
    test "keeps the top-k tools by probability and drops none" do
      probs = %{"gcd" => 0.7, "add" => 0.2, "count_words" => 0.05, "none" => 0.05}
      assert {:ok, %{tools: tools}} = transform(answers(0.9, probs, 0.2), top_k: 2)
      assert tools == %{"gcd" => Gcd, "add" => Add}
    end

    test "drops tools Jev scored at zero instead of filling top-k with ties" do
      probs = %{"gcd" => 0.9, "add" => 0.0, "count_words" => 0.0, "none" => 0.1}
      assert {:ok, %{tools: tools}} = transform(answers(0.9, probs, 0.2), top_k: 3)
      assert tools == %{"gcd" => Gcd}
    end

    test "offers no tools when the next step needs none" do
      assert {:ok, %{tools: tools}} = transform(answers(0.1, %{"gcd" => 0.5, "none" => 0.5}, 0.2))
      assert tools == %{}
    end

    test "never empties the tools because every named tool is unknown" do
      assert {:ok, overrides} = transform(answers(0.9, %{"ghost" => 0.8, "none" => 0.2}, 0.2))
      refute Map.has_key?(overrides, :tools)
    end
  end

  describe "model tiers" do
    test "are off by default" do
      assert {:ok, overrides} = transform(answers(0.9, %{"gcd" => 1.0}, 1.9))
      refute Map.has_key?(overrides, :model)
    end

    test "map the depth score onto the configured aliases" do
      models = [models: {:fast, :capable, :reasoning}]
      assert {:ok, %{model: :fast}} = transform(answers(0.9, %{"gcd" => 1.0}, 0.3), models)
      assert {:ok, %{model: :capable}} = transform(answers(0.9, %{"gcd" => 1.0}, 1.0), models)
      assert {:ok, %{model: :reasoning}} = transform(answers(0.9, %{"gcd" => 1.0}, 1.7), models)

      assert {:ok, %{model: :fast}} =
               transform(answers(0.9, %{"gcd" => 1.0}, 1.0), models ++ [depth_thresholds: {1.2, 1.8}])
    end
  end

  describe "fails open" do
    test "on a client error" do
      assert {:ok, overrides} = transform(fn _, _ -> {:error, {:http, 529, ""}} end)
      assert overrides == %{}
    end

    test "when the client raises" do
      assert {:ok, overrides} = transform(fn _, _ -> raise "boom" end)
      assert overrides == %{}
    end

    test "when an answer is missing or malformed" do
      assert {:ok, %{}} = transform(%{"needs_tool" => %{noul: 0.9}})
      assert {:ok, %{}} = transform(answers(0.9, %{"gcd" => "high"}, 0.2))
      assert {:ok, %{}} = transform(answers(0.9, %{{:bad, :key} => 1.0}, 0.2))
      assert {:ok, %{}} = transform(answers(1.1, %{"gcd" => 1.0}, 0.2))
      assert {:ok, %{}} = transform(answers(0.9, %{"gcd" => 1.1}, 0.2))
      assert {:ok, %{}} = transform(answers(0.9, %{"gcd" => 1.0}, 2.1))
    end

    test "when a runtime override is invalid" do
      opts = [client: StubClient, client_opts: [answers: answers(0.9, %{"gcd" => 1.0}, 0.2)]]
      context = %{system_one: [top_k: "two"]}

      assert {:ok, %{}} = SystemOne.transform(@request, %{iteration: 1}, %{}, context, opts)
    end

    test "when there are more tools than one Choice question can hold" do
      many = Map.new(1..300, fn i -> {"tool_#{i}", Add} end)
      request = %{@request | tools: many}
      opts = [client: StubClient, client_opts: [answers: fn _, _ -> flunk("must not call the client") end]]
      assert {:ok, %{}} = SystemOne.transform(request, %{iteration: 1}, %{}, %{}, opts)
    end

    test "when the turn has no tools and model routing is off" do
      request = %{@request | tools: %{}}
      opts = [client: StubClient, client_opts: [answers: fn _, _ -> flunk("must not call the client") end]]

      assert {:ok, %{}} = SystemOne.transform(request, %{iteration: 1}, %{}, %{}, opts)
    end
  end

  describe "runtime overrides" do
    test "can replace the client" do
      opts = [client: String, client_opts: [answers: answers(0.9, %{"gcd" => 1.0}, 0.2)]]
      context = %{system_one: [client: StubClient]}

      assert {:ok, %{tools: %{"gcd" => Gcd}}} =
               SystemOne.transform(@request, %{iteration: 1}, %{}, context, opts)
    end
  end

  describe "what the client is asked" do
    test "the latest user request, recent tool results, and every tool with its description" do
      request = %{
        @request
        | messages: [
            %{role: :user, content: "first"},
            %{role: :assistant, content: "calling"},
            %{role: :tool, name: "gcd", content: ~s({"gcd":21})},
            %{role: :user, content: [%{type: :text, text: "second"}]}
          ]
      }

      opts = [client: StubClient, client_opts: [owner: self(), answers: answers(0.9, %{"gcd" => 1.0}, 0.2)]]
      SystemOne.transform(request, %{iteration: 2}, %{}, %{}, opts)

      assert_received {:system_one_call, state, questions}
      assert state.request == "second"
      assert [progress] = state.progress
      assert progress =~ "gcd" and progress =~ "21"
      assert state.available_actions |> Enum.map(& &1.name) |> Enum.sort() == ["add", "count_words", "gcd"]

      assert %{"type" => "choice", "criteria" => %{"gcd" => "Greatest common divisor of two integers", "none" => _}} =
               questions["tool"]

      assert questions["needs_tool"]["type"] == "noul"
      assert questions["depth"]["type"] == "score"
    end
  end

  test "emits one routing telemetry event per decision" do
    ref = make_ref()
    parent = self()
    event = [:jido, :ai, :strategy, :react, :system_one_route]
    :telemetry.attach({__MODULE__, ref}, event, fn _e, m, md, _ -> send(parent, {ref, m, md}) end, nil)
    on_exit(fn -> :telemetry.detach({__MODULE__, ref}) end)

    transform(answers(0.9, %{"gcd" => 0.9, "none" => 0.1}, 1.0), models: {:fast, :capable, :reasoning})

    assert_received {^ref, %{duration_ms: 7}, metadata}
    assert metadata.request_id == "req-1"
    assert metadata.iteration == 1
    assert metadata.chosen_tools == ["gcd"]
    assert metadata.chosen_model == :capable
    assert metadata.needs_tool == 0.9
  end

  describe "use" do
    test "reports invalid options as compile errors" do
      assert_raise CompileError, ~r/requires a :client module/, fn ->
        Code.compile_string("""
        defmodule BadRouter do
          use Jido.AI.Reasoning.ReAct.Transformers.SystemOne, top_k: 2
        end
        """)
      end

      assert_raise CompileError, ~r/:top_k must be a positive integer/, fn ->
        Code.compile_string("""
        defmodule BadRouter2 do
          use Jido.AI.Reasoning.ReAct.Transformers.SystemOne, client: Foo, top_k: 0
        end
        """)
      end
    end

    test "the generated module is a valid request transformer" do
      assert {:ok, Router} = RequestTransformer.validate(Router)
    end
  end

  describe "inside the ReAct runner" do
    setup :set_mimic_from_context

    test "the provider sees only the gated tools and the routed model" do
      parent = self()

      Mimic.expect(ReqLLM.Generation, :generate_text, fn model, _messages, opts ->
        send(parent, {:provider, model, Enum.map(opts[:tools], & &1.name)})
        {:error, :offline_provider_boundary}
      end)

      config =
        Config.new(model: :fast, tools: [Add, Gcd, CountWords], streaming: false, request_transformer: Router)

      client_answers = answers(0.95, %{"gcd" => 0.9, "add" => 0.08, "count_words" => 0.0, "none" => 0.02}, 1.0)

      Runner.stream("gcd of 1071 and 462", config, context: %{system_one: [client_opts: [answers: client_answers]]})
      |> Enum.to_list()

      assert_received {:provider, model, tool_names}
      assert Enum.sort(tool_names) == ["add", "gcd"]
      assert model == Jido.AI.resolve_model(:capable)
    end

    test "a failing client leaves the turn exactly as configured" do
      parent = self()

      Mimic.expect(ReqLLM.Generation, :generate_text, fn model, _messages, opts ->
        send(parent, {:provider, model, Enum.map(opts[:tools], & &1.name)})
        {:error, :offline_provider_boundary}
      end)

      config =
        Config.new(model: :fast, tools: [Add, Gcd, CountWords], streaming: false, request_transformer: Router)

      Runner.stream("gcd of 1071 and 462", config,
        context: %{system_one: [client_opts: [answers: fn _, _ -> {:error, :down} end]]}
      )
      |> Enum.to_list()

      assert_received {:provider, model, tool_names}
      assert Enum.sort(tool_names) == ["add", "count_words", "gcd"]
      assert model == Jido.AI.resolve_model(:fast)
    end
  end
end
