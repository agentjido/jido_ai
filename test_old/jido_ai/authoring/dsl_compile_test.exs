defmodule Jido.AI.Authoring.DSLCompileTest do
  use ExUnit.Case, async: false

  @agent Jido.AI.Authoring.DSLCompileTest.DynamicAgent

  setup do
    :code.purge(@agent)
    :code.delete(@agent)

    on_exit(fn ->
      :code.purge(@agent)
      :code.delete(@agent)
    end)
  end

  test "inline instructions and Actions compile to ordinary Action modules" do
    Code.compile_string("""
    defmodule #{inspect(@agent)} do
      use Jido.AI.Agent, name: "dynamic_inline_agent"

      agent do
        schema Zoi.object(%{answer: Zoi.any() |> Zoi.default(nil)})

        ai :support do
          instructions %{query: query}, context: context do
            {:ok, %{instructions: "\#{context.tenant}: \#{query}"}}
          end

          model :capable

          tools do
            action :echo, %{value: value},
              description: "Echo one value",
              schema: Zoi.object(%{value: Zoi.string()}),
              context: _context do
              {:ok, %{value: value}}
            end
          end

          result into: :answer
        end
      end

      routes do
        route "dynamic.ask", ai: :support
      end
    end
    """)

    profile = apply(@agent, :ai_profile, [:support])
    assert {:ok, %{kind: :action}} = Jido.Executable.resolve(profile.instructions)

    deadline = System.monotonic_time(:millisecond) + 1_000

    assert {:ok, resolved} =
             Jido.AI.Instructions.resolve(
               profile,
               %{query: "refund"},
               %{tenant: "acme"},
               deadline
             )

    assert resolved.instructions == "acme: refund"

    [tool] = profile.tools
    assert tool.name == "echo"
    assert {:ok, %{kind: :action}} = Jido.Executable.resolve(tool.target)
    assert {:ok, %{value: "hello"}} = Jido.Exec.run(tool.target, %{value: "hello"}, %{})
  end

  test "the route helper creates a static extension reference" do
    assert %Jido.AI.Authoring.Ref{id: :support} = Jido.AI.DSL.Macros.ai(:support)
  end
end
