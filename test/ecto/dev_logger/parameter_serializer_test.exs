defmodule Ecto.DevLogger.ParameterSerializerTest do
  use ExUnit.Case

  defmodule Repo do
    use Ecto.Repo, adapter: Ecto.Adapters.Postgres, otp_app: :does_not_matter
  end

  defmodule DateRange do
    defstruct lower: nil,
              lower_inclusive: true,
              upper: nil,
              upper_inclusive: false
  end

  defmodule DateRange.Type do
    alias Postgrex.Range
    use Ecto.Type

    defp from_postgrex(%Range{} = range), do: struct!(DateRange, Map.from_struct(range))
    defp to_postgrex(%DateRange{} = range), do: struct!(Range, Map.from_struct(range))

    @doc false
    def cast(nil), do: {:ok, nil}
    def cast(%Range{} = range), do: {:ok, from_postgrex(range)}
    def cast(%DateRange{} = range), do: {:ok, range}

    def cast(%{lower: lower, upper: upper} = range_map) do
      map =
        range_map
        |> Map.put(:lower, ensure_date(lower))
        |> Map.put(:upper, ensure_date(upper))

      {:ok, struct!(DateRange, map)}
    end

    def cast(_), do: :error

    def load(nil), do: {:ok, nil}
    def load(%Range{} = range), do: {:ok, from_postgrex(range)}
    def load(_), do: :error

    def dump(nil), do: {:ok, nil}
    def dump(%DateRange{} = range), do: {:ok, to_postgrex(range)}
    def dump(_), do: :error

    def type, do: :daterange

    defp ensure_date(%Date{} = date), do: date
    defp ensure_date("empty"), do: :empty
    defp ensure_date(date) when is_binary(date), do: Date.from_iso8601!(date)
    defp ensure_date(other), do: other
  end

  defmodule Transaction do
    use Ecto.Schema

    @primary_key {:id, :binary_id, read_after_writes: true}
    schema "transactions" do
      field(:coverage, DateRange.Type)
    end
  end

  defmodule Serializer do
    use Ecto.DevLogger.ParameterSerializer

    def stringify_ecto_params(%Postgrex.Range{} = range) do
      lower_inclusive(range.lower_inclusive) <>
        to_string(range.lower) <>
        ", " <>
        to_string(range.upper) <>
        upper_inclusive(range.upper_inclusive)
    end

    defp lower_inclusive(true), do: "["
    defp lower_inclusive(false), do: "("
    defp upper_inclusive(true), do: "]"
    defp upper_inclusive(false), do: ")"
  end

  setup tags do
    opts =
      case tags[:configure_serializer] do
        true -> [serializer: Serializer]
        _ -> []
      end

    Repo.__adapter__().storage_down(config())
    Repo.__adapter__().storage_up(config())
    {:ok, _} = Repo.start_link(config())

    :telemetry.attach(
      "ecto.dev_logger",
      [:my_test_app, :repo, :query],
      &Ecto.DevLogger.telemetry_handler/4,
      opts
    )

    Repo.query!("""
    CREATE TABLE transactions (
      id uuid PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
      coverage daterange
    )
    """)

    on_exit(fn ->
      :telemetry.detach("ecto.dev_logger")
      Repo.__adapter__().storage_down(config())
    end)
  end

  import ExUnit.CaptureLog

  @tag configure_serializer: false
  test "without serializer, logger fails" do
    log =
      capture_log(fn ->
        _ =
          Repo.insert!(%Transaction{
            coverage: %DateRange{lower: ~D"2022-04-22", upper: ~D"2022-04-29"}
          })

        Enum.each([0.02, 0.025, 0.05, 0.075, 0.1, 0.125, 0.15], fn duration ->
          Ecto.Adapters.SQL.query!(Repo, "SELECT pg_sleep(#{duration})", [])
        end)
      end)

    assert log =~ "[error]"
    assert log =~ "%Postgrex.Range{"
  end

  @tag configure_serializer: true
  test "with serializer, logger does not fail" do
    log =
      capture_log(fn ->
        _ =
          Repo.insert!(%Transaction{
            coverage: %DateRange{lower: ~D"2022-04-22", upper: ~D"2022-04-29"}
          })

        Enum.each([0.02, 0.025, 0.05, 0.075, 0.1, 0.125, 0.15], fn duration ->
          Ecto.Adapters.SQL.query!(Repo, "SELECT pg_sleep(#{duration})", [])
        end)
      end)

    assert log =~ "[2022-04-22, 2022-04-29)"
  end

  defp config do
    [
      telemetry_prefix: [:my_test_app, :repo],
      otp_app: :my_test_app,
      timeout: 15000,
      migration_timestamps: [type: :naive_datetime_usec],
      database: "ecto_dev_logger_test",
      hostname: "localhost",
      username: "postgres",
      password: "postgres",
      port: 5432,
      log: false,
      pool_size: 10
    ]
  end
end
