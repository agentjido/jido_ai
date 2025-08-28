### Slide 1: Jido AI in 15 Minutes

Content:
- Unified facade over multiple LLM providers
- Rich prompts: strings or message arrays with multi-modal parts
- Tool calling via Jido Actions; structured output with schema validation
- Cost/usage middleware and robust error types

Code:
```elixir
# source: projects/jido_ai/lib/jido_ai.ex
@spec generate_text(
        Model.t() | {atom(), keyword()} | String.t(),
        String.t() | [Message.t()],
        keyword()
      ) :: {:ok, String.t()} | {:error, term()}
def generate_text(model_spec, prompt, opts) when (is_binary(prompt) or is_list(prompt)) and is_list(opts) do
  opts = process_tool_options(opts)

  with {:ok, model} <- ensure_model_struct(model_spec),
       {:ok, provider_module} <- provider(model.provider) do
    provider_module.generate_text(model, prompt, opts)
  end
end
```

Notes:
- Entry point for text generation
- Accepts string or `[Message]` prompts
- Tools merged via `actions`/`tools` opts

---

### Slide 2: Models and Providers

Content:
- Model spec formats: string, tuple, or struct
- Provider lookup via registry
- Keep provider-specifics behind a behaviour/macro

Code:
```elixir
# source: projects/jido_ai/lib/jido_ai.ex
@spec provider(atom()) :: {:ok, module()} | {:error, String.t()}
def provider(provider) do
  Jido.AI.Provider.Registry.fetch(provider)
end

@spec model(Model.t() | {atom(), keyword()} | String.t()) ::
        {:ok, Model.t()} | {:error, String.t()}
def model(spec) do
  Model.from(spec)
end
```

Notes:
- Models normalized before use
- Registry returns concrete provider module

---

### Slide 3: Message Structure

Content:
- Strongly typed `Message` struct
- Roles: `:user`, `:assistant`, `:system`, `:tool`
- Content can be string or list of content parts

Code:
```elixir
# source: projects/jido_ai/lib/jido_ai/message.ex
typedstruct do
  @typedoc "A message in a conversation with an AI model"

  field(:role, role(), enforce: true)
  field(:content, String.t() | [ContentPart.t()], enforce: true)
  field(:name, String.t() | nil)
  field(:tool_call_id, String.t() | nil)
  field(:tool_calls, [map()] | nil)
  field(:metadata, map() | nil)
end
```

Notes:
- `tool_call_id` used for linking tool results
- `metadata` carries provider options

---

### Slide 4: Content Parts (Multi-modal & Tools)

Content:
- ContentPart types: text, image_url, image, file, tool_call, tool_result
- Validation helpers and API mapping via `to_map/1`

Code:
```elixir
# source: projects/jido_ai/lib/jido_ai/content_part.ex
typedstruct do
  @typedoc "A piece of content within a message"

  field(:type, content_type(), enforce: true)
  field(:text, String.t() | nil)
  field(:url, String.t() | nil)
  field(:data, binary() | nil)
  field(:media_type, String.t() | nil)
  field(:filename, String.t() | nil)
  field(:tool_call_id, String.t() | nil)
  field(:tool_name, String.t() | nil)
  field(:input, map() | nil)
  field(:output, any() | nil)
  field(:metadata, map() | nil)
end
```

Notes:
- Tool parts enable RAG/actions workflows
- Binary/file support encoded for providers

---

### Slide 5: Convenience Builders

Content:
- Lightweight helpers for common messages
- Keep usage concise for message arrays

Code:
```elixir
# source: projects/jido_ai/lib/jido_ai/messages.ex
@spec user(String.t()) :: Message.t()
@spec user(String.t(), map()) :: Message.t()
def user(content, metadata \\ %{}) do
  %Message{role: :user, content: content, metadata: metadata}
end

@spec system(String.t()) :: Message.t()
@spec system(String.t(), map()) :: Message.t()
def system(content, metadata \\ %{}) do
  %Message{role: :system, content: content, metadata: metadata}
end
```

