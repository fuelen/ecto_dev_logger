defmodule Ecto.DevLogger do
  @moduledoc """
  An alternative logger for Ecto queries.

  It inlines bindings into the query, so it is easy to copy-paste logged SQL and run it in any IDE for debugging without
  manual transformation of common elixir terms to string representation (binary UUID, DateTime, Decimal, json, etc).
  Also, it highlights db time to make slow queries noticeable. Source table and inlined bindings are highlighted as well.
  """

  require Logger

  @type option :: {:log_repo_name, boolean()} | {:ignore_event, (metadata :: map() -> boolean())}

  @doc """
  Attaches `telemetry_handler/4` to application.

  Returns the result from the call to `:telemetry.attach/4` or `:ok` if the repo has default logging enabled.

  ## Options

  * `:log_repo_name` - when truthy will add the repo name into the log.
  * `:ignore_event` - a callback which allows to skip some telemetry events thus skip printing logs.
  By default, the library ignores events from `Oban` and events related to migration queries.
  These checks are not overridable by `:ignore_event` callback and have priority over it.
  * `:before_inline_callback` - a callback which allows to modify the query before inlining of bindings.
  You can use this option to format the query using external utility, like `pgformatter`, etc.

  To ignore logging for a single Repo operation, pass `log: false` via `telemetry_options` to that call, for example:

      Repo.query!("SELECT 1", [], telemetry_options: [log: false])
      Repo.insert!(changeset, telemetry_options: [log: false])
  """
  @spec install(repo_module :: module(), opts :: [option()]) :: :ok | {:error, :already_exists}
  def install(repo_module, opts \\ []) when is_atom(repo_module) do
    config = repo_module.config()

    if config[:log] == false do
      :telemetry.attach(
        handler_id(repo_module),
        config[:telemetry_prefix] ++ [:query],
        &__MODULE__.telemetry_handler/4,
        opts
      )
    else
      :ok
    end
  end

  @doc """
  Detaches a previously attached handler for a given Repo.

  Returns the result from the call to `:telemetry.detach/1`
  """
  @spec uninstall(repo_module :: module()) :: :ok | {:error, :not_found}
  def uninstall(repo_module) when is_atom(repo_module) do
    :telemetry.detach(handler_id(repo_module))
  end

  @doc """
  Gets the handler_id for a given Repo.
  """
  @spec handler_id(repo_module :: module()) :: list()
  def handler_id(repo_module) do
    config = repo_module.config()
    [:ecto_dev_logger] ++ config[:telemetry_prefix]
  end

  defp oban_query?(metadata) do
    not is_nil(metadata[:options][:oban_conf])
  end

  defp schema_migration?(metadata) do
    metadata[:options][:schema_migration] == true
  end

  defp ignore_event?(config, metadata) do
    metadata[:options][:log] == false or oban_query?(metadata) or schema_migration?(metadata) or
      (config[:ignore_event] || (&always_false/1)).(metadata)
  end

  defp always_false(_), do: false

  @doc "Telemetry handler which logs queries."
  @spec telemetry_handler(
          :telemetry.event_name(),
          :telemetry.event_measurements(),
          :telemetry.event_metadata(),
          [option()]
        ) :: :ok
  def telemetry_handler(_event_name, measurements, metadata, config) do
    if ignore_event?(config, metadata) do
      :ok
    else
      query = String.Chars.to_string(metadata.query)
      color = sql_color(query)
      repo_adapter = metadata[:repo].__adapter__()
      before_inline_callback = config[:before_inline_callback] || (&Function.identity/1)
      params = preprocess_params(metadata)

      Logger.debug(
        fn ->
          query
          |> before_inline_callback.()
          |> inline_params(params, color, repo_adapter)
          |> log_sql_iodata(measurements, metadata, color, config)
        end,
        ansi_color: color
      )
    end
  end

  @doc false
  def inline_params(query, params, _return_to_color, _repo_adapter) when map_size(params) == 0 do
    query
  end

  def inline_params(query, params, return_to_color, repo_adapter)
      when repo_adapter in [Ecto.Adapters.Postgres, Ecto.Adapters.Tds] do
    params_by_index =
      params
      |> Enum.with_index(1)
      |> Map.new(fn {value, index} -> {index, value} end)

    placeholder_with_number_regex = placeholder_with_number_regex(repo_adapter)

    String.replace(query, placeholder_with_number_regex, fn
      <<_prefix::utf8, index::binary>> = replacement ->
        case Map.fetch(params_by_index, String.to_integer(index)) do
          {:ok, value} ->
            try do
              value
              |> Ecto.DevLogger.PrintableParameter.to_expression()
              |> colorize(IO.ANSI.color(0, 2, 3), apply(IO.ANSI, return_to_color, []))
            rescue
              Protocol.UndefinedError ->
                value
                |> inspect()
                |> colorize(IO.ANSI.color(5, 0, 0), apply(IO.ANSI, return_to_color, []))
            end

          :error ->
            replacement
        end
    end)
  end

  def inline_params(query, params, return_to_color, repo_adapter)
      when repo_adapter in [Ecto.Adapters.MyXQL, Ecto.Adapters.SQLite3] do
    params_by_index =
      params
      |> Enum.with_index()
      |> Map.new(fn {value, index} -> {index, value} end)

    query
    |> String.split(~r{\?(?!")})
    |> Enum.map_reduce(0, fn elem, index ->
      formatted_value =
        case Map.fetch(params_by_index, index) do
          {:ok, value} ->
            value
            |> Ecto.DevLogger.PrintableParameter.to_expression()
            |> colorize(IO.ANSI.color(0, 2, 3), apply(IO.ANSI, return_to_color, []))

          :error ->
            []
        end

      {[elem, formatted_value], index + 1}
    end)
    |> elem(0)
  end

  defp preprocess_params(metadata) do
    cast_params = Map.get(metadata, :cast_params)

    if is_list(cast_params) do
      Enum.zip_with(
        [metadata.params, cast_params],
        fn
          [[p | _] = integers, [c | _] = atoms] when is_integer(p) and is_atom(c) ->
            Enum.zip_with([integers, atoms], fn [i, a] ->
              %Ecto.DevLogger.NumericEnum{integer: i, atom: a}
            end)

          [integer, atom] when is_integer(integer) and is_atom(atom) ->
            %Ecto.DevLogger.NumericEnum{integer: integer, atom: atom}

          [[hex | _], [uuid | _] = uuids] when byte_size(hex) == 16 and byte_size(uuid) == 36 ->
            uuids

          [hex, uuid] when byte_size(hex) == 16 and byte_size(uuid) == 36 ->
            uuid

          [param, _] ->
            param
        end
      )
    else
      metadata.params
    end
  end

  defp placeholder_with_number_regex(Ecto.Adapters.Postgres), do: ~r/\$\d+/
  defp placeholder_with_number_regex(Ecto.Adapters.Tds), do: ~r/@\d+/

  defp log_sql_iodata(query, measurements, metadata, color, config) do
    [
      "QUERY",
      ?\s,
      log_ok_error(metadata.result),
      log_ok_source(metadata.source, color),
      log_repo(metadata.repo, color, config),
      log_time("db", measurements, :query_time, true, color),
      log_time("decode", measurements, :decode_time, false, color),
      ?\n,
      query,
      log_stacktrace(metadata[:stacktrace], metadata.repo)
    ]
  end

  defp log_ok_error({:ok, _res}), do: "OK"
  defp log_ok_error({:error, _err}), do: "ERROR"

  defp log_repo(nil, _color, _config), do: ""

  defp log_repo(repo, color, config) do
    Keyword.get(config, :log_repo_name, false)
    |> case do
      true -> [" repo=", colorize(inspect(repo), IO.ANSI.blue(), apply(IO.ANSI, color, []))]
      _ -> ""
    end
  end

  defp log_ok_source(nil, _color), do: ""

  defp log_ok_source(source, color),
    do: [" source=", colorize(inspect(source), IO.ANSI.blue(), apply(IO.ANSI, color, []))]

  defp log_time(label, measurements, key, force, color) do
    case measurements do
      %{^key => time} ->
        us = System.convert_time_unit(time, :native, :microsecond)
        ms = div(us, 100) / 10

        if force or ms > 0 do
          line = [?\s, label, ?=, :io_lib_format.fwrite_g(ms), ?m, ?s]

          case duration_color(ms) do
            nil -> line
            duration_color -> colorize(line, duration_color, apply(IO.ANSI, color, []))
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
    if IO.ANSI.enabled?() do
      # don't colorize if duration < @colorize_step
      duration = duration - @colorize_step

      if duration > 0 do
        # then every @colorize_step ms apply color from RGB(5, 5, 0) to RGB(5, 0, 0) (simple gradient from yellow to red)
        green = 5 - min(div(floor(duration), @colorize_step), 5)
        IO.ANSI.color(5, green, 0)
      end
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

  defp colorize(term, color, return_to_color) do
    if IO.ANSI.enabled?() do
      [color, term, return_to_color]
    else
      term
    end
  end

  defp log_stacktrace(stacktrace, repo) do
    with [_ | _] <- stacktrace,
         {module, function, arity, info} <- last_non_ecto(Enum.reverse(stacktrace), repo, nil) do
      [
        if(IO.ANSI.enabled?(), do: IO.ANSI.light_black(), else: ""),
        ?\n,
        "↳ ",
        Exception.format_mfa(module, function, arity),
        log_stacktrace_info(info)
      ]
    else
      _ -> []
    end
  end

  defp log_stacktrace_info([file: file, line: line] ++ _) do
    [", at: ", file, ?:, Integer.to_string(line)]
  end

  defp log_stacktrace_info(_) do
    []
  end

  @repo_modules [Ecto.Repo.Queryable, Ecto.Repo.Schema, Ecto.Repo.Transaction]

  defp last_non_ecto([{mod, _, _, _} | _stacktrace], repo, last)
       when mod == repo or mod in @repo_modules,
       do: last

  defp last_non_ecto([last | stacktrace], repo, _last), do: last_non_ecto(stacktrace, repo, last)
  defp last_non_ecto([], _repo, last), do: last
end
