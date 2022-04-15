defmodule Ecto.DevLoggerTest do
  use ExUnit.Case

  defmodule Repo do
    use Ecto.Repo, adapter: Ecto.Adapters.Postgres, otp_app: :does_not_matter
  end

  defmodule Money do
    defstruct [:currency, :value]
  end

  defmodule Money.Ecto.Type do
    use Ecto.ParameterizedType

    def type(_params), do: :composite_type

    def init(_opts), do: %{}

    def cast(_data, _params), do: {:ok, nil}
    def load(_data, _loader, _params), do: {:ok, nil}

    def dump(nil, _dumper, _params), do: {:ok, nil}
    def dump(data, _dumper, _params), do: {:ok, {data.currency, data.value}}

    def equal?(a, b, _params) do
      a == b
    end
  end

  defmodule Post do
    use Ecto.Schema

    @primary_key {:id, :binary_id, read_after_writes: true}
    schema "posts" do
      field(:string, :string)
      field(:map, :map)
      field(:integer, :integer)
      field(:decimal, :decimal)
      field(:date, :date)
      field(:array_of_strings, {:array, :string})
      field(:datetime, :utc_datetime_usec)
      field(:naive_datetime, :naive_datetime_usec)
      field(:money, Money.Ecto.Type)
    end
  end

  setup do
    Repo.__adapter__().storage_down(config())
    Repo.__adapter__().storage_up(config())
    {:ok, _} = Repo.start_link(config())

    Repo.query!("CREATE EXTENSION \"pgcrypto\";")

    Repo.query!("""
    CREATE TYPE money_type AS (currency char(3), value integer);
    """)

    Repo.query!("""
    CREATE TABLE posts (
      id uuid PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
      string text,
      map jsonb,
      integer integer,
      decimal numeric,
      date date,
      array_of_strings text[],
      money money_type,
      datetime timestamp without time zone NOT NULL,
      naive_datetime timestamp without time zone NOT NULL
    )
    """)

    :telemetry.attach(
      "ecto.dev_logger",
      [:my_test_app, :repo, :query],
      &Ecto.DevLogger.telemetry_handler/4,
      nil
    )

    on_exit(fn ->
      Repo.__adapter__().storage_down(config())
    end)
  end

  test "everything" do
    %{id: post_id} =
      Repo.insert!(%Post{
        string: "Post 1",
        map: %{test: true},
        integer: 0,
        decimal: Decimal.from_float(0.12),
        date: Date.utc_today(),
        array_of_strings: ["hello", "world"],
        money: %Money{currency: "USD", value: 390},
        datetime: DateTime.utc_now(),
        naive_datetime: NaiveDateTime.utc_now()
      })

    post = Repo.get!(Post, post_id)
    post = post |> Ecto.Changeset.change(string: "Post 2") |> Repo.update!()
    Repo.delete!(post)

    Enum.each([0.02, 0.025, 0.05, 0.075, 0.1, 0.125, 0.15], fn duration ->
      Ecto.Adapters.SQL.query!(Repo, "SELECT pg_sleep(#{duration})", [])
    end)
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
