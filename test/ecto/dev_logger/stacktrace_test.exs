defmodule Ecto.DevLogger.StacktraceTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  defmodule Repo do
    def config do
      [
        log: false,
        telemetry_prefix: [:ecto_dev_logger, :stacktrace_test],
        log_stacktrace_mfa: {Ecto.DevLogger.StacktraceTest, :stacktrace_entries, [2]}
      ]
    end

    def __adapter__, do: Ecto.Adapters.Postgres
  end

  def stacktrace_entries(stacktrace, %{repo: Repo}, count), do: Enum.take(stacktrace, count)

  setup do
    Ecto.DevLogger.uninstall(Repo)
    assert :ok = Ecto.DevLogger.install(Repo)
    on_exit(fn -> Ecto.DevLogger.uninstall(Repo) end)
  end

  test "uses the Repo log_stacktrace_mfa configuration" do
    stacktrace = [
      {__MODULE__, :first_call, 1, [file: ~c"first.ex", line: 10]},
      {__MODULE__, :second_call, 2, [file: ~c"second.ex", line: 20]},
      {__MODULE__, :not_logged, 3, [file: ~c"third.ex", line: 30]}
    ]

    metadata = %{
      query: "SELECT 1",
      params: [],
      cast_params: nil,
      repo: Repo,
      result: {:ok, :result},
      source: nil,
      stacktrace: stacktrace,
      options: []
    }

    log =
      capture_log(fn ->
        :telemetry.execute(
          Repo.config()[:telemetry_prefix] ++ [:query],
          %{query_time: 0},
          metadata
        )
      end)

    plain_log = Regex.replace(~r/\e\[[0-9;]*[mGKH]/, log, "")

    assert plain_log =~ "↳ Ecto.DevLogger.StacktraceTest.first_call/1, at: first.ex:10"
    assert plain_log =~ "  Ecto.DevLogger.StacktraceTest.second_call/2, at: second.ex:20"
    refute plain_log =~ "not_logged"
  end
end
