# Your Second Action

**Prerequisites**: [Getting Started](getting-started.md) • Basic action creation

This tutorial builds a more sophisticated action with schema validation, error handling, and comprehensive testing.

## The Task: User Registration

We'll create an action that validates user registration data, demonstrating:
- Complex schema validation
- Structured error handling  
- Lifecycle hooks
- Comprehensive testing

## Step 1: Define the Schema

```elixir
defmodule MyApp.Actions.RegisterUser do
  use Jido.Action,
    name: "register_user",
    description: "Validates and registers a new user",
    schema: [
      email: [
        type: :string, 
        required: true,
        doc: "User's email address"
      ],
      password: [
        type: :string, 
        required: true,
        doc: "User's password (min 8 chars)"
      ],
      age: [
        type: :integer, 
        required: true,
        min: 13,
        doc: "User's age (minimum 13)"
      ],
      terms_accepted: [
        type: :boolean,
        default: false,
        doc: "Terms of service acceptance"
      ]
    ]
```

## Step 2: Add Validation Logic

```elixir
  def run(params, context) do
    with {:ok, validated} <- validate_business_rules(params),
         {:ok, user} <- create_user(validated, context) do
      {:ok, %{
        user_id: user.id,
        email: user.email,
        registered_at: DateTime.utc_now()
      }}
    end
  end

  defp validate_business_rules(params) do
    cond do
      not String.contains?(params.email, "@") ->
        {:error, Jido.Action.Error.execution_error("Invalid email format")}
      
      String.length(params.password) < 8 ->
        {:error, Jido.Action.Error.execution_error("Password too short")}
      
      not params.terms_accepted ->
        {:error, Jido.Action.Error.execution_error("Terms must be accepted")}
      
      true ->
        {:ok, params}
    end
  end

  defp create_user(params, _context) do
    # Simulate user creation
    user_id = "user_#{:rand.uniform(10000)}"
    {:ok, %{id: user_id, email: params.email}}
  end
```

## Step 3: Add Lifecycle Hooks

```elixir
  @impl true
  def on_before_validate_params(params) do
    # Normalize email before validation
    normalized = Map.update(params, :email, "", &String.downcase/1)
    {:ok, normalized}
  end

  @impl true  
  def on_after_run(result) do
    # Log successful registration
    IO.puts("User registered: #{result.user_id}")
    {:ok, result}
  end

  @impl true
  def on_error(failed_params, error, _context, _opts) do
    # Log registration failure (no compensation needed)
    IO.puts("Registration failed for #{failed_params[:email]}: #{error.message}")
    {:ok, %{error_logged: true}}
  end
end
```

## Step 4: Test Your Action

Create `test/actions/register_user_test.exs`:

```elixir
defmodule MyApp.Actions.RegisterUserTest do
  use ExUnit.Case

  alias MyApp.Actions.RegisterUser

  describe "register_user/2" do
    test "succeeds with valid input" do
      params = %{
        email: "user@example.com",
        password: "secure123", 
        age: 25,
        terms_accepted: true
      }
      
      assert {:ok, result} = RegisterUser.run(params, %{})
      assert String.starts_with?(result.user_id, "user_")
      assert result.email == "user@example.com"
      assert result.registered_at
    end

    test "normalizes email case" do
      params = %{
        email: "USER@EXAMPLE.COM",
        password: "secure123",
        age: 25, 
        terms_accepted: true
      }
      
      assert {:ok, result} = RegisterUser.run(params, %{})
      assert result.email == "user@example.com"
    end

    test "rejects invalid email" do
      params = %{
        email: "invalid-email",
        password: "secure123",
        age: 25,
        terms_accepted: true
      }
      
      assert {:error, error} = RegisterUser.run(params, %{})
      assert error.message =~ "Invalid email format"
    end

    test "rejects short password" do
      params = %{
        email: "user@example.com", 
        password: "short",
        age: 25,
        terms_accepted: true
      }
      
      assert {:error, error} = RegisterUser.run(params, %{})
      assert error.message =~ "Password too short"
    end

    test "requires terms acceptance" do
      params = %{
        email: "user@example.com",
        password: "secure123",
        age: 25,
        terms_accepted: false
      }
      
      assert {:error, error} = RegisterUser.run(params, %{})
      assert error.message =~ "Terms must be accepted"
    end

    test "validates schema constraints" do
      # Age too young
      params = %{
        email: "user@example.com",
        password: "secure123", 
        age: 12,
        terms_accepted: true
      }
      
      assert {:error, error} = RegisterUser.run(params, %{})
      assert error.type == :validation_error
    end

    test "requires all mandatory fields" do
      params = %{email: "user@example.com"}
      
      assert {:error, error} = RegisterUser.run(params, %{})
      assert error.type == :validation_error
    end
  end
end
```

## Step 5: Run Tests

```bash
mix test test/actions/register_user_test.exs
```

Expected output:
```
Compiling 1 file (.ex)
.......

Finished in 0.05 seconds (0.00s async, 0.05s sync)
7 tests, 0 failures
```

## Step 6: Use with Execution Engine

```elixir
# With retries and timeout
{:ok, result} = Jido.Exec.run(
  MyApp.Actions.RegisterUser,
  %{
    email: "user@example.com",
    password: "secure123",
    age: 25,
    terms_accepted: true
  },
  %{request_id: "req_123"},
  timeout: 5000,
  max_retries: 2
)

# Async execution
async_ref = Jido.Exec.run_async(
  MyApp.Actions.RegisterUser,
  params,
  %{}
)

{:ok, result} = Jido.Exec.await(async_ref, 10_000)
```

## What You've Learned

✅ **Schema Definition** - Complex validation with types, constraints, and docs  
✅ **Error Handling** - Structured errors with helpful messages  
✅ **Lifecycle Hooks** - Data normalization and logging  
✅ **Testing Patterns** - Comprehensive test coverage  
✅ **Production Usage** - Execution engine features

## Next Steps

**→ [Actions](actions-guide.md)** - Deep dive into framework architecture  
**→ [Error Handling Guide](error-handling.md)** - Advanced error patterns  
**→ [Testing Guide](testing.md)** - More testing strategies

---
← [Getting Started](getting-started.md) | **Next: [Actions](actions-guide.md)** →
