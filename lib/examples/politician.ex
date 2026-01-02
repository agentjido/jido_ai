defmodule JidoAi.Examples.Politician do
  defmodule Schema do
    use Ecto.Schema
    use Instructor

    @llm_doc """
    A description of United States Politicians and the offices that they held,

    ## Fields:
    - first_name: Their first name
    - last_name: Their last name
    - offices_held:
      - office: The branch and position in government they served in
      - from_date: When they entered office or null
      - until_date: The date they left office or null
    """
    @primary_key false
    embedded_schema do
      field(:first_name, :string)
      field(:last_name, :string)

      embeds_many :offices_held, Office, primary_key: false do
        field(:office, Ecto.Enum,
          values: [:president, :vice_president, :governor, :congress, :senate]
        )

        field(:from_date, :date)
        field(:to_date, :date)
      end
    end
  end

  use Jido.Action,
    name: "politician",
    description: "A description of United States Politicians and the offices that they held",
    schema: [
      query: [type: :string, required: true, doc: "The query to search for"]
    ]

  def run(params, _context) do
    JidoAi.Actions.Anthropic.ChatCompletion.run(
      %{
        model: "claude-3-5-haiku-latest",
        messages: [
          %{
            role: "user",
            content: params.query
          }
        ],
        response_model: Schema,
        temperature: 0.5,
        max_tokens: 1000
      },
      %{}
    )
    |> case do
      {:ok, %{result: politician}} -> {:ok, %{result: politician}}
      {:error, reason} -> {:error, reason}
    end
  end
end
