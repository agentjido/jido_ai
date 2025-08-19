# defmodule JidoAI.PlaygroundLive do
#   use Phoenix.LiveView

#   alias Jido.AI.{CostCalculator, Keyring, Message, TokenCounter}

#   @default_model "openrouter:openai/gpt-oss-20b:free"

#   def mount(_params, _session, socket) do
#     IO.puts("🔧 PlaygroundLive mounting...")

#     providers = Jido.AI.Provider.Registry.list_providers() |> sort_alphabetically()
#     IO.puts("🔧 Found #{length(providers)} providers: #{inspect(providers)}")

#     default_provider = :openrouter
#     available_models = get_models_for_provider(default_provider) |> sort_models_alphabetically()
#     IO.puts("🔧 Found #{length(available_models)} models for #{default_provider}")

#     # Set a test API key for openrouter if none exists
#     if Jido.AI.config([default_provider, :api_key]) == nil do
#       IO.puts("🔧 Setting test API key for openrouter")
#       Keyring.set_session_value(:openrouter_api_key, "sk-or-v1-test123456789")
#     end

#     # Check API key availability
#     api_key_status = check_api_keys(providers)
#     IO.puts("🔧 API Key Status: #{inspect(api_key_status)}")

#     # Find the default model in the available models
#     default_model = "openai/gpt-oss-20b"

#     auto_selected_model =
#       if Enum.any?(available_models, fn {model_id, _model} -> model_id == default_model end) do
#         IO.puts("🔧 Auto-selecting default model: #{default_model}")
#         default_model
#       else
#         first_model_tuple = List.first(available_models)

#         first_model_id =
#           case first_model_tuple do
#             {model_id, _} -> model_id
#             _ -> default_model
#           end

#         IO.puts("🔧 Default model not found, using first available: #{first_model_id}")
#         first_model_id
#       end

#     {:ok,
#      assign(socket,
#        # Tabs and UI
#        active_tab: :text_generation,

#        # Provider & Model
#        providers: providers,
#        selected_provider: default_provider,
#        available_models: available_models,
#        selected_model: auto_selected_model,
#        model_spec: @default_model,
#        api_key_status: api_key_status,

#        # Text Generation
#        messages: [],
#        input: "",
#        loading: false,
#        current_assistant_id: nil,

#        # Generation Options
#        temperature: 0.7,
#        max_tokens: 1000,
#        system_prompt: "You are a helpful assistant.",

#        # Structured Data
#        schema_input:
#          "name: [type: :string, required: true],\nage: [type: :integer, default: 25],\nemail: [type: :string, required: true]",
#        output_type: :object,
#        structured_result: nil,

#        # Message Builder
#        message_mode: :simple,
#        current_messages: [],

#        # Metrics
#        total_input_tokens: 0,
#        total_output_tokens: 0,
#        total_cost: 0.0,
#        api_calls: 0,
#        session_start: System.system_time(:millisecond),
#        current_request_cost: nil
#      )}
#   end

#   def render(assigns) do
#     ~H"""
#     <!DOCTYPE html>
#     <html lang="en" class="dark">
#     <head>
#       <meta charset="UTF-8">
#       <meta name="viewport" content="width=device-width, initial-scale=1.0">
#       <title>Jido AI Playground</title>
#       <script src="https://cdn.tailwindcss.com"></script>
#       <script>
#         tailwind.config = {
#           darkMode: 'class',
#           theme: {
#             extend: {
#               colors: {
#                 github: {
#                   canvas: '#0d1117',
#                   secondary: '#161b22',
#                   tertiary: '#21262d',
#                   border: '#30363d',
#                   text: '#f0f6fc',
#                   muted: '#8b949e',
#                   accent: '#58a6ff',
#                   success: '#238636',
#                   danger: '#da3633'
#                 }
#               }
#             }
#           }
#         }
#       </script>
#     </head>
#     <body class="bg-github-canvas text-github-text h-screen overflow-hidden">
#       <div class="h-screen flex flex-col">
#         <!-- Header -->
#         <header class="bg-github-secondary border-b border-github-border px-5 py-3 flex justify-between items-center flex-shrink-0">
#           <div class="flex items-center gap-3">
#             <div class="flex items-center gap-2">
#               <span class="text-github-accent font-mono text-lg font-bold">></span>
#               <span class="text-base font-semibold">Jido AI Playground</span>
#             </div>
#             <div class="bg-blue-600 text-white px-2 py-1 rounded-xl text-xs font-medium">
#               Developer Testing Interface
#             </div>
#           </div>
#           <div class="flex items-center gap-3">
#             <span class="text-github-muted text-sm"><%= @api_calls %> messages</span>
#             <button class="bg-github-danger text-white px-3 py-1.5 rounded-md text-xs hover:bg-red-700 transition-colors" phx-click="reset_session">
#               Reset All
#             </button>
#           </div>
#         </header>

