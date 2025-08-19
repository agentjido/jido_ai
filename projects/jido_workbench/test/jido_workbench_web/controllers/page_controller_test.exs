defmodule JidoWorkbenchWeb.PageControllerTest do
  use JidoWorkbenchWeb.ConnCase
  @moduletag :skip
  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "<main>"
  end
end
