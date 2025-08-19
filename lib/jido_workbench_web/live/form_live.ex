defmodule JidoWorkbenchWeb.FormLive do
  use JidoWorkbenchWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    changeset = build_changeset()

    {:ok,
     assign(socket,
       form: to_form(changeset, as: :object),
       form2: to_form(changeset, as: :object2),
       active_tab: :form
     )}
  end

  @impl true
  def handle_event("validate", %{"object" => object_params}, socket) do
    changeset =
      object_params
      |> build_changeset()
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: :object))}
  end

  @impl true
  def handle_event("submit", %{"object" => object_params}, socket) do
    changeset = build_changeset(object_params)

    case validate_changeset(changeset) do
      {:ok, _} ->
        socket =
          socket
          |> put_flash(:success, "Object successfully created")
          |> assign(form: to_form(changeset, as: :object))

        {:noreply, socket}

      {:error, changeset} ->
        socket =
          socket
          |> put_flash(:error, inspect(changeset.errors))

        {:noreply, assign(socket, form: to_form(changeset, as: :object))}
    end
  end

  defp build_changeset(params \\ %{}) do
    data = %{}

    types = %{
      text: :string,
      select: :string,
      checkbox_group: {:array, :string},
      radio_group: :string,
      textarea: :string,
      checkbox: :boolean,
      color: :string,
      date: :date,
      datetime: :naive_datetime,
      email: :string,
      file: :string,
      hidden: :string,
      month: :string,
      number: :integer,
      password: :string,
      radio: :string,
      range: :integer,
      search: :string,
      tel: :string,
      time: :time,
      url: :string,
      week: :string,
      switch: :boolean
    }

    {data, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Ecto.Changeset.validate_required([:text])
    |> Ecto.Changeset.validate_acceptance(:checkbox)
    |> Ecto.Changeset.validate_length(:text, min: 3, max: 50)
  end

  defp validate_changeset(changeset) do
    Ecto.Changeset.apply_action(changeset, :validate)
  end
end