#         <!-- Tab Navigation -->
#         <nav class="bg-github-secondary border-b border-github-border px-5 flex gap-0 flex-shrink-0">
#           <button
#             class={"text-github-muted px-4 py-3 text-sm flex items-center gap-1.5 border-b-2 border-transparent transition-all hover:text-github-text " <> if(@active_tab == :text_generation, do: "text-github-accent border-github-accent", else: "")}
#             phx-click="switch_tab"
#             phx-value-tab="text_generation"
#           >
#             <span class="text-base">💬</span>
#             Text Generation
#           </button>
#           <button
#             class={"text-github-muted px-4 py-3 text-sm flex items-center gap-1.5 border-b-2 border-transparent transition-all hover:text-github-text " <> if(@active_tab == :structured_data, do: "text-github-accent border-github-accent", else: "")}
#             phx-click="switch_tab"
#             phx-value-tab="structured_data"
#           >
#             <span class="text-base">📊</span>
#             Structured Data
#           </button>
#           <button
#             class={"text-github-muted px-4 py-3 text-sm flex items-center gap-1.5 border-b-2 border-transparent transition-all hover:text-github-text " <> if(@active_tab == :message_builder, do: "text-github-accent border-github-accent", else: "")}
#             phx-click="switch_tab"
#             phx-value-tab="message_builder"
#           >
#             <span class="text-base">🔧</span>
#             Message Builder
#           </button>
#           <button
#             class={"text-github-muted px-4 py-3 text-sm flex items-center gap-1.5 border-b-2 border-transparent transition-all hover:text-github-text " <> if(@active_tab == :analytics, do: "text-github-accent border-github-accent", else: "")}
#             phx-click="switch_tab"
#             phx-value-tab="analytics"
#           >
#             <span class="text-base">📈</span>
#             Analytics
#           </button>
#         </nav>

#         <div class="flex flex-1 overflow-hidden">
#           <!-- Main Content -->
#           <div class="flex-1 p-5 overflow-y-auto bg-github-canvas border-r border-github-border">
#             <%= case @active_tab do %>
#               <% :text_generation -> %>
#                 <%= render_text_generation(assigns) %>
#               <% :structured_data -> %>
#                 <%= render_structured_data(assigns) %>
#               <% :message_builder -> %>
#                 <%= render_message_builder(assigns) %>
#               <% :analytics -> %>
#                 <%= render_analytics(assigns) %>
#             <% end %>
#           </div>

#           <!-- Sidebar -->
#           <div class="w-80 bg-github-secondary p-5 overflow-y-auto border-l border-github-border">
#             <%= render_sidebar(assigns) %>
#           </div>
#         </div>
#       </div>
#     </body>
#     </html>

#     <style>
#       .valid { border-color: #238636 !important; }
#       .invalid { border-color: #da3633 !important; }

#       /* Custom scrollbar for webkit browsers */
#       ::-webkit-scrollbar { width: 8px; }
#       ::-webkit-scrollbar-track { background: #21262d; }
#       ::-webkit-scrollbar-thumb { background: #30363d; border-radius: 4px; }
#       ::-webkit-scrollbar-thumb:hover { background: #484f58; }

#       /* Spinner animation */
#       @keyframes spin { to { transform: rotate(360deg); } }
#       .spinner {
#         display: inline-block; width: 12px; height: 12px;
#         border: 2px solid #30363d; border-radius: 50%;
#         border-top-color: #58a6ff; animation: spin 1s ease-in-out infinite;
#       }
#     </style>

#     <script>
#       // Auto-scroll chat to bottom on new messages
#       window.addEventListener("phx:stream_chunk", () => {
#         const chatContainer = document.getElementById("chat");
#         if (chatContainer) {
#           chatContainer.scrollTop = chatContainer.scrollHeight;
#         }
#       });

#       // Auto-scroll on page updates (for message additions)
#       document.addEventListener("DOMContentLoaded", () => {
#         const observer = new MutationObserver(() => {
#           const chatContainer = document.getElementById("chat");
#           if (chatContainer) {
#             chatContainer.scrollTop = chatContainer.scrollHeight;
#           }
#         });

#         const chatContainer = document.getElementById("chat");
#         if (chatContainer) {
#           observer.observe(chatContainer, { childList: true, subtree: true });
#         }
#       });
#     </script>
#     """
#   end

#   # Tab Content Renderers
#   defp render_text_generation(assigns) do
#     ~H"""
#     <div class="h-full flex flex-col">
#       <div class="mb-5 pb-3 border-b border-github-border">
#         <h2 class="text-lg font-semibold text-github-text mb-1">Text Generation Hub</h2>
#         <p class="text-sm text-github-muted">Test your model configurations and prompts</p>
#       </div>

