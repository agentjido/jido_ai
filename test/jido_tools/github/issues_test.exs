defmodule Jido.Tools.Github.IssuesTest do
  use JidoTest.ActionCase, async: false

  import Mimic

  alias Jido.Tools.Github.Issues

  setup :set_mimic_global
  setup :verify_on_exit!

  @mock_client %{access_token: "test_token"}
  @mock_issue_response %{
    "id" => 123,
    "number" => 1,
    "title" => "Test Issue",
    "body" => "Test Body",
    "state" => "open",
    "assignee" => nil,
    "labels" => [],
    "milestone" => nil
  }

  describe "Create" do
    test "creates issue successfully with all parameters" do
      expect(Tentacat.Issues, :create, fn client, owner, repo, body ->
        assert client == @mock_client
        assert owner == "test-owner"
        assert repo == "test-repo"
        assert body.title == "Test Issue"
        assert body.body == "Test Body"
        assert body.assignee == "test-assignee"
        assert body.milestone == "v1.0"
        assert body.labels == ["bug", "feature"]
        @mock_issue_response
      end)

      params = %{
        client: @mock_client,
        owner: "test-owner",
        repo: "test-repo",
        title: "Test Issue",
        body: "Test Body",
        assignee: "test-assignee",
        milestone: "v1.0",
        labels: ["bug", "feature"]
      }

      assert {:ok, result} = Issues.Create.run(params, %{})
      assert result.status == "success"
      assert result.data == @mock_issue_response
      assert result.raw == @mock_issue_response
    end

    test "creates issue with minimal parameters" do
      expect(Tentacat.Issues, :create, fn client, owner, repo, body ->
        assert client == @mock_client
        assert owner == "test-owner"
        assert repo == "test-repo"
        assert body.title == "Test Issue"
        assert body.body == "Test Body"
        assert body.assignee == nil
        assert body.milestone == nil
        assert body.labels == nil
        @mock_issue_response
      end)

      params = %{
        client: @mock_client,
        owner: "test-owner",
        repo: "test-repo",
        title: "Test Issue",
        body: "Test Body",
        assignee: nil,
        milestone: nil,
        labels: nil
      }

      assert {:ok, result} = Issues.Create.run(params, %{})
      assert result.status == "success"
      assert result.data == @mock_issue_response
    end
  end

  describe "Filter" do
    test "filters issues with all parameters" do
      mock_issues = [@mock_issue_response]

      expect(Tentacat.Issues, :filter, fn client, owner, repo, filters ->
        assert client == @mock_client
        assert owner == "test-owner"
        assert repo == "test-repo"
        assert filters.state == "open"
        assert filters.assignee == "test-user"
        assert filters.creator == "test-creator"
        assert filters.labels == "bug,feature"
        assert filters.sort == "created"
        assert filters.direction == "desc"
        assert filters.since == "2023-01-01T00:00:00Z"
        mock_issues
      end)

      params = %{
        client: @mock_client,
        owner: "test-owner",
        repo: "test-repo",
        state: "open",
        assignee: "test-user",
        creator: "test-creator",
        labels: "bug,feature",
        sort: "created",
        direction: "desc",
        since: "2023-01-01T00:00:00Z"
      }

      assert {:ok, result} = Issues.Filter.run(params, %{})
      assert result.status == "success"
      assert result.data == mock_issues
      assert result.raw == mock_issues
    end

    test "filters issues with minimal parameters" do
      mock_issues = [@mock_issue_response]

      expect(Tentacat.Issues, :filter, fn client, owner, repo, filters ->
        assert client == @mock_client
        assert owner == "test-owner"
        assert repo == "test-repo"
        assert filters.state == nil
        assert filters.assignee == nil
        assert filters.creator == nil
        assert filters.labels == nil
        assert filters.sort == nil
        assert filters.direction == nil
        assert filters.since == nil
        mock_issues
      end)

      params = %{
        client: @mock_client,
        owner: "test-owner",
        repo: "test-repo",
        state: nil,
        assignee: nil,
        creator: nil,
        labels: nil,
        sort: nil,
        direction: nil,
        since: nil
      }

      assert {:ok, result} = Issues.Filter.run(params, %{})
      assert result.status == "success"
      assert result.data == mock_issues
    end

    test "filters issues with state only" do
      mock_issues = [@mock_issue_response]

      expect(Tentacat.Issues, :filter, fn _client, _owner, _repo, filters ->
        assert filters.state == "closed"
        mock_issues
      end)

      params = %{
        client: @mock_client,
        owner: "test-owner",
        repo: "test-repo",
        state: "closed",
        assignee: nil,
        creator: nil,
        labels: nil,
        sort: nil,
        direction: nil,
        since: nil
      }

      assert {:ok, result} = Issues.Filter.run(params, %{})
      assert result.status == "success"
    end
  end

  describe "Find" do
    test "finds issue by number successfully" do
      expect(Tentacat.Issues, :find, fn client, owner, repo, number ->
        assert client == @mock_client
        assert owner == "test-owner"
        assert repo == "test-repo"
        assert number == 42
        @mock_issue_response
      end)

      params = %{
        client: @mock_client,
        owner: "test-owner",
        repo: "test-repo",
        number: 42
      }

      assert {:ok, result} = Issues.Find.run(params, %{})
      assert result.status == "success"
      assert result.data == @mock_issue_response
      assert result.raw == @mock_issue_response
    end

    test "finds issue with different number" do
      expect(Tentacat.Issues, :find, fn _client, _owner, _repo, number ->
        assert number == 1
        @mock_issue_response
      end)

      params = %{
        client: @mock_client,
        owner: "test-owner",
        repo: "test-repo",
        number: 1
      }

      assert {:ok, result} = Issues.Find.run(params, %{})
      assert result.status == "success"
    end
  end

  describe "List" do
    test "lists all issues successfully" do
      mock_issues = [@mock_issue_response, %{@mock_issue_response | "number" => 2}]

      expect(Tentacat.Issues, :list, fn client, owner, repo ->
        assert client == @mock_client
        assert owner == "test-owner"
        assert repo == "test-repo"
        mock_issues
      end)

      params = %{
        client: @mock_client,
        owner: "test-owner",
        repo: "test-repo"
      }

      assert {:ok, result} = Issues.List.run(params, %{})
      assert result.status == "success"
      assert result.data == mock_issues
      assert result.raw == mock_issues
    end

    test "lists issues for different repository" do
      mock_issues = []

      expect(Tentacat.Issues, :list, fn client, owner, repo ->
        assert client == @mock_client
        assert owner == "different-owner"
        assert repo == "different-repo"
        mock_issues
      end)

      params = %{
        client: @mock_client,
        owner: "different-owner",
        repo: "different-repo"
      }

      assert {:ok, result} = Issues.List.run(params, %{})
      assert result.status == "success"
      assert result.data == []
    end
  end

  describe "Update" do
    test "updates issue with all parameters" do
      updated_issue = %{@mock_issue_response | "title" => "Updated Title", "state" => "closed"}

      expect(Tentacat.Issues, :update, fn client, owner, repo, number, body ->
        assert client == @mock_client
        assert owner == "test-owner"
        assert repo == "test-repo"
        assert number == 42
        assert body.title == "Updated Title"
        assert body.body == "Updated Body"
        assert body.assignee == "new-assignee"
        assert body.state == "closed"
        assert body.milestone == "v2.0"
        assert body.labels == ["enhancement"]
        updated_issue
      end)

      params = %{
        client: @mock_client,
        owner: "test-owner",
        repo: "test-repo",
        number: 42,
        title: "Updated Title",
        body: "Updated Body",
        assignee: "new-assignee",
        state: "closed",
        milestone: "v2.0",
        labels: ["enhancement"]
      }

      assert {:ok, result} = Issues.Update.run(params, %{})
      assert result.status == "success"
      assert result.data == updated_issue
      assert result.raw == updated_issue
    end

    test "updates issue with minimal parameters" do
      expect(Tentacat.Issues, :update, fn client, owner, repo, number, body ->
        assert client == @mock_client
        assert owner == "test-owner"
        assert repo == "test-repo"
        assert number == 1
        assert body.title == nil
        assert body.body == nil
        assert body.assignee == nil
        assert body.state == nil
        assert body.milestone == nil
        assert body.labels == nil
        @mock_issue_response
      end)

      params = %{
        client: @mock_client,
        owner: "test-owner",
        repo: "test-repo",
        number: 1,
        title: nil,
        body: nil,
        assignee: nil,
        state: nil,
        milestone: nil,
        labels: nil
      }

      assert {:ok, result} = Issues.Update.run(params, %{})
      assert result.status == "success"
      assert result.data == @mock_issue_response
    end

    test "updates only title and state" do
      expect(Tentacat.Issues, :update, fn _client, _owner, _repo, _number, body ->
        assert body.title == "New Title Only"
        assert body.state == "open"
        assert body.body == nil
        @mock_issue_response
      end)

      params = %{
        client: @mock_client,
        owner: "test-owner",
        repo: "test-repo",
        number: 5,
        title: "New Title Only",
        body: nil,
        assignee: nil,
        state: "open",
        milestone: nil,
        labels: nil
      }

      assert {:ok, result} = Issues.Update.run(params, %{})
      assert result.status == "success"
    end
  end
end
