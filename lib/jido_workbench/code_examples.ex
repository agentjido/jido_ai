defmodule JidoWorkbench.CodeExamples do
  defmodule Example do
    defstruct [:id, :title, :content, :livebook_url]
  end

  def hero_example do
    %Example{
      id: :weather_agent,
      title: "Weather Agent Example",
      content: """
      defmodule WeatherAgent do
        use Jido.Agent, name: "weather_agent"

        def start_link(_opts \\\\ []) do
          Jido.AI.Agent.start_link(
            agent: __MODULE__,
            ai: [
              model: {:openai, model: "gpt-4o-mini"},
              prompt: \"""
              You are an enthusiastic weather reporter.
              <%= @message %>
              \""",
              tools: [
                Jido.Tools.Weather
              ]
            ]
          )
        end

        defdelegate chat_response(pid, message), to: Jido.AI.Agent
        defdelegate tool_response(pid, message), to: Jido.AI.Agent
      end

      iex(1)> {:ok, pid} = WeatherAgent.start_link()
      {:ok, #PID<0.123.0>}

      iex(2)> WeatherAgent.tool_response(pid, "What is the weather in Tokyo?")
      {:ok, "The weather in Tokyo is sunny with a temperature of 20 degrees Celsius."}
      """,
      livebook_url:
        "https://raw.githubusercontent.com/agentjido/jido_workbench/refs/heads/main/priv/documentation/cookbook/weather-tool-response.livemd"
    }
  end

  def action_example do
    %Example{
      id: :create_invoice_action,
      title: "Action Example",
      content: """
      defmodule CreateInvoice do
        use Jido.Action, name: "create_invoice"

        def run(%{customer_id: id, amount: amount}, _ctx) do
          with {:ok, invoice} <- BillingSystem.create_invoice(id, amount),
               {:ok, _} <- NotificationSystem.notify(:invoice_created, invoice) do
            {:ok, %{invoice_id: invoice.id}}
          end
        end
      end
      """,
      livebook_url: ""
    }
  end

  def agent_example do
    %Example{
      id: :customer_support_agent,
      title: "Customer Support Agent Example",
      content: """
      defmodule CustomerSupportAgent do
        use Jido.Agent, name: "support_agent"

        def start_link(opts \\\\ []) do
          Agent.start_link(
            agent: __MODULE__,
            ai: [
              model: {:openai, model: "gpt-4o-mini"},
              prompt: "You help customers solve product issues."
            ],
            tools: [
              Jido.Tools.KnowledgeBase,
              Jido.Tools.TicketSystem
            ]
          )
        end
      end
      """,
      livebook_url: ""
    }
  end

  def signal_example do
    %Example{
      id: :signal_dispatch,
      title: "Signal Example",
      content: """
      {:ok, signal} = Jido.Signal.new(%{
        type: "order.payment.processed",
        source: "/payments",
        data: %{order_id: "456"},
        jido_dispatch: [
          {:pubsub, [topic: "transactions"]},
          {:bus, [target: :audit_bus]},
          {:pid, [target: pid, async: true]}
        ]
      })
      """,
      livebook_url: ""
    }
  end

  def skill_example do
    %Example{
      id: :data_analysis_skill,
      title: "Skill Example",
      content: """
      defmodule Jido.Skills.DataAnalysis do
        use Jido.Skill, name: "data_analysis"

        def mount(agents, opts \\\\ []) do
          Jido.Agent.register_action(agent, [analyze_trends])
        end

        def router(opts \\\\ []) do
          [
            {"jido.data_analysis.analyze",
              %Instruction{
                action: Jido.DataAnalysis.Actions.AnalyzeTrends,
                params: %{model: model}
              }},
          ]
        end

        def handle_signal(%{type: "data.analysis.analyze"} = signal, _skill_opts) do
          {:ok, signal}
        end

        def transform_result(signal, result, _skill_opts) do
          {:ok, result}
        end
      end
      """,
      livebook_url: ""
    }
  end
end
