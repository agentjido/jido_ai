defmodule Jido.Dialogue.CharacterServer do
  use GenServer

  # Client API

  def start_link(opts) do
    conversation_id = Keyword.fetch!(opts, :conversation_id)
    name = Keyword.fetch!(opts, :name)
    config = Keyword.fetch!(opts, :config)

    GenServer.start_link(__MODULE__, %{
      conversation_id: conversation_id,
      name: name,
      config: config,
      memory: []
    })
  end

  def handle_message(pid, message) do
    GenServer.call(pid, {:handle_message, message})
  end

  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  # Server Callbacks

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_call({:handle_message, message}, _from, state) do
    # Add message to memory first
    new_state = update_memory(state, message)

    # Generate response using updated memory and context
    {:ok, response} = generate_response(message, new_state)

    {:reply, {:ok, response}, new_state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  # Private Functions

  defp update_memory(state, message) do
    # Keep last 10 messages in memory
    new_memory = Enum.take([message | state.memory], 10)
    %{state | memory: new_memory}
  end

  defp generate_response(%{content: "What's my name?"} = message, state) do
    case message do
      %{context: %{user_name: name}} ->
        {:ok, "Your name is #{name}."}

      _ ->
        # Try to find name in memory if not in context
        case find_name_in_memory(state.memory) do
          {:ok, name} -> {:ok, "Your name is #{name}."}
          :error -> {:ok, "I'm not sure what your name is yet."}
        end
    end
  end

  defp generate_response(%{content: content, context: context}, state) do
    # Use memory to enhance responses
    recent_topics = extract_topics(state.memory)

    response =
      case context do
        %{user_name: name} ->
          base = "Hello #{name}, I'm #{state.name}, #{state.config.role}."

          topics =
            if recent_topics != [],
              do: " I see we were discussing #{Enum.join(recent_topics, ", ")}.",
              else: ""

          base <> topics <> " " <> content

        _ ->
          base = "Hello, I'm #{state.name}, #{state.config.role}."

          topics =
            if recent_topics != [],
              do: " We were discussing #{Enum.join(recent_topics, ", ")}.",
              else: ""

          base <> topics <> " " <> content
      end

    {:ok, response}
  end

  defp generate_response(%{content: content}, state) do
    # Use memory to enhance responses even without context
    recent_topics = extract_topics(state.memory)

    base = "Hello, I'm #{state.name}, #{state.config.role}."

    topics =
      if recent_topics != [],
        do: " We were discussing #{Enum.join(recent_topics, ", ")}.",
        else: ""

    response = base <> topics <> " " <> content

    {:ok, response}
  end

  defp find_name_in_memory(memory) do
    case Enum.find(memory, fn msg ->
           msg.speaker == "user" and String.match?(msg.content, ~r/My name is (\w+)/i)
         end) do
      nil ->
        :error

      message ->
        [_, name] = Regex.run(~r/My name is (\w+)/i, message.content)
        {:ok, name}
    end
  end

  defp extract_topics(memory) do
    memory
    # Look at last 5 messages
    |> Enum.take(5)
    |> Enum.map(& &1.content)
    |> Enum.flat_map(fn content ->
      # Simple topic extraction - look for nouns/key terms
      # This could be enhanced with NLP in a real implementation
      Regex.scan(~r/\b(help|technical|question|problem|issue|error)\b/i, content)
      |> Enum.map(fn [match | _] -> String.downcase(match) end)
    end)
    |> Enum.uniq()
  end
end
