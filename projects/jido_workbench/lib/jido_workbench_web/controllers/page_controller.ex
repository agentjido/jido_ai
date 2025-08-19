defmodule JidoWorkbenchWeb.PageController do
  use JidoWorkbenchWeb, :controller

  @v1_errors [
    text_input_with_error: {"can't be blank", [validation: :required]},
    text_input_with_error: {"must be at least 2 characters", [validation: :minimum]},
    number_input_with_error: {"can't be blank", [validation: :required]},
    email_input_with_error: {"can't be blank", [validation: :required]},
    password_input_with_error: {"can't be blank", [validation: :required]},
    search_input_with_error: {"can't be blank", [validation: :required]},
    telephone_input_with_error: {"can't be blank", [validation: :required]},
    url_input_with_error: {"can't be blank", [validation: :required]},
    time_input_with_error: {"can't be blank", [validation: :required]},
    time_select_with_error: {"can't be blank", [validation: :required]},
    date_select_with_error: {"can't be blank", [validation: :required]},
    date_input_with_error: {"can't be blank", [validation: :required]},
    datetime_select_with_error: {"can't be blank", [validation: :required]},
    datetime_local_input_with_error: {"can't be blank", [validation: :required]},
    color_input_with_error: {"can't be blank", [validation: :required]},
    file_input_with_error: {"can't be blank", [validation: :required]},
    range_input_with_error: {"can't be blank", [validation: :required]},
    textarea_with_error: {"can't be blank", [validation: :required]},
    select_with_error: {"can't be blank", [validation: :required]},
    switch_with_error: {"can't be blank", [validation: :required]},
    checkbox_with_error: {"can't be blank", [validation: :required]},
    checkbox_group_col_with_error: {"can't be blank", [validation: :required]},
    checkbox_group_row_with_error: {"can't be blank", [validation: :required]},
    radio_with_error: {"can't be blank", [validation: :required]},
    radio_group_col_with_error: {"can't be blank", [validation: :required]},
    radio_group_row_with_error: {"can't be blank", [validation: :required]}
  ]

  @v1_params %{
    "text_input_with_error" => "",
    "number_input_with_error" => "",
    "email_input_with_error" => "",
    "password_input_with_error" => "",
    "search_input_with_error" => "",
    "telephone_input_with_error" => "",
    "url_input_with_error" => "",
    "time_input_with_error" => "",
    "time_select_with_error" => nil,
    "date_select_with_error" => nil,
    "date_input_with_error" => "",
    "datetime_select_with_error" => nil,
    "datetime_local_input_with_error" => nil,
    "color_input_with_error" => "",
    "file_input_with_error" => "",
    "range_input_with_error" => "",
    "textarea_with_error" => "",
    "select_with_error" => "",
    "switch_with_error" => "",
    "checkbox_with_error" => "",
    "checkbox_group_col_with_error" => "",
    "checkbox_group_row_with_error" => "",
    "radio_with_error" => "",
    "radio_group_col_with_error" => "",
    "radio_group_row_with_error" => ""
  }

  @v2_errors [
    text_with_error: {"can't be blank", [validation: :required]},
    text_with_error: {"must be at least 2 characters", [validation: :minimum]},
    number_with_error: {"can't be blank", [validation: :required]},
    email_with_error: {"can't be blank", [validation: :required]},
    password_with_error: {"can't be blank", [validation: :required]},
    search_with_error: {"can't be blank", [validation: :required]},
    tel_with_error: {"can't be blank", [validation: :required]},
    url_with_error: {"can't be blank", [validation: :required]},
    time_with_error: {"can't be blank", [validation: :required]},
    date_with_error: {"can't be blank", [validation: :required]},
    week_with_error: {"can't be blank", [validation: :required]},
    month_with_error: {"can't be blank", [validation: :required]},
    datetime_local_with_error: {"can't be blank", [validation: :required]},
    color_with_error: {"can't be blank", [validation: :required]},
    file_with_error: {"can't be blank", [validation: :required]},
    range_with_error: {"can't be blank", [validation: :required]},
    textarea_with_error: {"can't be blank", [validation: :required]},
    select_with_error: {"can't be blank", [validation: :required]},
    switch_with_error: {"can't be blank", [validation: :required]},
    checkbox_with_error: {"can't be blank", [validation: :required]},
    checkbox_group_col_with_error: {"can't be blank", [validation: :required]},
    checkbox_group_row_with_error: {"can't be blank", [validation: :required]},
    radio_with_error: {"can't be blank", [validation: :required]},
    radio_group_col_with_error: {"can't be blank", [validation: :required]},
    radio_group_row_with_error: {"can't be blank", [validation: :required]}
  ]

  @v2_params %{
    "text_with_error" => "",
    "number_with_error" => "",
    "email_with_error" => "",
    "password_with_error" => "",
    "search_with_error" => "",
    "tel_with_error" => "",
    "url_with_error" => "",
    "time_with_error" => "",
    "date_with_error" => "",
    "week_with_error" => "",
    "month_with_error" => "",
    "datetime_local_with_error" => "",
    "color_with_error" => "",
    "file_with_error" => "",
    "range_with_error" => "",
    "textarea_with_error" => "",
    "select_with_error" => "",
    "switch_with_error" => "",
    "checkbox_with_error" => "",
    "checkbox_group_col_with_error" => "",
    "checkbox_group_row_with_error" => "",
    "radio_with_error" => "",
    "radio_group_col_with_error" => "",
    "radio_group_row_with_error" => ""
  }

  def home(conn, _params) do
    v1_changeset =
      %Ecto.Changeset{action: :update, data: %{name: ""}, errors: @v1_errors}
      |> Map.put(:params, @v1_params)

    v2_form =
      %Ecto.Changeset{action: :update, data: %{name: ""}, errors: @v2_errors}
      |> Map.put(:params, @v2_params)
      |> Phoenix.Component.to_form(as: :object)

    conn =
      conn
      |> assign(:changeset, v1_changeset)
      |> assign(:form, v2_form)

    render(conn, :home, active_tab: :home)
  end
end
