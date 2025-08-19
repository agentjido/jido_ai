# defmodule JidoWorkbenchWeb.JidoLive do
#   use JidoWorkbenchWeb, :live_view
#   import JidoWorkbenchWeb.WorkbenchLayout
#   alias JidoWorkbench.AgentJido
#   alias Jido.Chat.{Message, Participant, Room}
#   alias Jido.Chat
#   require Logger

#   @agent_id Application.compile_env(:jido_workbench, [:agent_jido, :agent_id])
#   @room_id Application.compile_env(:jido_workbench, [:agent_jido, :room_id])

#   @impl true
#   def mount(_params, _session, socket) do
#     participant_opts = [
#       display_name: "Operator",
#       type: :human,
#       # Dispatch chat messages back to this LiveView process
#       dispatch: {:pid, target: self()}
#     ]

#     with {:ok, operator} = Chat.participant("operator", participant_opts),
#          :ok <- Chat.join(@room_id, operator) do
#       message =
#         Message.new!(%{
#           sender: operator.id,
#           type: Message.type(:join),
#           content: "Operator has joined the room"
#         })

#       Chat.post_message(@room_id, message)

#       # Get existing messages
#       {:ok, messages} = Chat.get_messages(@room_id)

#       {:ok,
#        assign(socket,
#          room_id: @room_id,
#          agent: @agent_id,
#          operator: operator,
#          messages: messages,
#          is_typing: false,
#          response_ref: nil
#        )}
#     else
#       {:error, reason} ->
#         Logger.error("Chat room #{@room_id} not found: #{inspect(reason)}")

#         socket =
#           socket
#           |> put_flash(:error, "Chat system not available")
#           |> redirect(to: ~p"/")

#         {:ok, socket}
#     end
#   end

#   @impl true
#   def terminate(_reason, socket) do
#     # Create leave message
#     message =
#       Message.new!(%{
#         sender: socket.assigns.operator.id,
#         type: Message.type(:leave),
#         content: "Operator has left the room"
#       })

#     Chat.post_message(@room_id, message)
#     Chat.leave(@room_id, socket.assigns.operator.id)

#     :ok
#   end

#   @impl true
#   def handle_event("send_message", %{"message" => ""}, socket), do: {:noreply, socket}

#   def handle_event("send_message", %{"message" => content}, socket) do
#     socket = add_user_message(socket, content)
#     process_chat_response(socket)
#   end

#   defp add_user_message(socket, content) do
#     message =
#       Message.new!(%{
#         sender: socket.assigns.operator.id,
#         type: Message.type(:message),
#         content: content
#       })

#     Chat.post_message(@room_id, message)

#     # Get updated messages
#     {:ok, messages} = Chat.get_messages(@room_id)

#     assign(socket,
#       messages: messages
#     )
#   end

#   defp process_chat_response(socket) do
#     # Set typing indicator before starting response
#     socket = assign(socket, is_typing: true)

#     # Format messages for the agent
#     history =
#       Enum.filter(socket.assigns.messages, fn msg ->
#         msg.type == Message.type(:message)
#       end)
#       |> Enum.map(fn msg ->
#         %{
#           role: if(msg.sender == socket.assigns.operator.id, do: "user", else: "assistant"),
#           content: msg.content
#         }
#       end)

#     # Start async task to get response
#     task =
#       Task.async(fn ->
#         AgentJido.chat_response(@agent_id, history)
#       end)

#     {:noreply, assign(socket, response_ref: task.ref)}
#   end

#   @impl true
#   def handle_info({ref, {:ok, response}}, %{assigns: %{response_ref: ref}} = socket) do
#     # Clean up task
#     Process.demonitor(ref, [:flush])

#     # Create and publish agent message
#     {:ok, message} =
#       Message.new(%{
#         type: Message.type(:message),
#         room_id: socket.assigns.room_id,
#         sender: "Agent Jido",
#         content: response,
#         timestamp: DateTime.utc_now()
#       })

#     # Publish the message
#     signal = Message.to_signal(message)
#     {:ok, _} = Jido.Signal.Bus.publish(socket.assigns.bus_pid, [signal])