#       <div class="border border-github-border rounded-lg flex-1 overflow-y-auto p-4 mb-5 bg-github-canvas min-h-96 space-y-4" id="chat">
#         <%= if Enum.empty?(@messages) do %>
#           <div class="text-github-muted p-10 text-center">
#             <p class="mb-2">👋 Start a conversation with your AI model</p>
#             <p>Type a message below to begin testing</p>
#           </div>
#         <% else %>
#           <%= for message <- @messages do %>
#             <div class={"flex " <> if(message.role == "user", do: "justify-end", else: "justify-start")} id={"msg-" <> message.id}>
#               <div class={if message.role == "user" do
#                 "bg-blue-600 text-white px-4 py-3 rounded-lg rounded-br-md max-w-lg break-words"
#               else
#                 "bg-github-tertiary text-github-text px-4 py-3 rounded-lg rounded-bl-md max-w-lg break-words border border-github-border"
#               end}>
#                 <%= if message.role == "assistant" do %>
#                   <div class="prose prose-invert prose-sm max-w-none">
#                     <%= Phoenix.HTML.raw(format_markdown(message.content)) %>
#                   </div>
#                 <% else %>
#                   <%= message.content %>
#                 <% end %>
#               </div>
#             </div>
#           <% end %>
#         <% end %>
#       </div>

#       <form phx-submit="send_message" class="mt-auto">
#         <div class="flex gap-2.5">
#           <input
#             type="text"
#             name="message"
#             value={@input}
#             phx-change="input_change"
#             placeholder="Enter your prompt..."
#             disabled={@loading}
#             autofocus
#             class="flex-1 px-3 py-3 bg-github-tertiary border border-github-border rounded-md text-base text-github-text placeholder-github-muted focus:outline-none focus:border-github-accent focus:ring-2 focus:ring-github-accent/30"
#           />
#           <button type="submit" class="px-6 py-3 bg-github-success text-white rounded-md font-medium text-base transition-colors hover:bg-green-700 disabled:bg-gray-600 disabled:cursor-not-allowed flex items-center gap-2" disabled={@loading or @input == ""}>
#             <%= if @loading do %>
#               <span class="spinner"></span> Generating...
#             <% else %>
#               ✨ Generate
#             <% end %>
#           </button>
#         </div>
#       </form>
#     </div>
#     """
#   end

#   defp render_structured_data(assigns) do
#     ~H"""
#     <div class="h-full flex flex-col">
#       <div class="mb-5 pb-3 border-b border-github-border">
#         <h2 class="text-lg font-semibold text-github-text mb-1">Structured Data Sandbox</h2>
#         <p class="text-sm text-github-muted">Test schema validation and object generation</p>
#       </div>

#       <div class="grid grid-cols-1 lg:grid-cols-2 gap-5 flex-1">
#         <div class="flex flex-col">
#           <label class="text-github-muted text-sm font-medium mb-1.5">Schema Definition (NimbleOptions format)</label>
#           <textarea
#             class="bg-github-tertiary border border-github-border rounded-md p-3 font-mono text-sm text-github-text min-h-32 resize-y flex-1 focus:outline-none focus:border-github-accent focus:ring-2 focus:ring-github-accent/30"
#             name="value"
#             phx-change="update_schema"
#             phx-debounce="500"
#             placeholder="name: [type: :string, required: true],&#10;age: [type: :integer, default: 0]"
#           ><%= @schema_input %></textarea>

#           <div class="flex gap-3 my-4">
#             <button
#               class={"px-4 py-2 rounded-md text-sm transition-all " <> if(@output_type == :object, do: "bg-blue-600 text-white border-blue-600", else: "bg-github-tertiary text-github-muted border border-github-border hover:bg-github-border hover:text-github-text")}
#               phx-click="set_output_type"
#               phx-value-type="object"
#             >Object</button>
#             <button
#               class={"px-4 py-2 rounded-md text-sm transition-all " <> if(@output_type == :array, do: "bg-blue-600 text-white border-blue-600", else: "bg-github-tertiary text-github-muted border border-github-border hover:bg-github-border hover:text-github-text")}
#               phx-click="set_output_type"
#               phx-value-type="array"
#             >Array</button>
#             <button
#               class={"px-4 py-2 rounded-md text-sm transition-all " <> if(@output_type == :enum, do: "bg-blue-600 text-white border-blue-600", else: "bg-github-tertiary text-github-muted border border-github-border hover:bg-github-border hover:text-github-text")}
#               phx-click="set_output_type"
#               phx-value-type="enum"
#             >Enum</button>
#           </div>

#           <button class="px-6 py-3 bg-github-success text-white rounded-md font-medium transition-colors hover:bg-green-700 disabled:bg-gray-600 disabled:cursor-not-allowed" phx-click="generate_structured" disabled={@loading}>
#             <%= if @loading, do: "Generating...", else: "Generate Object" %>
#           </button>
#         </div>

#         <div class="flex flex-col">
#           <label class="text-github-muted text-sm font-medium mb-1.5">Generated Result</label>
#           <div class="bg-github-canvas border border-github-border rounded-md p-4 font-mono text-sm text-github-text min-h-48 whitespace-pre-wrap overflow-x-auto flex-1">
#             <%= if @structured_result do %>
#               <%= Jason.encode!(@structured_result, pretty: true) %>
#             <% else %>
#               <div class="text-github-muted p-5 text-center">
#                 <p class="mb-2">📊 Generated objects will appear here</p>
#                 <p>Configure your schema and click "Generate Object"</p>
#               </div>
#             <% end %>
#           </div>
#         </div>
#       </div>
#     </div>
#     """
#   end