Notes:
- Import `Jido.AI.Messages` in clients
- Similar helpers for assistant, files, images, tool_result

---

### Slide 6: Prompt Assembly → OpenAI Format

Content:
- Strings become a single user message
- Message lists encoded with content parts
- System prompt injected at index 0 when provided

Code:
```elixir
# source: projects/jido_ai/lib/jido_ai/provider/request/builder.ex
def build_chat_completion_body(provider_module, %Model{} = model, prompt, system_prompt, opts) do
  messages = encode_messages(prompt)
  final_messages = if system_prompt, do: [%{role: "system", content: system_prompt} | messages], else: messages
  provider_options = Options.merge_provider_options(model, prompt, opts, %{})
  supported_opts = provider_module.chat_completion_opts()
  base_body =
    opts
    |> Keyword.put(:messages, final_messages)
    |> Keyword.put(:model, model.model)
    |> Keyword.take(supported_opts ++ [:stream])
    |> Map.new()
  Map.merge(base_body, Map.get(provider_options, model.provider, %{}))
end
```

Notes:
- Provider-specific opts merged into body
- Keeps request shape consistent per provider

---

### Slide 7: System Prompt Support

Content:
- `system_prompt` opt supported across APIs
- Verified by tests for strings and message arrays

Code:
```elixir
# source: projects/jido_ai/test/jido_ai/system_prompt_test.exs
body_with_system =
  Builder.build_chat_completion_body(OpenAI, model, "Hello", "You are helpful", [])
messages_with_system = body_with_system[:messages]
assert length(messages_with_system) == 2
assert hd(messages_with_system) == %{role: "system", content: "You are helpful"}
assert Enum.at(messages_with_system, 1) == %{role: "user", content: "Hello"}
```

Notes:
- System prompt always prepended
- Works with both string and message prompts

---

### Slide 8: Tool-Friendly Assistant and Results

Content:
- Assistant can emit tool calls via content parts
- Tool results return as `:tool` messages linked by `tool_call_id`

Code:
```elixir
# source: projects/jido_ai/lib/jido_ai/message.ex
@spec assistant_with_tools(String.t(), [ContentPart.t()], keyword()) :: t()
def assistant_with_tools(text, tool_calls, opts \\ []) when is_binary(text) and is_list(tool_calls) do
  content = [ContentPart.text(text) | tool_calls]
  new(:assistant, content, opts)
end

@spec tool_result(String.t(), String.t(), any(), keyword()) :: t()
def tool_result(tool_call_id, tool_name, output, opts \\ []) when is_binary(tool_call_id) and is_binary(tool_name) do
  content = [ContentPart.tool_result(tool_call_id, tool_name, output)]
  new(:tool, content, Keyword.put(opts, :tool_call_id, tool_call_id))
end
```

Notes:
- Tool calls are part of assistant content
- Tool results are separate `:tool` messages

---

### Slide 9: From Actions to Tools

Content:
- Convert Jido Actions into OpenAI-compatible tool defs
- Alternative raw format supported

Code:
```elixir
# source: projects/jido_ai/lib/jido_ai/tool_integration.ex
@spec actions_to_tools([module()], :openai | :raw) :: [map()]
def actions_to_tools(actions, format \\ :openai) when is_list(actions) do
  Enum.map(actions, fn action ->
    tool_def = action.to_tool()
    case format do
      :openai -> %{"type" => "function", "function" => %{"name" => tool_def.name,
                         "description" => tool_def.description,
                         "parameters" => convert_schema_to_openai_format(tool_def.parameters_schema)}}
      :raw -> tool_def
    end
  end)
end
```

Notes:
- `action.to_tool/0` supplies schema/name/description
- Keeps provider layer decoupled from actions

---

### Slide 10: Executing Tool Calls

Content:
- Decode tool call JSON args, dispatch to action
- Return `tool_result` messages for conversation