#     # Get updated messages
#     {:ok, messages} = Chat.get_messages(@room_id)

#     {:noreply,
#      socket
#      |> assign(is_typing: false, response_ref: nil, messages: messages, history_index: 0)}
#   end

#   def handle_info({ref, {:error, reason}}, %{assigns: %{response_ref: ref}} = socket) do
#     # Clean up task
#     Process.demonitor(ref, [:flush])
#     Logger.error("Chat response failed: #{inspect(reason)}")

#     # Create and publish system message
#     {:ok, message} =
#       Message.new(%{
#         type: Message.type(:system),
#         room_id: socket.assigns.room_id,
#         sender: "System",
#         content: "Sorry, I encountered an error. Please try again in a moment.",
#         timestamp: DateTime.utc_now()
#       })

#     # Publish the message
#     signal = Message.to_signal(message)
#     {:ok, _} = Jido.Signal.Bus.publish(socket.assigns.bus_pid, [signal])

#     # Get updated messages
#     {:ok, messages} = Jido.Chat.Room.get_messages(socket.assigns.room_id)

#     {:noreply,
#      socket
#      |> assign(is_typing: false, response_ref: nil, messages: messages, history_index: 0)}
#   end

#   # Handle task crash
#   def handle_info({:DOWN, ref, :process, _pid, reason}, %{assigns: %{response_ref: ref}} = socket) do
#     Logger.error("Chat response task crashed: #{inspect(reason)}")

#     # Create and publish system message
#     {:ok, message} =
#       Message.new(%{
#         type: Message.type(:system),
#         room_id: socket.assigns.room_id,
#         sender: "System",
#         content: "Sorry, something went wrong. Please try again in a moment.",
#         timestamp: DateTime.utc_now()
#       })

#     # Publish the message
#     signal = Message.to_signal(message)
#     {:ok, _} = Jido.Signal.Bus.publish(socket.assigns.bus_pid, [signal])

#     # Get updated messages
#     {:ok, messages} = Jido.Chat.Room.get_messages(socket.assigns.room_id)

#     {:noreply,
#      socket
#      |> assign(is_typing: false, response_ref: nil, messages: messages, history_index: 0)}
#   end

#   # Handle incoming chat signals
#   def handle_info({:signal, %{type: "chat.message", data: data}}, socket) do
#     # Refresh messages when a new message is received
#     {:ok, messages} = Jido.Chat.Room.get_messages(socket.assigns.room_id)
#     {:noreply, assign(socket, messages: messages)}
#   end

#   # Ignore other signals
#   def handle_info({:signal, _}, socket), do: {:noreply, socket}

#   # Helper functions for message type checking
#   def is_system_message(message) do
#     message.type == Message.type(:system)
#   end

#   def is_rich_message(message) do
#     message.type == Message.type(:rich)
#   end

#   defp format_line_breaks(content) do
#     String.replace(content, "\n", "<br>")
#   end

#   defp get_participant_name(participant_id) do
#     case participant_id do
#       "Operator" -> "Operator"
#       "Agent Jido" -> "Agent Jido"
#       "System" -> "System"
#       _ -> participant_id
#     end
#   end

#   defp message_justify_class(sender) do
#     if sender == "Operator", do: "flex justify-end", else: "flex justify-start"
#   end

#   defp message_flex_direction(sender) do
#     if sender == "Operator", do: "flex-row-reverse", else: ""
#   end

#   defp message_header_class(sender) do
#     base_class = "text-sm text-gray-500 dark:text-gray-400 mb-1 "
#     if sender == "Operator", do: base_class <> "text-right", else: base_class
#   end

#   defp message_content_class(sender) do
#     base_class = "rounded-2xl px-4 py-2 max-w-prose break-words "

#     if sender == "Operator" do
#       base_class <> "bg-lime-500 text-zinc-900 rounded-tr-none"
#     else
#       base_class <> "bg-zinc-800 text-gray-100 rounded-tl-none"
#     end
#   end
# end
