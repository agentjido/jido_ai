defmodule JidoTest.Exec.Examples.UserRegistrationExecTest do
  use JidoTest.ActionCase, async: true

  alias Jido.Exec
  alias Jido.Exec.Chain
  alias JidoTest.TestActions.{EnrichUserData, FormatEnrichNotifyUserChain, FormatUser, NotifyUser}

  @valid_user_data %{
    # Note the trailing space to test trimming
    name: "John Doe ",
    # Test case normalization
    email: "JOHN@EXAMPLE.COM",
    age: 30
  }

  @moduletag :capture_log

  describe "individual action tests" do
    test "FormatUser formats and validates user data directly" do
      {:ok, result} = FormatUser.run(@valid_user_data, %{})

      assert result.formatted_name == "John Doe"
      assert result.email == "john@example.com"
      assert result.age == 30
      assert result.is_adult == true
    end

    test "EnrichUserData adds username and avatar" do
      input = %{
        formatted_name: "John Doe",
        email: "john@example.com"
      }

      {:ok, result} = EnrichUserData.run(input, %{})

      hash = :crypto.hash(:md5, input.email) |> Base.encode16(case: :lower)
      assert result.username == "john.doe"
      assert result.avatar_url =~ "https://www.gravatar.com/avatar/#{hash}"
    end

    test "NotifyUser sends notification" do
      input = %{
        email: "john@example.com",
        username: "john.doe"
      }

      {:ok, result} = NotifyUser.run(input, %{})

      assert result.notification_sent == true
      assert result.notification_type == "welcome_email"
      assert result.recipient.email == "john@example.com"
      assert result.recipient.username == "john.doe"
    end
  end

  describe "using Exec.run" do
    test "FormatUser via Exec.run" do
      {:ok, result} = Exec.run(FormatUser, @valid_user_data)

      assert result.formatted_name == "John Doe"
      assert result.email == "john@example.com"
      assert result.is_adult == true
    end

    test "EnrichUserData via Exec.run" do
      input = %{
        formatted_name: "John Doe",
        email: "john@example.com"
      }

      {:ok, result} = Exec.run(EnrichUserData, input)

      hash = :crypto.hash(:md5, input.email) |> Base.encode16(case: :lower)

      assert result.username == "john.doe"
      assert result.avatar_url =~ "https://www.gravatar.com/avatar/#{hash}"
    end

    test "NotifyUser via Exec.run" do
      input = %{
        email: "john@example.com",
        username: "john.doe"
      }

      {:ok, result} = Exec.run(NotifyUser, input)

      assert result.notification_sent == true
      assert result.notification_type == "welcome_email"
    end

    test "FormatUser via Exec.run_async" do
      async_ref = Exec.run_async(FormatUser, @valid_user_data)
      assert is_map(async_ref)
      assert is_pid(async_ref.pid)
      assert is_reference(async_ref.ref)

      {:ok, result} = Exec.await(async_ref)

      assert result.formatted_name == "John Doe"
      assert result.email == "john@example.com"
      assert result.is_adult == true
    end
  end

  describe "chaining actions" do
    test "chains all user registration actions together" do
      {:ok, result} =
        Chain.chain(
          [
            FormatUser,
            EnrichUserData,
            NotifyUser
          ],
          @valid_user_data
        )

      # Verify FormatUser results
      assert result.formatted_name == "John Doe"
      assert result.email == "john@example.com"
      assert result.age == 30
      assert result.is_adult == true

      # Verify EnrichUserData results
      assert result.username == "john.doe"
      assert result.avatar_url =~ "https://www.gravatar.com/avatar/"

      # Verify NotifyUser results
      assert result.notification_sent == true
      assert result.notification_type == "welcome_email"
      assert result.recipient.email == "john@example.com"
      assert result.recipient.username == "john.doe"
    end

    test "chains with context" do
      context = %{tenant_id: "123", environment: "test"}

      {:ok, result} =
        Chain.chain(
          [FormatUser, EnrichUserData, NotifyUser],
          @valid_user_data,
          context: context
        )

      assert result.notification_sent == true
    end

    test "chains with override action parameters" do
      {:ok, result} =
        Chain.chain(
          [
            {FormatUser, [name: "Jane Doe"]},
            EnrichUserData,
            NotifyUser
          ],
          @valid_user_data
        )

      # Parameter to FormatUser is overridden by the local parameter
      assert result.formatted_name == "Jane Doe"
      assert result.username == "jane.doe"
    end

    test "chains with custom action parameters" do
      {:ok, result} =
        Chain.chain(
          [
            FormatUser,
            {EnrichUserData, [custom_field: "value"]},
            NotifyUser
          ],
          @valid_user_data
        )

      assert result.notification_sent == true
      # Custom field is added to the result by EnrichUserData
      assert result.custom_field == "value"
    end

    test "chain stops on first error" do
      invalid_data = %{@valid_user_data | email: nil}

      {:error, error} =
        Chain.chain(
          [FormatUser, EnrichUserData, NotifyUser],
          invalid_data
        )

      assert is_exception(error)
      assert error.__struct__ == Jido.Action.Error.InvalidInputError
    end

    test "chain can be packaged as an action" do
      {:ok, result} =
        Exec.run(FormatEnrichNotifyUserChain, %{
          name: "George Washington",
          email: "george@example.com",
          age: 67
        })

      assert result.name == "George Washington"
      assert result.email == "george@example.com"
      assert result.age == 67
      assert result.username == "george.washington"
      assert result.avatar_url =~ "https://www.gravatar.com/avatar/"
      assert result.notification_sent == true
      assert result.notification_type == "welcome_email"
    end
  end
end
