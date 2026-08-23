defmodule Ecto.DevLogger.TimingsTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  defmodule Repo do
    def __adapter__, do: Ecto.Adapters.Postgres
  end

  @measurements %{
    query_time: System.convert_time_unit(1, :millisecond, :native),
    decode_time: System.convert_time_unit(2, :millisecond, :native),
    queue_time: System.convert_time_unit(3, :millisecond, :native),
    idle_time: System.convert_time_unit(4, :millisecond, :native),
    total_time: System.convert_time_unit(6, :millisecond, :native)
  }

  @metadata %{
    query: "SELECT 1",
    params: [],
    cast_params: nil,
    repo: Repo,
    result: {:ok, :result},
    source: nil,
    stacktrace: nil,
    options: []
  }

  test "logs query and decode timings by default" do
    log =
      capture_log(fn -> Ecto.DevLogger.telemetry_handler([], @measurements, @metadata, []) end)

    assert log =~ " db=1.0ms decode=2.0ms"
    refute log =~ " queue="
    refute log =~ " idle="
    refute log =~ " total="
  end

  test "logs explicitly enabled timings in a fixed order" do
    config = [timings: [:total, :idle, :queue, :query]]

    log =
      capture_log(fn ->
        Ecto.DevLogger.telemetry_handler([], @measurements, @metadata, config)
      end)

    assert log =~ " db=1.0ms queue=3.0ms idle=4.0ms total=6.0ms"
    refute log =~ " decode="
  end

  test "can hide all timings" do
    log =
      capture_log(fn ->
        Ecto.DevLogger.telemetry_handler([], @measurements, @metadata, timings: [])
      end)

    refute log =~ ~r/ (?:db|decode|queue|idle|total)=/
  end
end