Code:
```elixir
# source: projects/jido_ai/lib/jido_ai/tool_integration.ex
@spec execute_single_tool_call(map(), map(), map()) :: Message.t()
def execute_single_tool_call(tool_call, action_map, context) do
  %{"id" => tool_call_id, "function" => %{"name" => function_name, "arguments" => arguments_json}} = tool_call
  case Map.get(action_map, function_name) do
    nil -> Message.tool_result(tool_call_id, function_name, %{error: "Unknown tool: #{function_name}"})
    action ->
      case Jason.decode(arguments_json) do
        {:ok, arguments} ->
          tool_def = action.to_tool()
          case tool_def.function.(arguments, context) do
            {:ok, result_json} -> Message.tool_result(tool_call_id, function_name, Jason.decode!(result_json))
            {:error, error_json} -> Message.tool_result(tool_call_id, function_name, Jason.decode!(error_json))
          end
        {:error, _} -> Message.tool_result(tool_call_id, function_name, %{error: "Invalid JSON arguments: #{arguments_json}"})
      end
  end
end
```

Notes:
- JSON boundary between LLM and action layer
- Errors encoded as tool results too

---

### Slide 11: Tool Flow Overview

Content:
- Flow: user → assistant(tool_call) → tool_result → assistant
- Tools can be executed client-side then appended to messages
- Works with `generate_text/3` streaming or non-streaming

Code:
```elixir
# source: projects/jido_ai/lib/jido_ai.ex
messages = [
  user("What's the weather in SF?"),
  assistant("I'll check the weather for you", [
    tool_call("call_123", "get_weather", %{location: "San Francisco"})
  ]),
  tool_result("call_123", "get_weather", %{temp: 68, condition: "sunny"}),
  assistant("It's 68°F and sunny in San Francisco!")
]
```

Notes:
- Simple manual loop for tool calls
- Also possible to convert actions and let model call tools

---

### Slide 12: Structured Output: Validation

Content:
- NimbleOptions-backed schemas for object/array/enum
- Validation returns `{:ok, data}` or raises `SchemaValidation`

Code:
```elixir
# source: projects/jido_ai/lib/jido_ai/object_schema.ex
def validate(%__MODULE__{output_type: :object, schema: schema}, data) when is_map(data) do
  normalized_data = normalize_map_keys(data)
  case NimbleOptions.validate(normalized_data, schema) do
    {:ok, validated_data} -> {:ok, validated_data}
    {:error, %NimbleOptions.ValidationError{} = error} ->
      validation_error = SchemaValidation.exception(
        validation_errors: [Exception.message(error)],
        schema: %{output_type: :object, properties: schema}
      )
      {:error, validation_error}
  end
end
```

Notes:
- String keys normalized before validation
- Detailed errors captured in a typed exception

---

### Slide 13: Retry on Schema Errors

Content:
- Provider default retries object generation on validation failure
- Builds a retry prompt with error feedback

Code:
```elixir
# source: projects/jido_ai/lib/jido_ai/provider/macro.ex
defp do_generate_object_with_retry(provider_module, model, prompt, schema, opts, max_retries, attempt) do
  system_prompt = Request.Builder.build_schema_system_prompt(schema, Keyword.get(opts, :system_prompt))
  with {:ok, _} <- Util.Validation.validate_prompt(prompt),
       {:ok, _} <- Util.Validation.validate_schema(schema) do
    merged_opts = Util.Options.merge_model_options(provider_module, model, opts)
                  |> Util.Options.maybe_add_json_mode(provider_module)
    with {:ok, response} <- Request.HTTP.do_http_request(provider_module, model,
                           Request.Builder.build_chat_completion_body(provider_module, model, prompt, system_prompt, merged_opts), merged_opts),
         {:ok, object, meta} <- Response.Parser.extract_object_response(response),
         {:ok, schema_struct} <- ObjectSchema.new(schema),
         {:ok, validated_object} <- ObjectSchema.validate(schema_struct, object) do
      {:ok, validated_object}
    else
      {:error, %SchemaValidation{} = error} when attempt < max_retries ->
        retry_prompt = build_retry_prompt(prompt, schema, error)
        do_generate_object_with_retry(provider_module, model, retry_prompt, schema, opts, max_retries, attempt + 1)
      {:error, _} = error -> error
    end
  end
end
```

