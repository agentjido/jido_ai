defmodule JidoWorkbenchWeb.ErrorJSONTest do
  use JidoWorkbenchWeb.ConnCase, async: true
  @moduletag :skip
  test "renders 404" do
    assert JidoWorkbenchWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert JidoWorkbenchWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
