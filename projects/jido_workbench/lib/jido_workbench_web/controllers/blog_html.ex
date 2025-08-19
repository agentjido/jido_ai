defmodule JidoWorkbenchWeb.BlogHTML do
  use JidoWorkbenchWeb, :html

  # alias JidoWorkbench.Blog.Post
  # alias JidoWorkbenchWeb.WorkbenchLayout

  import JidoWorkbenchWeb.WorkbenchLayout, only: [workbench_layout: 1]

  embed_templates "blog_html/*"

  def format_date(date) do
    Calendar.strftime(date, "%B %d, %Y")
  end

  def format_rfc822_date(date) do
    Calendar.strftime(date, "%a, %d %b %Y %H:%M:%S GMT")
  end

  def preview(body) do
    # Get first 150 characters of post body, ending at word boundary
    body
    |> String.slice(0, 150)
    |> String.split(~r/\s/)
    |> Enum.drop(-1)
    |> Enum.join(" ")
    |> Kernel.<>("...")
  end
end