Notes:
- Retries include validation feedback in prompt
- Max retries from opts or model defaults

---

### Slide 14: Usage Extraction

Content:
- Normalize provider usage into input/output/total tokens
- Supports OpenAI, Google, Anthropic formats

Code:
```elixir
# source: projects/jido_ai/lib/jido_ai/middleware/usage_extraction.ex
def extract_usage_from_response(response_body) when is_map(response_body) do
  cond do
    google_usage = get_in(response_body, ["usageMetadata"]) -> normalize_google_usage(google_usage)
    usage = get_in(response_body, ["usage"]) ->
      case normalize_anthropic_usage(usage) do
        nil -> normalize_openai_usage(usage)
        result -> result
      end
    true -> nil
  end
end
```

Notes:
- Produces a consistent usage struct
- Downstream cost calc uses this when available

---

### Slide 15: Cost Calculation

Content:
- Compute USD costs from model rates and tokens
- Uses exact usage when present; falls back to estimates

Code:
```elixir
# source: projects/jido_ai/lib/jido_ai/cost_calculator.ex
def calculate_cost_from_usage(model, %{"prompt_tokens" => input_tokens, "completion_tokens" => output_tokens}) do
  calculate_cost(model, input_tokens, output_tokens)
end

def calculate_request_cost(model, request_body, response_body) do
  input_tokens = TokenCounter.count_request_tokens(request_body)
  output_tokens = TokenCounter.count_response_tokens(response_body)
  calculate_cost(model, input_tokens, output_tokens)
end
```

Notes:
- Pricing read from provider model metadata
- Estimation used when provider omits usage

---

### Slide 16: HTTP Transport Middleware

Content:
- Validates options, counts tokens, executes HTTP, enriches response
- Attaches usage/cost metadata and builds structured errors

Code:
```elixir
# source: projects/jido_ai/lib/jido_ai/middleware/transport.ex
case http_client.post(url, request_options) do
  {:ok, response} ->
    if response.status >= 400 do
      error = build_enhanced_api_error(response, context.body)
      Context.put_meta(context, :error, error)
    else
      process_successful_response(context, response)
    end
  {:error, reason} ->
    error = build_enhanced_api_error(reason, context.body)
    Context.put_meta(context, :error, error)
end
```

Notes:
- Works with any Req-compatible client
- Adds `:jido_meta` to responses for downstream use

---

### Slide 17: Tests as Evaluation

Content:
- No separate evaluator pipeline; rely on focused tests
- Coverage for prompts, tools, transport, usage/cost, and provider base

Code:
```elixir
# source: projects/jido_ai/test/integration/tool_flow_integration_test.exs
describe "tool conversation structure validation" do
  test "validates basic tool call conversation" do
    messages = [
      user("What is 5 + 3?"),
      tool_result("call_123", "add", %{result: 8}),
      assistant("The answer is 8")
    ]
    assert Enum.all?(messages, &Message.valid?/1)
  end
end
```

Notes:
- Integration tests exercise end-to-end flows
- Unit tests cover encoding, validation, options

---

### Slide 18: Putting It Together

Content:
- Choose provider/model, construct messages, call `generate_text/3`
- Add actions as tools or handle tool loop manually

Code:
```elixir
# source: projects/jido_ai/lib/jido_ai.ex
@spec stream_text(
        Model.t() | {atom(), keyword()} | String.t(),
        String.t() | [Message.t()],
        keyword()
      ) :: {:ok, Enumerable.t()} | {:error, term()}
def stream_text(model_spec, prompt, opts) when (is_binary(prompt) or is_list(prompt)) and is_list(opts) do
  opts = process_tool_options(opts)
  with {:ok, model} <- ensure_model_struct(model_spec),
       {:ok, provider_module} <- provider(model.provider) do
    provider_module.stream_text(model, prompt, opts)
  end
end
```

Notes:
- Same pattern for `generate_object/4` and streaming variants
- Keep business logic outside providers; pass options/messages
