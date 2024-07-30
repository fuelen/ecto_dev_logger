defmodule Ecto.DevLoggerTest do
  use ExUnit.Case

  defmodule Repo do
    use Ecto.Repo, adapter: Ecto.Adapters.Postgres, otp_app: :my_test_app

    def get_config() do
      [
        telemetry_prefix: [:my_test_app, :repo],
        otp_app: :my_test_app,
        timeout: 15_000,
        migration_timestamps: [type: :naive_datetime_usec],
        database: "ecto_dev_logger_test",
        hostname: "localhost",
        username: "postgres",
        password: "postgres",
        port: 5432,
        log: false,
        stacktrace: true,
        pool_size: 10
      ]
    end
  end

  defmodule Repo2 do
    use Ecto.Repo, adapter: Ecto.Adapters.Postgres, otp_app: :my_test_app

    def get_config() do
      [
        telemetry_prefix: [:my_test_app, :repo2],
        otp_app: :my_test_app,
        timeout: 15_000,
        migration_timestamps: [type: :naive_datetime_usec],
        database: "ecto_dev_logger_test2",
        hostname: "localhost",
        username: "postgres",
        password: "postgres",
        port: 5432,
        log: false,
        stacktrace: true,
        pool_size: 10
      ]
    end
  end

  defmodule Money do
    defstruct [:currency, :value]
  end

  defmodule Money.Ecto.Type do
    use Ecto.ParameterizedType

    def type(_params), do: :money_type

    def init(_opts), do: %{}

    def cast(_data, _params), do: {:ok, nil}

    def load(nil, _loader, _params), do: {:ok, nil}

    def load({currency, value}, _loader, _params),
      do: {:ok, %Money{currency: currency, value: value}}

    def dump(nil, _dumper, _params), do: {:ok, nil}
    def dump(data, _dumper, _params), do: {:ok, {data.currency, data.value}}

    def equal?(a, b, _params) do
      a == b
    end
  end

  defmodule MACADDRType do
    use Ecto.Type

    def type, do: :inet
    def cast(term), do: {:ok, term}
    def dump(term), do: {:ok, term}
    def load(term), do: {:ok, term}
  end

  defmodule InetType do
    use Ecto.Type

    def type, do: :inet
    def cast(term), do: {:ok, term}
    def dump(term), do: {:ok, term}
    def load(term), do: {:ok, term}
  end

  defmodule Post do
    use Ecto.Schema

    @primary_key {:id, :binary_id, read_after_writes: true}
    schema "posts" do
      field(:string, :string)
      field(:binary, :binary)
      field(:map, :map)
      field(:integer, :integer)
      field(:decimal, :decimal)
      field(:date, :date)
      field(:time, :time)
      field(:array_of_strings, {:array, :string})
      field(:money, Money.Ecto.Type)
      field(:multi_money, {:array, Money.Ecto.Type})
      field(:datetime, :utc_datetime_usec)
      field(:naive_datetime, :naive_datetime_usec)
      field(:password_digest, :string)
      field(:ip, InetType)
      field(:macaddr, MACADDRType)
      field(:enum, {:array, Ecto.Enum}, values: [foo: 1, bar: 2, baz: 5])
    end
  end

  setup do
    setup_repo(Repo)
    Ecto.DevLogger.install(Repo)

    on_exit(fn ->
      teardown_repo(Repo)
    end)
  end

  test "everything" do
    %{id: post_id} =
      Repo.insert!(%Post{
        string: "Post '1'",
        binary:
          <<246, 229, 61, 115, 2, 108, 128, 33, 102, 144, 102, 55, 125, 237, 142, 40, 217, 225,
            234, 79, 134, 83, 85, 94, 218, 15, 55, 38, 39>>,
        map: %{test: true, string: "\"'"},
        integer: 0,
        decimal: Decimal.from_float(0.12),
        date: Date.utc_today(),
        time: Time.truncate(Time.utc_now(), :second),
        array_of_strings: ["single_word", "hello, comma", "hey 'quotes'", "hey \"quotes\""],
        money: %Money{currency: "USD", value: 390},
        multi_money: [%Money{currency: "USD", value: 230}, %Money{currency: "USD", value: 180}],
        datetime: DateTime.utc_now(),
        naive_datetime: NaiveDateTime.utc_now(),
        password_digest: "$pbkdf2-sha512$160000$iFMKqXv32lHNL7GsUtajyA$Sa4ebMd",
        ip: %Postgrex.INET{address: {127, 0, 0, 1}, netmask: 24},
        macaddr: %Postgrex.MACADDR{address: {8, 1, 43, 5, 7, 9}},
        enum: [:foo, :baz]
      })

    post = Repo.get!(Post, post_id)
    post = post |> Ecto.Changeset.change(string: nil) |> Repo.update!()
    Repo.delete!(post)

    Enum.each([0.02, 0.025, 0.05, 0.075, 0.1, 0.125, 0.15], fn duration ->
      Ecto.Adapters.SQL.query!(Repo, "SELECT pg_sleep(#{duration})", [])
    end)
  end

  describe "inline_params/4" do
    @params [
      nil,
      <<95, 131, 49, 101, 176, 212, 77, 86, 178, 31, 80, 13, 41, 189, 148, 174>>,
      [["test"]]
    ]
    @return_to_color :yellow
    test "Postgres" do
      assert Ecto.DevLogger.inline_params(
               "UPDATE \"posts\" SET \"string\" = $1 WHERE \"id\" = $2 AND \"array_of_array_of_string\" = $3 RETURNING \"id\"",
               @params,
               @return_to_color,
               Ecto.Adapters.Postgres
             ) ==
               "UPDATE \"posts\" SET \"string\" = \e[38;5;31mNULL\e[33m WHERE \"id\" = \e[38;5;31m'5f833165-b0d4-4d56-b21f-500d29bd94ae'\e[33m AND \"array_of_array_of_string\" = \e[38;5;31m'{{test}}'\e[33m RETURNING \"id\""
    end

    test "Tds" do
      assert Ecto.DevLogger.inline_params(
               "UPDATE \"posts\" SET \"string\" = @1 WHERE \"id\" = @2 AND \"array_of_array_of_string\" = @3 RETURNING \"id\"",
               @params,
               @return_to_color,
               Ecto.Adapters.Tds
             ) ==
               "UPDATE \"posts\" SET \"string\" = \e[38;5;31mNULL\e[33m WHERE \"id\" = \e[38;5;31m'5f833165-b0d4-4d56-b21f-500d29bd94ae'\e[33m AND \"array_of_array_of_string\" = \e[38;5;31m'{{test}}'\e[33m RETURNING \"id\""
    end

    test "MySQL" do
      assert to_string(
               Ecto.DevLogger.inline_params(
                 "UPDATE \"posts\" SET \"string\" = ? WHERE \"id\" = ? AND \"array_of_array_of_string\" = ? RETURNING \"id\"",
                 @params,
                 @return_to_color,
                 Ecto.Adapters.MyXQL
               )
             ) ==
               "UPDATE \"posts\" SET \"string\" = \e[38;5;31mNULL\e[33m WHERE \"id\" = \e[38;5;31m'5f833165-b0d4-4d56-b21f-500d29bd94ae'\e[33m AND \"array_of_array_of_string\" = \e[38;5;31m'{{test}}'\e[33m RETURNING \"id\""
    end
  end

  test "install returns error from failure to attach " do
    assert {:error, :already_exists} = Ecto.DevLogger.install(Repo)
  end

  test "handler_id\1" do
    assert [:ecto_dev_logger, :my_test_app, :repo] = Ecto.DevLogger.handler_id(Repo)
  end

  describe "multiple repos" do
    setup do
      setup_repo(Repo2)

      on_exit(fn ->
        teardown_repo(Repo2)
      end)
    end

    test "install of second repo works" do
      assert :ok = Ecto.DevLogger.install(Repo2)
      repo1_prefix = Repo.config()[:telemetry_prefix]
      [repo1_handler] = :telemetry.list_handlers(repo1_prefix)
      repo2_prefix = Repo2.config()[:telemetry_prefix]
      [repo2_handler] = :telemetry.list_handlers(repo2_prefix)
      # Confirm that there is a distinct handler ID for each repo
      assert repo1_handler.id != repo2_handler.id
    end

    test "logging for two repos, with repo name" do
      ## Use options to enable logging of repo name on second repo
      assert :ok = Ecto.DevLogger.install(Repo2, log_repo_name: true)

      # Log some basic queries
      repo1_log =
        ExUnit.CaptureLog.capture_log(fn ->
          %{id: post_id} =
            Repo.insert!(%Post{
              datetime: ~U[2022-06-25T14:30:16.639767Z],
              naive_datetime: ~N[2022-06-25T14:30:16.643949]
            })

          Repo.get!(Post, post_id)
          :ok
        end)

      [
        repo1_insert_start,
        repo1_insert_status,
        repo1_insert_query,
        repo1_insert_location,
        repo1_select_start,
        repo1_select_status,
        repo1_select_query,
        repo1_select_location,
        _close
      ] = String.split(repo1_log, "\n")

      ## Confirm that the original repo's logging is not changed by the addition of a second repo
      assert repo1_insert_start == "\e[32m"

      assert repo1_insert_status =~
               ~r/\[debug\] QUERY OK source=\e\[34m\"posts\"\e\[32m db=\d+\.\d+ms/

      assert repo1_insert_query ==
               "INSERT INTO \"posts\" (\"datetime\",\"naive_datetime\") VALUES (\e[38;5;31m'2022-06-25 14:30:16.639767Z'\e[32m,\e[38;5;31m'2022-06-25 14:30:16.643949'\e[32m) RETURNING \"id\"\e[90m"

      assert repo1_insert_location =~
               ~r/↳\ anonymous\ fn\/0\ in\ Ecto\.DevLoggerTest\."test\ multiple\ repos\ logging\ for\ two\ repos,\ with\ repo\ name"\/1,\ at:\ test\/ecto\/dev_logger_test\.exs:[0-9]+/

      assert repo1_select_start == "\e[0m\e[36m"

      assert repo1_select_status =~
               ~r/\[debug\] QUERY OK source=\e\[34m\"posts\"\e\[36m db=\d+\.\d+ms/

      select_query_regex =
        (Regex.escape(
           "SELECT p0.\"id\", p0.\"string\", p0.\"binary\", p0.\"map\", p0.\"integer\", p0.\"decimal\", p0.\"date\", p0.\"time\", p0.\"array_of_strings\", p0.\"money\", p0.\"multi_money\", p0.\"datetime\", p0.\"naive_datetime\", p0.\"password_digest\", p0.\"ip\", p0.\"macaddr\", p0.\"enum\" FROM \"posts\" AS p0 WHERE (p0.\"id\" = \e[38;5;31m'"
         ) <>
           "[-0-9a-fA-F]+" <>
           Regex.escape("'\e[36m)\e[90m"))
        |> Regex.compile!()

      assert repo1_select_query =~ select_query_regex

      assert repo1_select_location =~
               ~r/↳\ anonymous\ fn\/0\ in\ Ecto\.DevLoggerTest\."test\ multiple\ repos\ logging\ for\ two\ repos,\ with\ repo\ name"\/1,\ at:\ test\/ecto\/dev_logger_test\.exs:[0-9]+/

      repo2_log =
        ExUnit.CaptureLog.capture_log(fn ->
          %{id: post_id} =
            Repo2.insert!(%Post{
              datetime: ~U[2022-06-25T14:30:16.639767Z],
              naive_datetime: ~N[2022-06-25T14:30:16.643949]
            })

          Repo2.get!(Post, post_id)
          :ok
        end)

      [
        repo2_insert_start,
        repo2_insert_status,
        repo2_insert_query,
        repo2_insert_location,
        repo2_select_start,
        repo2_select_status,
        repo2_select_query,
        repo2_select_location,
        _close
      ] = String.split(repo2_log, "\n")

      ## Confirm that the logging remains the same apart from the addition of the repo name in the status line.
      assert repo2_insert_start == repo1_insert_start

      assert repo2_insert_status =~
               ~r/\[debug\] QUERY OK source=\e\[34m\"posts\"\e\[32m repo=\e\[34mEcto.DevLoggerTest.Repo2\e\[32m db=\d+\.\d+ms/

      assert repo2_insert_query == repo1_insert_query

      assert repo2_insert_location =~
               ~r/↳\ anonymous\ fn\/0\ in\ Ecto\.DevLoggerTest\."test\ multiple\ repos\ logging\ for\ two\ repos,\ with\ repo\ name"\/1,\ at:\ test\/ecto\/dev_logger_test\.exs:[0-9]+/

      assert repo2_select_start == repo1_select_start

      assert repo2_select_status =~
               ~r/\[debug\] QUERY OK source=\e\[34m\"posts\"\e\[36m repo=\e\[34mEcto.DevLoggerTest.Repo2\e\[\d+m db=\d+\.\d+ms/

      assert repo2_select_query =~ select_query_regex

      assert repo2_select_location =~
               ~r/↳\ anonymous\ fn\/0\ in\ Ecto\.DevLoggerTest\."test\ multiple\ repos\ logging\ for\ two\ repos,\ with\ repo\ name"\/1,\ at:\ test\/ecto\/dev_logger_test\.exs:[0-9]+/
    end
  end

  defp setup_repo(repo_module, log_sql_statements \\ false) do
    config = repo_module.get_config()

    Application.put_env(:my_test_app, repo_module, config)
    repo_module.__adapter__().storage_down(config)
    repo_module.__adapter__().storage_up(config)
    repo_pid = start_supervised!(repo_module)

    repo_module.query!("CREATE EXTENSION IF NOT EXISTS \"pgcrypto\";", [],
      log: log_sql_statements
    )

    repo_module.query!(
      """
      CREATE TYPE money_type AS (currency char(3), value integer);
      """,
      [],
      log: log_sql_statements
    )

    repo_module.query!(
      """
      CREATE TABLE posts (
        id uuid PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
        string text,
        "binary" bytea,
        map jsonb,
        integer integer,
        decimal numeric,
        date date,
        time time(0) without time zone,
        array_of_strings text[],
        money money_type,
        multi_money money_type[],
        password_digest text,
        datetime timestamp without time zone NOT NULL,
        naive_datetime timestamp without time zone NOT NULL,
        ip INET,
        macaddr MACADDR,
        enum integer[]
      )
      """,
      [],
      log: log_sql_statements
    )

    ## Swallow the reload warning after changing DB structure.
    assert ExUnit.CaptureLog.capture_log(fn ->
             repo_module.query!("SELECT * FROM posts")
           end) =~
             "forcing us to reload type information from the database. This is expected behaviour whenever you migrate your database."

    repo_pid
  end

  defp teardown_repo(repo_module) do
    Ecto.DevLogger.uninstall(repo_module)

    config = repo_module.get_config()
    repo_module.__adapter__().storage_down(config)
  end
end
