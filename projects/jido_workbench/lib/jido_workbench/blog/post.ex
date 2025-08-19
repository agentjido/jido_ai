defmodule JidoWorkbench.Blog.Post do
  @enforce_keys [:id, :author, :title, :body, :description, :tags, :date, :path]
  defstruct [:id, :author, :title, :body, :description, :tags, :date, :path]

  def build(filename, attrs, body) do
    [year, month_day_id] = filename |> Path.rootname() |> Path.split() |> Enum.take(-2)
    [month, day, id] = String.split(month_day_id, "-", parts: 3)
    date = Date.from_iso8601!("#{year}-#{month}-#{day}")
    base_path = Application.app_dir(:jido_workbench)
    path = String.replace(filename, base_path, "")
    struct!(__MODULE__, [id: id, date: date, body: body, path: path] ++ Map.to_list(attrs))
  end
end