#   defp render_message_builder(assigns) do
#     ~H"""
#     <div class="h-full flex flex-col">
#       <div class="mb-5 pb-3 border-b border-github-border">
#         <h2 class="text-lg font-semibold text-github-text mb-1">Message Builder</h2>
#         <p class="text-sm text-github-muted">Compose rich conversations with multi-modal content</p>
#       </div>

#       <div class="text-github-muted p-10 text-center">
#         <p>Coming soon - Rich message composition with image/file support</p>
#       </div>
#     </div>
#     """
#   end

#   defp render_analytics(assigns) do
#     ~H"""
#     <div class="h-full flex flex-col">
#       <div class="mb-5 pb-3 border-b border-github-border">
#         <h2 class="text-lg font-semibold text-github-text mb-1">Performance Analytics</h2>
#         <p class="text-sm text-github-muted">Monitor usage, costs, and performance metrics</p>
#       </div>

#       <div class="text-github-muted p-10 text-center">
#         <p>Coming soon - Real-time metrics and cost tracking</p>
#       </div>
#     </div>
#     """
#   end

#   defp render_sidebar(assigns) do
#     ~H"""
#     <div class="mb-6">
#       <h3 class="text-sm font-semibold text-github-text mb-3 flex items-center gap-1.5">
#         🤖 Provider & Model
#       </h3>

#       <div class="mb-4">
#         <div class="flex items-center justify-between mb-1.5">
#           <label class="text-github-muted text-xs font-medium">Provider</label>
#           <%= case Enum.find(@api_key_status, fn {p, _} -> p == @selected_provider end) do %>
#             <% {_, :available} -> %>
#               <span class="text-github-success text-xs">🔑 API Key OK</span>
#             <% {_, :missing} -> %>
#               <span class="text-github-danger text-xs">🔑 No API Key</span>
#             <% _ -> %>
#               <span class="text-github-muted text-xs">🔑 Unknown</span>
#           <% end %>
#         </div>
#         <form phx-change="change_provider">
#           <select name="value" class="w-full bg-github-tertiary border border-github-border text-github-text px-2.5 py-2 rounded-md text-xs cursor-pointer focus:outline-none focus:border-github-accent focus:ring-2 focus:ring-github-accent/30">
#             <%= for provider <- @providers do %>
#               <option value={provider} selected={provider == @selected_provider}>
#                 <%= provider |> to_string() |> String.capitalize() %>
#               </option>
#             <% end %>
#           </select>
#         </form>
#       </div>

#       <div class="mb-4">
#         <label class="text-github-muted text-xs font-medium mb-1.5 block">Model</label>
#         <form phx-change="change_model">
#           <select name="value" class="w-full bg-github-tertiary border border-github-border text-github-text px-2.5 py-2 rounded-md text-xs cursor-pointer focus:outline-none focus:border-github-accent focus:ring-2 focus:ring-github-accent/30">
#             <%= for {model_id, _model} <- @available_models do %>
#               <option value={model_id} selected={model_id == @selected_model}>
#                 <%= model_id %>
#               </option>
#             <% end %>
#           </select>
#         </form>
#       </div>
#     </div>

#     <div class="mb-6">
#       <h3 class="text-sm font-semibold text-github-text mb-3 flex items-center gap-1.5">
#         ⚙️ Generation Options
#       </h3>

#       <div class="mb-4">
#         <label class="text-github-muted text-xs font-medium mb-1.5 block">Temperature: <%= @temperature %></label>
#         <input
#           type="range"
#           class="w-full h-1.5 bg-github-border rounded-md appearance-none cursor-pointer slider"
#           name="value"
#           min="0"
#           max="2"
#           step="0.1"
#           value={@temperature}
#           phx-change="update_temperature"
#         />
#       </div>

#       <div class="mb-4">
#         <label class="text-github-muted text-xs font-medium mb-1.5 block">Max Tokens</label>
#         <input
#           type="number"
#           class="w-full bg-github-tertiary border border-github-border text-github-text px-2.5 py-2 rounded-md text-xs focus:outline-none focus:border-github-accent focus:ring-2 focus:ring-github-accent/30"
#           name="value"
#           value={@max_tokens}
#           phx-change="update_max_tokens"
#           min="1"
#           max="32000"
#         />
#       </div>

#       <div class="mb-4">
#         <label class="text-github-muted text-xs font-medium mb-1.5 block">System Prompt</label>
#         <textarea
#           class="w-full bg-github-tertiary border border-github-border text-github-text px-2.5 py-2 rounded-md text-xs resize-y min-h-15 focus:outline-none focus:border-github-accent focus:ring-2 focus:ring-github-accent/30"
#           name="value"
#           phx-change="update_system_prompt"
#           phx-debounce="300"
#           placeholder="You are a helpful assistant..."
#         ><%= @system_prompt %></textarea>
#       </div>
#     </div>

