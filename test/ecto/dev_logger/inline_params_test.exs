defmodule Ecto.DevLogger.InlineParamsTest do
  use ExUnit.Case, async: true

  test "inlines TDS named parameters" do
    params = [
      %{__struct__: Tds.Parameter, name: "@name", value: "O'Brien @1"},
      %{__struct__: Tds.Parameter, name: "@attempts", value: 3}
    ]

    query =
      Ecto.DevLogger.inline_params(
        "UPDATE posts SET name = @name, attempts = @attempts WHERE marker = @name_suffix",
        params,
        :yellow,
        Ecto.Adapters.Tds
      )

    assert query |> to_string() |> strip_ansi() ==
             "UPDATE posts SET name = 'O''Brien @1', attempts = 3 WHERE marker = @name_suffix"
  end

  test "continues to inline TDS numbered parameters" do
    query = Ecto.DevLogger.inline_params("SELECT @1, @2", [nil, 3], :yellow, Ecto.Adapters.Tds)

    assert query |> to_string() |> strip_ansi() == "SELECT NULL, 3"
  end

  defp strip_ansi(string), do: Regex.replace(~r/\e\[[0-9;]*[mGKH]/, string, "")
end
