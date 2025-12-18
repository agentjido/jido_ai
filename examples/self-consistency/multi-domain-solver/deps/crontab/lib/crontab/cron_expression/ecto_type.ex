if match?({:module, Ecto.Type}, Code.ensure_compiled(Ecto.Type)) do
  defmodule Crontab.CronExpression.Ecto.Type do
    @moduledoc """
    Provides a type for Ecto usage.

    The underlying data type should be a map.

    ## Migration Example

        create table(:my_table) do
          add :schedule, :map
        end

    ## Schema Example

        schema "my_table" do
          field :schedule, Crontab.CronExpression.Ecto.Type
        end

    ## Casted Values

    It is recommended to only pass `Crontab.CronExpression` structs to the
    field.

    The type will automatically cast the string representation to a
    `Crontab.CronExpression` struct. This will however only work for normal
    (not extended) expressions since the string representation of extended
    expressions can't be disambiguated from normal expressions.

    """

    @behaviour Ecto.Type

    alias Crontab.CronExpression
    alias Crontab.CronExpression.Composer
    alias Crontab.CronExpression.Parser

    @doc false
    @impl Ecto.Type
    @spec type :: :map
    def type, do: :map

    @doc false
    @impl Ecto.Type
    @spec cast(any) :: {:ok, CronExpression.t()} | :error
    def cast(%CronExpression{} = cron_expression), do: {:ok, cron_expression}

    def cast(cron_expression) when is_binary(cron_expression) do
      cron_expression
      |> String.trim()
      |> Parser.parse()
      |> case do
        result = {:ok, _} -> result
        _ -> :error
      end
    end

    def cast(_), do: :error

    @doc false
    @impl Ecto.Type
    @spec load(any) :: {:ok, CronExpression.t()} | :error
    def load(%{"extended" => extended, "expression" => expression} = term) do
      load(%{
        extended: extended,
        expression: expression,
        prior: Map.get(term, "prior", false),
        subsequent: Map.get(term, "subsequent", false)
      })
    end

    def load(%{extended: extended, expression: expression} = term) do
      ambiguity_opts =
        Enum.reject(
          [
            if(term[:prior], do: :prior),
            if(term[:subsequent], do: :subsequent)
          ],
          &is_nil/1
        )

      case Parser.parse(expression, extended, ambiguity_opts) do
        {:ok, _} = result -> result
        _ -> :error
      end
    end

    def load(_), do: :error

    @doc false
    @impl Ecto.Type
    @spec dump(any) :: {:ok, CronExpression.t()} | :error
    def dump(%CronExpression{extended: extended} = cron_expression) do
      {:ok,
       %{
         extended: extended,
         expression: Composer.compose(cron_expression),
         prior: :prior in cron_expression.on_ambiguity,
         subsequent: :subsequent in cron_expression.on_ambiguity
       }}
    end

    @doc false
    @impl Ecto.Type
    def dump(_), do: :error

    @doc false
    @impl Ecto.Type
    def embed_as(_), do: :dump

    @doc false
    @impl Ecto.Type
    def equal?(term1, term2), do: term1 == term2
  end
end