#     <div class="mb-6">
#       <h3 class="text-sm font-semibold text-github-text mb-3 flex items-center gap-1.5">
#         📊 Quick Metrics
#       </h3>
#       <div class="grid grid-cols-2 gap-3">
#         <div class="bg-github-tertiary p-3 rounded-md border border-github-border">
#           <div class="text-github-muted text-xs mb-1">Input Tokens</div>
#           <div class="text-github-text text-base font-semibold text-github-success"><%= @total_input_tokens %></div>
#         </div>
#         <div class="bg-github-tertiary p-3 rounded-md border border-github-border">
#           <div class="text-github-muted text-xs mb-1">Output Tokens</div>
#           <div class="text-github-text text-base font-semibold text-blue-400"><%= @total_output_tokens %></div>
#         </div>
#         <div class="bg-github-tertiary p-3 rounded-md border border-github-border">
#           <div class="text-github-muted text-xs mb-1">Total Cost</div>
#           <div class="text-github-text text-base font-semibold text-github-accent">$<%= :io_lib.format("~.6f", [@total_cost]) %></div>
#         </div>
#         <div class="bg-github-tertiary p-3 rounded-md border border-github-border">
#           <div class="text-github-muted text-xs mb-1">API Calls</div>
#           <div class="text-github-text text-base font-semibold text-orange-400"><%= @api_calls %></div>
#         </div>
#       </div>

#       <%= if @current_request_cost do %>
#         <div class="mt-3 bg-github-tertiary p-3 rounded-md border border-github-border">
#           <div class="text-github-muted text-xs mb-1">Last Request</div>
#           <div class="text-github-text text-sm">
#             <%= CostCalculator.format_cost(@current_request_cost) %>
#           </div>
#         </div>
#       <% end %>
#     </div>

#     <div class="mt-auto">
#       <h3 class="text-sm font-semibold text-github-text mb-3 flex items-center gap-1.5">
#         🛠️ Developer Tools
#       </h3>
#       <button class="w-full bg-github-tertiary border border-github-border text-github-text px-2.5 py-2.5 rounded-md cursor-pointer mb-2 text-xs text-left transition-colors hover:bg-github-border" phx-click="export_session">Export Session</button>
#       <button class="w-full bg-github-tertiary border border-github-border text-github-text px-2.5 py-2.5 rounded-md cursor-pointer mb-2 text-xs text-left transition-colors hover:bg-github-border" phx-click="generate_code">Generate Code</button>
#       <button class="w-full bg-red-600 border border-red-500 text-white px-2.5 py-2.5 rounded-md cursor-pointer mb-2 text-xs text-left transition-colors hover:bg-red-700" phx-click="reset_metrics">Reset Metrics</button>
#       <button class="w-full bg-github-tertiary border border-github-border text-github-text px-2.5 py-2.5 rounded-md cursor-pointer mb-2 text-xs text-left transition-colors hover:bg-github-border" phx-click="view_raw_response">View Raw Response</button>
#     </div>
#     """
#   end

#   # Event Handlers
#   def handle_event("switch_tab", %{"tab" => tab}, socket) do
#     {:noreply, assign(socket, active_tab: String.to_atom(tab))}
#   end

#   def handle_event("reset_session", _params, socket) do
#     {:noreply,
#      assign(socket,
#        messages: [],
#        input: "",
#        loading: false,
#        current_assistant_id: nil,
#        total_input_tokens: 0,
#        total_output_tokens: 0,
#        total_cost: 0.0,
#        api_calls: 0,
#        current_request_cost: nil,
#        structured_result: nil
#      )}
#   end

#   def handle_event("reset_metrics", _params, socket) do
#     IO.puts("🔧 Resetting metrics...")

#     {:noreply,
#      assign(socket,
#        total_input_tokens: 0,
#        total_output_tokens: 0,
#        total_cost: 0.0,
#        api_calls: 0,
#        current_request_cost: nil
#      )}
#   end

#   def handle_event("update_temperature", params, socket) do
#     temp = params["value"] || params["temperature"]
#     {temp_float, _} = Float.parse(temp)
#     {:noreply, assign(socket, temperature: temp_float)}
#   end

#   def handle_event("update_max_tokens", params, socket) do
#     tokens = params["value"] || params["max_tokens"]
#     {tokens_int, _} = Integer.parse(tokens)
#     {:noreply, assign(socket, max_tokens: tokens_int)}
#   end

#   def handle_event("update_system_prompt", params, socket) do
#     prompt = params["value"] || params["system_prompt"]
#     {:noreply, assign(socket, system_prompt: prompt)}
#   end

#   def handle_event("update_schema", params, socket) do
#     schema = params["value"] || params["schema"]
#     {:noreply, assign(socket, schema_input: schema)}
#   end

#   def handle_event("set_output_type", %{"type" => type}, socket) do
#     {:noreply, assign(socket, output_type: String.to_atom(type))}
#   end

