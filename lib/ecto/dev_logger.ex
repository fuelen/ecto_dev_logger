defmodule Ecto.DevLogger do
  @moduledoc """
  An alternative logger for Ecto queries.

  It inlines bindings into the query, so it is easy to copy-paste logged SQL and run it in any IDE for debugging without
  manual transformation of common elixir terms to string representation (binary UUID, DateTime, Decimal, json, etc).
  Also, it highlights db time to make slow queries noticeable. Source table and inlined bindings are highlighted as well.
  """

  require Logger

  @doc """
  Attaches `telemetry_handler/4` to application.
  """
  @spec install(repo_module :: module()) :: :ok
  def install(repo_module) when is_atom(repo_module) do
    config = repo_module.config()

    if config[:log] == false do
      :telemetry.attach(
        "ecto.dev_logger",
        config[:telemetry_prefix] ++ [:query],
        &__MODULE__.telemetry_handler/4,
        nil
      )
    end

    :ok
  end

  defp oban_query?(metadata) do
    not is_nil(metadata[:options][:oban_conf])
  end

  @doc "Telemetry handler which logs queries."
  @spec telemetry_handler(
          :telemetry.event_name(),
          :telemetry.event_measurements(),
          :telemetry.event_metadata(),
          :telemetry.handler_config()
        ) :: :ok
  def telemetry_handler(_event_name, measurements, metadata, _config) do
    unless oban_query?(metadata) do
      query_string = String.Chars.to_string(metadata.query)
      color = sql_color(query_string)
      repo_adapter = metadata[:repo].__adapter__()

      query_string =
        metadata.params
        |> Enum.with_index(1)
        |> Enum.reverse()
        |> Enum.reduce(query_string, fn {binding, index}, query ->
          replacement =
            to_string([
              IO.ANSI.color(0, 2, 3),
              stringify_ecto_params(binding, :root),
              apply(IO.ANSI, color, [])
            ])

          replace_params(repo_adapter, query, index, replacement)
        end)

      Logger.debug(
        fn -> log_sql_iodata(query_string, measurements, metadata, color) end,
        ansi_color: color
      )
    end

    :ok
  end

  defp log_sql_iodata(query, measurements, %{result: result, source: source}, color) do
    [
      "QUERY",
      ?\s,
      log_ok_error(result),
      log_ok_source(source, color),
      log_time("db", measurements, :query_time, true, color),
      log_time("decode", measurements, :decode_time, false, color),
      ?\n,
      query
    ]
  end

  defp log_ok_error({:ok, _res}), do: "OK"
  defp log_ok_error({:error, _err}), do: "ERROR"

  defp log_ok_source(nil, _color), do: ""

  defp log_ok_source(source, color),
    do: [" source=", IO.ANSI.blue(), inspect(source), apply(IO.ANSI, color, [])]

  defp log_time(label, measurements, key, force, color) do
    case measurements do
      %{^key => time} ->
        us = System.convert_time_unit(time, :native, :microsecond)
        ms = div(us, 100) / 10

        if force or ms > 0 do
          line = [?\s, label, ?=, :io_lib_format.fwrite_g(ms), ?m, ?s]

          case duration_color(ms) do
            nil -> line
            duration_color -> [duration_color, line, apply(IO.ANSI, color, [])]
          end
        else
          []
        end

      %{} ->
        []
    end
  end

  @colorize_step 25
  defp duration_color(duration) do
    # don't colorize if duration < @colorize_step
    duration = duration - @colorize_step

    if duration > 0 do
      # then every @colorize_step ms apply color from RGB(5, 5, 0) to RGB(5, 0, 0) (simple gradient from yellow to red)
      green = 5 - min(div(floor(duration), @colorize_step), 5)
      IO.ANSI.color(5, green, 0)
    end
  end

  defp sql_color("SELECT" <> _), do: :cyan
  defp sql_color("ROLLBACK" <> _), do: :red
  defp sql_color("LOCK" <> _), do: :white
  defp sql_color("INSERT" <> _), do: :green
  defp sql_color("UPDATE" <> _), do: :yellow
  defp sql_color("DELETE" <> _), do: :red
  defp sql_color("begin" <> _), do: :magenta
  defp sql_color("commit" <> _), do: :magenta
  defp sql_color(_), do: :default_color

  defp stringify_ecto_params(binding, _level)
       when is_float(binding) or is_integer(binding) or is_atom(binding),
       do: to_string(binding)

  defp stringify_ecto_params(%Decimal{} = binding, _level), do: to_string(binding)

  defp stringify_ecto_params(binding, level) when is_binary(binding) do
    string =
      with <<_::128>> <- binding,
           {:ok, string} <- Ecto.UUID.load(binding) do
        string
      else
        _ -> binding
      end

    case level do
      :root -> "'#{string}'"
      :child -> string
    end
  end

  defp stringify_ecto_params(binding, :root) when is_list(binding) do
    "'{" <> Enum.map_join(binding, ",", &stringify_ecto_params(&1, :child)) <> "}'"
  end

  defp stringify_ecto_params(%module{} = date, :root)
       when module in [Date, DateTime, NaiveDateTime] do
    "'#{stringify_ecto_params(date, :child)}'"
  end

  defp stringify_ecto_params(%{} = map, :root) when not is_struct(map) do
    "'#{stringify_ecto_params(map, :child)}'"
  end

  defp stringify_ecto_params(composite, :root) when is_tuple(composite) do
    values =
      composite
      |> Tuple.to_list()
      |> Enum.map(&stringify_ecto_params(&1, :child))
      |> Enum.join(", ")

    "'(#{values})'"
  end

  defp stringify_ecto_params(%Date{} = date, :child) do
    to_string(date)
  end

  defp stringify_ecto_params(%NaiveDateTime{} = datetime, :child) do
    NaiveDateTime.to_iso8601(datetime)
  end

  defp stringify_ecto_params(%DateTime{} = datetime, :child) do
    DateTime.to_iso8601(datetime)
  end

  defp stringify_ecto_params(%{} = map, :child) when not is_struct(map) do
    Jason.encode!(map)
  end

  defp replace_params(Ecto.Adapters.Tds, query, index, replacement) do
    String.replace(query, "@#{index}", replacement)
  end

  defp replace_params(_adapter, query, index, replacement) do
    String.replace(query, "$#{index}", replacement)
  end
end
