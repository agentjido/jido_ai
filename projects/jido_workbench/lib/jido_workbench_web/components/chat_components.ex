defmodule JidoWorkbenchWeb.ChatComponents do
  use Phoenix.Component
  import JidoWorkbenchWeb.CoreComponents
  import PetalComponents.Icon
  import PetalComponents.Avatar
  alias Jido.Chat.Message

  attr :messages, :list, required: true
  attr :is_typing, :boolean, default: false
  attr :class, :string, default: nil
  slot :input_form

  def chat_container(assigns) do
    ~H"""
    <div class={["flex flex-col h-[85vh] bg-white dark:bg-secondary-900 rounded-lg shadow-lg", @class]}>
      <.chat_header />
      <.messages_container messages={@messages} is_typing={@is_typing} />
      <div class="p-4 border-t border-secondary-200 dark:border-secondary-700">
        {render_slot(@input_form)}
      </div>
    </div>
    """
  end

  def chat_header(assigns) do
    ~H"""
    <div class="px-6 py-4 border-b border-secondary-200 dark:border-secondary-700">
      <div class="flex items-center justify-between">
        <div class="flex items-center space-x-4">
          <div class="h-10 w-10 rounded-full bg-primary-500 flex items-center justify-center">
            <span class="text-white dark:text-secondary-900 font-semibold text-lg">J</span>
          </div>
          <div>
            <h2 class="text-xl font-bold text-secondary-900 dark:text-secondary-100">
              Chat with Agent Jido
            </h2>
            <div class="flex items-center">
              <div class="relative h-2 w-2 mr-2">
                <span class="absolute inline-flex h-2 w-2 rounded-full bg-success-500 opacity-75 animate-ping"></span>
              </div>
              <span class="text-sm text-secondary-500 dark:text-secondary-400">Online</span>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :messages, :list, required: true
  attr :is_typing, :boolean, default: false

  def messages_container(assigns) do
    ~H"""
    <div id="messages-container" phx-hook="ScrollBottom" class="flex-1 overflow-y-auto px-6 py-4 space-y-4">
      <%= for message <- @messages do %>
        <.message_item message={message} />
      <% end %>
      <.typing_indicator :if={@is_typing} />
    </div>
    """
  end

  attr :message, :any, required: true

  def message_item(%{message: message} = assigns) when message.type == :system do
    ~H"""
    <div class="flex justify-center">
      <div class="text-xs text-secondary-500 dark:text-secondary-400 italic px-4 py-1">
        {Phoenix.HTML.raw(format_line_breaks(Message.content(@message)))}
      </div>
    </div>
    """
  end

  def message_item(%{message: message} = assigns) do
    ~H"""
    <div class={message_justify_class(Message.sender_id(@message))}>
      <div class={"flex max-w-[70%] gap-3 #{message_flex_direction(Message.sender_id(@message))}"}>
        <div class="flex-shrink-0">
          <.avatar name={get_participant_name(Message.sender_id(@message))} random_color />
        </div>
        <div class="flex flex-col">
          <div class={message_header_class(Message.sender_id(@message))}>
            {get_participant_name(Message.sender_id(@message))}
          </div>
          <.message_content
            type={Message.type(@message)}
            content={Message.content(@message)}
            payload={Message.payload(@message)}
            sender_id={Message.sender_id(@message)}
          />
        </div>
      </div>
    </div>
    """
  end

  attr :type, :atom, required: true
  attr :content, :string, required: true
  attr :payload, :map, default: nil
  attr :sender_id, :string, required: true

  def message_content(%{type: :rich} = assigns) do
    ~H"""
    <div class={message_content_class(@sender_id)}>
      <div>
        {Phoenix.HTML.raw(format_line_breaks(@content))}
        <%= if @payload do %>
          <div class="mt-2 p-2 bg-secondary-100 dark:bg-secondary-700 rounded">
            <%= case @payload do %>
              <% %{url: url} -> %>
                <a href={url} target="_blank" class="text-info-600 dark:text-info-400 hover:underline">
                  {url}
                </a>
              <% _ -> %>
                <pre class="text-sm overflow-x-auto">{inspect(@payload, pretty: true)}</pre>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  def message_content(assigns) do
    ~H"""
    <div class={message_content_class(@sender_id)}>
      {Phoenix.HTML.raw(format_line_breaks(@content))}
    </div>
    """
  end

  def typing_indicator(assigns) do
    ~H"""
    <div class="flex justify-start">
      <div class="flex max-w-[70%] gap-3">
        <div class="flex-shrink-0">
          <.avatar name={get_participant_name("jido")} random_color />
        </div>
        <div class="flex flex-col">
          <div class={message_header_class("jido")}>
            {get_participant_name("jido")}
          </div>
          <div class="rounded-2xl max-w-prose break-words bg-secondary-100 dark:bg-secondary-800 text-secondary-900 dark:text-secondary-100 rounded-tl-none">
            <div class="flex items-center space-x-2 px-4 py-4">
              <div class="w-2 h-2 rounded-full bg-secondary-400 animate-bounce" style="animation-delay: 0ms"></div>
              <div class="w-2 h-2 rounded-full bg-secondary-400 animate-bounce" style="animation-delay: 150ms"></div>
              <div class="w-2 h-2 rounded-full bg-secondary-400 animate-bounce" style="animation-delay: 300ms"></div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Helper functions
  defp message_justify_class(sender_id) when sender_id == "operator", do: "flex justify-end"
  defp message_justify_class(_), do: "flex justify-start"

  defp message_flex_direction(sender_id) when sender_id == "operator", do: "flex-row-reverse"
  defp message_flex_direction(_), do: "flex-row"

  defp message_header_class(sender_id) when sender_id == "operator",
    do: "text-sm text-secondary-500 dark:text-secondary-400 text-right mb-1"

  defp message_header_class(_), do: "text-sm text-secondary-500 dark:text-secondary-400 mb-1"

  defp message_content_class(sender_id) when sender_id == "operator",
    do: "rounded-2xl max-w-prose break-words bg-primary-500 text-white dark:text-secondary-900 px-4 py-2 rounded-tr-none"

  defp message_content_class(_),
    do:
      "rounded-2xl max-w-prose break-words bg-secondary-100 dark:bg-secondary-800 text-secondary-900 dark:text-secondary-100 px-4 py-2 rounded-tl-none"

  defp format_line_breaks(content) when is_binary(content) do
    String.replace(content, "\n", "<br>")
  end

  defp format_line_breaks(content), do: content

  defp get_participant_name("operator"), do: "Operator"
  defp get_participant_name("jido"), do: "Agent Jido"
  defp get_participant_name(name), do: name
end