#   def handle_event("generate_structured", _params, socket) do
#     if socket.assigns.schema_input == "" do
#       {:noreply, socket}
#     else
#       live_view_pid = self()
#       model_spec = socket.assigns.model_spec
#       schema_input = socket.assigns.schema_input
#       output_type = socket.assigns.output_type
#       system_prompt = socket.assigns.system_prompt

#       spawn(fn ->
#         generate_structured_data(live_view_pid, model_spec, schema_input, output_type, system_prompt)
#       end)

#       {:noreply, assign(socket, loading: true, structured_result: nil)}
#     end
#   end

#   def handle_event("input_change", %{"message" => message}, socket) do
#     {:noreply, assign(socket, input: message)}
#   end

#   def handle_event("send_message", %{"message" => message}, socket) when message != "" do
#     user_message = %{
#       id: :crypto.strong_rand_bytes(8) |> Base.encode64(),
#       role: "user",
#       content: message
#     }

#     # Create assistant message placeholder
#     assistant_id = :crypto.strong_rand_bytes(8) |> Base.encode64()

#     assistant_message = %{
#       id: assistant_id,
#       role: "assistant",
#       content: ""
#     }

#     start_time = System.system_time(:millisecond)

#     updated_socket =
#       socket
#       |> assign(loading: true, input: "")
#       |> assign(messages: socket.assigns.messages ++ [user_message, assistant_message])
#       |> assign(current_assistant_id: assistant_id)

#     # Start async task for AI response streaming
#     live_view_pid = self()
#     model_spec = socket.assigns.model_spec

#     opts = [
#       temperature: socket.assigns.temperature,
#       max_tokens: socket.assigns.max_tokens,
#       system_prompt: socket.assigns.system_prompt
#     ]

#     # Build message history for the API call (exclude the placeholder assistant message)
#     message_history = updated_socket.assigns.messages |> Enum.slice(0..-2//1)

#     spawn(fn ->
#       stream_ai_response(live_view_pid, message_history, assistant_id, model_spec, opts, start_time)
#     end)

#     {:noreply, updated_socket}
#   end

#   def handle_event("send_message", _params, socket) do
#     {:noreply, socket}
#   end

#   def handle_event("change_provider", %{"value" => provider_str}, socket) do
#     IO.puts("🔧 🚨 PROVIDER CHANGE EVENT RECEIVED: #{provider_str}")
#     IO.puts("🔧 Current provider was: #{socket.assigns.selected_provider}")

#     provider = String.to_existing_atom(provider_str)
#     available_models = get_models_for_provider(provider) |> sort_models_alphabetically()

#     IO.puts("🔧 Found #{length(available_models)} models for #{provider}")

#     # Select first available model or keep current if it exists
#     selected_model =
#       case available_models do
#         [{model_id, _} | _] -> model_id
#         [] -> socket.assigns.selected_model
#       end

#     # Update model spec to use new provider:model
#     new_model_spec = "#{provider}:#{selected_model}"

#     IO.puts("🔧 New model spec: #{new_model_spec}")
#     IO.puts("🔧 Selected model: #{selected_model}")
#     IO.puts("🔧 Available models: #{length(available_models)}")

#     # Refresh API key status for new provider
#     api_key_status = [provider | socket.assigns.providers] |> Enum.uniq() |> check_api_keys()

#     socket =
#       assign(socket,
#         selected_provider: provider,
#         available_models: available_models,
#         selected_model: selected_model,
#         model_spec: new_model_spec,
#         api_key_status: api_key_status
#       )

#     IO.puts("🔧 ✅ Provider change completed - new state:")
#     IO.puts("🔧   Provider: #{socket.assigns.selected_provider}")
#     IO.puts("🔧   Model: #{socket.assigns.selected_model}")
#     IO.puts("🔧   Models available: #{length(socket.assigns.available_models)}")

#     {:noreply, socket}
#   end

#   def handle_event("change_model", %{"value" => model_id}, socket) do
#     IO.puts("🔧 Changing model to: #{model_id}")

#     provider = socket.assigns.selected_provider
#     new_model_spec = "#{provider}:#{model_id}"

#     IO.puts("🔧 New model spec: #{new_model_spec}")

#     {:noreply,
#      assign(socket,
#        selected_model: model_id,
#        model_spec: new_model_spec
#      )}
#   end

#   def handle_event(event, params, socket) do
#     IO.puts("🔧 🚨 UNKNOWN EVENT: #{event} with params: #{inspect(params)}")
#     {:noreply, socket}
#   end

#   def handle_info({:stream_chunk, assistant_id, chunk}, socket) do
#     updated_messages =
#       Enum.map(socket.assigns.messages, fn msg ->
#         if msg.id == assistant_id do
#           %{msg | content: msg.content <> chunk}
#         else
#           msg
#         end
#       end)

#     {:noreply, assign(socket, messages: updated_messages)}
#   end

#   def handle_info({:stream_complete, _assistant_id, _start_time}, socket) do
#     {:noreply, assign(socket, loading: false)}
#   end

#   def handle_info({:stream_complete, _assistant_id, _start_time, input_tokens, output_tokens, cost}, socket) do
#     # Accumulate metrics
#     new_total_input = socket.assigns.total_input_tokens + input_tokens
#     new_total_output = socket.assigns.total_output_tokens + output_tokens
#     new_total_cost = socket.assigns.total_cost + if cost, do: cost.total_cost, else: 0.0
#     new_api_calls = socket.assigns.api_calls + 1

#     IO.puts("🔧 📊 Metrics updated:")
#     IO.puts("🔧   Input tokens: #{input_tokens} (total: #{new_total_input})")
#     IO.puts("🔧   Output tokens: #{output_tokens} (total: #{new_total_output})")

#     if cost,
#       do: IO.puts("🔧   Cost: #{CostCalculator.format_cost(cost)} (total: $#{:io_lib.format("~.6f", [new_total_cost])})")

#     IO.puts("🔧   API calls: #{new_api_calls}")

#     {:noreply,
#      assign(socket,
#        loading: false,
#        total_input_tokens: new_total_input,
#        total_output_tokens: new_total_output,
#        total_cost: new_total_cost,
#        api_calls: new_api_calls,
#        current_request_cost: cost
#      )}
#   end

#   def handle_info({:stream_error, assistant_id, error}, socket) do
#     updated_messages =
#       Enum.map(socket.assigns.messages, fn msg ->
#         if msg.id == assistant_id do
#           %{msg | content: "Error: " <> inspect(error)}
#         else
#           msg
#         end
#       end)

#     {:noreply, assign(socket, messages: updated_messages, loading: false)}
#   end

#   def handle_info({:structured_result, result}, socket) do
#     {:noreply, assign(socket, structured_result: result, loading: false)}
#   end

#   def handle_info({:structured_error, error}, socket) do
#     {:noreply, assign(socket, structured_result: %{error: inspect(error)}, loading: false)}
#   end

#   defp stream_ai_response(pid, message_history, assistant_id, model_spec, opts, start_time) do
#     IO.puts("🔧 Starting stream for model: #{model_spec}")
#     IO.puts("🔧 Message history: #{length(message_history)} messages")
#     IO.puts("🔧 Options: #{inspect(opts)}")

#     # Check if we have an API key for the provider
#     provider = model_spec |> String.split(":") |> List.first() |> String.to_atom()

#     case Jido.AI.config([provider, :api_key]) do
#       nil ->
#         IO.puts("🔧 No API key found, using test mode")
#         simulate_streaming_response(pid, message_history, assistant_id, model_spec, start_time)

#       _key ->
#         IO.puts("🔧 API key found, using real API")
#         real_streaming_response(pid, message_history, assistant_id, model_spec, opts, start_time)
#     end
#   end

#   defp simulate_streaming_response(pid, message_history, assistant_id, model_spec, start_time) do
#     IO.puts("🔧 Simulating streaming response...")

#     latest_message = List.last(message_history)
#     current_message = if latest_message, do: latest_message.content, else: "No message"

#     test_response =
#       "🤖 [TEST MODE] Hello! I'm simulating a response from #{model_spec}.\n\nYour latest message was: #{current_message}\n\nChat history: #{length(message_history)} messages\n\nThis is a test of the streaming functionality. In real mode, this would be a response from the actual AI model."

#     # Calculate simulated metrics
#     request_body = %{
#       "model" => model_spec,
#       "messages" => Enum.map(message_history, fn msg -> %{"role" => msg.role, "content" => msg.content} end)
#     }

#     input_tokens = TokenCounter.count_request_tokens(request_body)
#     output_tokens = TokenCounter.count_tokens(test_response)

#     # Simulate cost calculation (use a default rate for test mode)
#     test_cost = %{
#       input_tokens: input_tokens,
#       output_tokens: output_tokens,
#       # $0.01/1K tokens
#       input_cost: input_tokens * 0.00001,
#       # $0.02/1K tokens
#       output_cost: output_tokens * 0.00002,
#       total_cost: input_tokens * 0.00001 + output_tokens * 0.00002,
#       currency: "USD"
#     }

#     # Simulate streaming by sending chunks
#     chunks = test_response |> String.graphemes() |> Enum.chunk_every(3) |> Enum.map(&Enum.join/1)

#     Enum.each(chunks, fn chunk ->
#       # Simulate network delay
#       Process.sleep(50)
#       send(pid, {:stream_chunk, assistant_id, chunk})
#     end)

#     send(pid, {:stream_complete, assistant_id, start_time, input_tokens, output_tokens, test_cost})
#   end

#   defp real_streaming_response(pid, message_history, assistant_id, model_spec, opts, start_time) do
#     # Convert message history to format expected by stream_text
#     messages =
#       Enum.map(message_history, fn msg ->
#         %Message{role: String.to_atom(msg.role), content: msg.content}
#       end)

#     prompt =
#       if length(messages) == 1 do
#         # Single message - pass as string
#         List.first(messages).content
#       else
#         # Multiple messages - pass as message list
#         messages
#       end

#     # Calculate input tokens for this request
#     request_body = %{
#       "model" => model_spec,
#       "messages" => Enum.map(message_history, fn msg -> %{"role" => msg.role, "content" => msg.content} end)
#     }

#     input_tokens = TokenCounter.count_request_tokens(request_body)

#     IO.puts("🔧 📡 STREAM_TEXT CALL:")
#     IO.puts("🔧   Model: #{model_spec}")
#     IO.puts("🔧   Messages: #{length(messages)}")
#     IO.puts("🔧   Input Tokens: #{input_tokens}")
#     IO.puts("🔧   Temperature: #{opts[:temperature]}")
#     IO.puts("🔧   Max Tokens: #{opts[:max_tokens]}")
#     IO.puts("🔧   System Prompt: #{String.slice(opts[:system_prompt] || "none", 0, 50)}...")

#     case Jido.AI.stream_text(model_spec, prompt, opts) do
#       {:ok, stream} ->
#         IO.puts("🔧 Stream started successfully")

#         try do
#           output_tokens =
#             Enum.reduce(stream, 0, fn chunk, acc_tokens ->
#               if chunk == "" do
#                 acc_tokens
#               else
#                 chunk_tokens = TokenCounter.count_stream_tokens(chunk)
#                 IO.puts("🔧 Chunk: #{inspect(chunk)} (#{chunk_tokens} tokens)")
#                 send(pid, {:stream_chunk, assistant_id, chunk})
#                 acc_tokens + chunk_tokens
#               end
#             end)

#           # Calculate cost for this request
#           cost = calculate_request_cost(model_spec, input_tokens, output_tokens)

#           IO.puts("🔧 Stream completed")
#           IO.puts("🔧 Total output tokens: #{output_tokens}")
#           if cost, do: IO.puts("🔧 Request cost: #{CostCalculator.format_cost(cost)}")

#           send(pid, {:stream_complete, assistant_id, start_time, input_tokens, output_tokens, cost})
#         rescue
#           error ->
#             IO.puts("🔧 Stream error during enumeration: #{inspect(error)}")
#             send(pid, {:stream_error, assistant_id, error})
#         end

#       {:error, error} ->
#         IO.puts("🔧 Stream failed to start: #{inspect(error)}")
#         send(pid, {:stream_error, assistant_id, error})
#     end
#   end

#   defp calculate_request_cost(model_spec, input_tokens, output_tokens) do
#     case Jido.AI.model(model_spec) do
#       {:ok, model} ->
#         CostCalculator.calculate_cost(model, input_tokens, output_tokens)

#       {:error, _} ->
#         nil
#     end
#   end

#   defp generate_structured_data(pid, model_spec, schema_input, output_type, system_prompt) do
#     # Parse schema from string format
#     {schema, []} = Code.eval_string("[" <> schema_input <> "]")

#     prompt = "Generate structured data according to the schema provided."

#     opts = [
#       output_type: output_type,
#       system_prompt: system_prompt
#     ]

#     case Jido.AI.generate_object(model_spec, prompt, schema, opts) do
#       {:ok, result} ->
#         send(pid, {:structured_result, result})

#       {:error, error} ->
#         send(pid, {:structured_error, error})
#     end
#   rescue
#     error ->
#       send(pid, {:structured_error, "Schema parsing error: " <> inspect(error)})
#   end

#   defp format_markdown(content) do
#     case Earmark.as_html(content) do
#       {:ok, html, []} -> html
#       {:ok, html, _warnings} -> html
#       {:error, _html, _errors} -> content
#     end
#   end

#   defp get_models_for_provider(provider) do
#     case Jido.AI.Provider.Registry.fetch(provider) do
#       {:ok, provider_module} ->
#         provider_info = provider_module.provider_info()
#         provider_info.models |> Enum.to_list()

#       {:error, _} ->
#         []
#     end
#   end

#   defp sort_alphabetically(list) do
#     Enum.sort_by(list, fn
#       atom when is_atom(atom) -> Atom.to_string(atom)
#       str when is_binary(str) -> String.downcase(str)
#     end)
#   end

#   defp sort_models_alphabetically(models) do
#     Enum.sort_by(models, fn
#       {model_id, _model} -> String.downcase(model_id)
#       model_id when is_binary(model_id) -> String.downcase(model_id)
#     end)
#   end

#   defp check_api_keys(providers) do
#     Enum.map(providers, fn provider ->
#       case Jido.AI.config([provider, :api_key]) do
#         nil ->
#           IO.puts("🔧 No API key found for #{provider}")
#           {provider, :missing}

#         key when is_binary(key) ->
#           IO.puts("🔧 API key found for #{provider}: #{String.slice(key, 0, 10)}...")
#           {provider, :available}

#         other ->
#           IO.puts("🔧 Unexpected API key type for #{provider}: #{inspect(other)}")
#           {provider, :error}
#       end
#     end)
#   end
# end
