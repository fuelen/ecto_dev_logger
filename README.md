# Ecto.DevLogger

[![Hex.pm](https://img.shields.io/hexpm/v/ecto_dev_logger.svg)](https://hex.pm/packages/ecto_dev_logger)
[![Hex.pm Downloads](https://img.shields.io/hexpm/dt/ecto_dev_logger)](https://hex.pm/packages/ecto_dev_logger)

An alternative logger for Ecto queries.

It inlines bindings into the query, so it is easy to copy-paste logged SQL and run it in any IDE for debugging without
manual transformation of common Elixir terms to string representations (binary UUID, DateTime, Decimal, JSON, etc.).
It also highlights DB time to make slow queries noticeable. The source table and inlined bindings are highlighted as well.

![before and after](./assets/screenshot.png)


## Installation

The package can be installed by adding `ecto_dev_logger` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ecto_dev_logger, "~> 0.15"}
  ]
end
```

Then disable the default logger for your repo in the config file for development:
```elixir
if config_env() == :dev do
  config :my_app, MyApp.Repo, log: false
end
```
Then install the telemetry handler in `MyApp.Application`:
```elixir
Ecto.DevLogger.install(MyApp.Repo)
```
The telemetry handler will be installed only if the repo `:log` configuration is set to `false`.

That's it.

The docs can be found at [https://hexdocs.pm/ecto_dev_logger](https://hexdocs.pm/ecto_dev_logger).

### Development Only Installation

If you turn off repo logging for any reason in production, you can configure `ecto_dev_logger` to *only* be available
in development. In your `mix.exs`, restrict the installation to `:dev`:

```elixir
def deps do
  [
    {:ecto_dev_logger, "~> 0.10", only: :dev}
  ]
end
```

In `MyApp.Application`, an additional function is required:

```elixir
defmodule MyApp.Application do
  @moduledoc "..."

  def start(_type, _args) do
    maybe_install_ecto_dev_logger()

    # ...
  end

  if Code.ensure_loaded?(Ecto.DevLogger) do
    defp maybe_install_ecto_dev_logger, do: Ecto.DevLogger.install(MyApp.Repo)
  else
    defp maybe_install_ecto_dev_logger, do: :ok
  end

  # ...
end
```

### Ignore logging for a single `Repo` call

If you want to suppress logging for a specific query or Repo operation, pass `log: false` via `telemetry_options`:

```elixir
# Examples
Repo.query!("CREATE EXTENSION IF NOT EXISTS postgis", [], telemetry_options: [log: false])
Repo.insert!(changeset, telemetry_options: [log: false])
Repo.get!(User, user_id, telemetry_options: [log: false])
```

This prevents `Ecto.DevLogger` from emitting a log for that telemetry event while still executing the operation normally.

### How it works and limitations

Ecto.DevLogger inlines query parameters by converting Elixir values into SQL expressions. It does this by calling the `Ecto.DevLogger.PrintableParameter` protocol for each bound value, producing a copy‑pastable literal or expression.

Because it only sees Elixir values (not the database column types), it must guess the target database type. The mapping from Elixir types to database types is not one‑to‑one, so the output may not always match your schema exactly:

- **Maps**: assumed to be JSON. If you store maps in other column types (for example, `hstore` when using `postgrex`), the rendered SQL will still be JSON.
- **Lists**: assumed to be array‑like columns; you might instead be storing lists as JSON.
- **Scalars**: integers, floats, booleans, and strings are logged as plain values.

If you use custom database or driver‑level types, implement `Ecto.DevLogger.PrintableParameter` for the structs that appear in parameters to control how values are rendered and keep the logged SQL runnable.
Note that `Ecto.DevLogger` operates below `Ecto.Type` casting; multiple different `Ecto.Type`s can map to the same driver type. The logger sees the post‑cast value (for example, a `Postgrex.*` struct), not your `Ecto.Type`.

Keep in mind that the logged SQL is meant for debugging; it aims to be helpful, but you may still need to add manual casts to match your schema precisely.

### Rendering examples

Below are examples of how common Elixir values are rendered in logged SQL:

| Elixir value | Rendered SQL | Notes |
| --- | --- | --- |
| `nil` | `NULL` | |
| `true` / `false` | `true` / `false` | |
| `"hello"` | `'hello'` | Strings are single-quoted |
| `<<1, 2, 3>>` | `DECODE('AQID','BASE64')` | Non‑UTF‑8 binaries use a base64 decode function |
| `123` | `123` | Integers are unquoted |
| `12.34` | `12.34` | Floats are unquoted |
| `Decimal.new("12.34")` | `12.34` | Decimals are unquoted |
| `~D[2023-01-02]` | `'2023-01-02'` | Dates are quoted strings |
| `~U[2023-01-02 03:04:05Z]` | `'2023-01-02 03:04:05Z'` | DateTimes are quoted strings |
| `~N[2023-01-02 03:04:05]` | `'2023-01-02 03:04:05'` | NaiveDateTimes are quoted strings |
| `~T[03:04:05]` | `'03:04:05'` | Times are quoted strings |
| `%{"a" => 1}` | `'{"a":1}'` | Maps are rendered as JSON strings |
| `["Elixir", "Ecto"]` | `'{Elixir,Ecto}'` | Array string literal when all elements are string‑renderable |
| `["Elixir", <<153>>]` | `ARRAY['Elixir', DECODE('mQ==','BASE64')]` | Falls back to `ARRAY[...]` if mixed |
| `{"Elixir", "Ecto"}` | `'(Elixir,Ecto)'` | Composite string literal when all elements are string‑renderable |
| `{"Elixir", <<153>>}` | `ROW('Elixir', DECODE('mQ==','BASE64'))` | Falls back to `ROW(...)` if mixed |
| `%Postgrex.INET{address: {127,0,0,1}, netmask: 24}` | `'127.0.0.1/24'` | IP/netmask rendered as text |
| `%Postgrex.MACADDR{address: {8,1,43,5,7,9}}` | `'08:01:2B:05:07:09'` | MAC address rendered as text |
| `%Postgrex.Interval{months: 1, days: 2, secs: 34}` | `'1 mon 2 days 34:00:00'` | Interval rendered via `Postgrex.Interval.to_string/1` |
| `%Postgrex.Range{lower: 1, upper: 10, lower_inclusive: true, upper_inclusive: false}` | `'[1,10)'` | Range bounds and brackets |
| `%Postgrex.Range{lower: :empty}` | `'empty'` | Empty range |
| `%Postgrex.Multirange{ranges: [...]}` | `'{[1,3),(10,15]}'` | Multirange of ranges |
| `[%Postgrex.Lexeme{}, ...]` | `'word1:pos weight ...'` | Lists of lexemes are rendered as tsvector strings |

Notes:
- “String‑renderable” means `PrintableParameter.to_string_literal/1` returns a string for the element. Otherwise, `to_expression/1` is used.
- Unknown structs (without a `PrintableParameter` implementation) fall back to `inspect/1` and may not form valid SQL.

### Geo rendering examples (optional)

Below are examples when the `geo` library is available:

| Geo value | Rendered SQL |
| --- | --- |
| `%Geo.Point{coordinates: {1.0, 2.0}, srid: 4326}` | `'SRID=4326;POINT(1.0 2.0)'` |
| `%Geo.PointZ{coordinates: {1.0, 2.0, 3.0}}` | `'POINT Z(1.0 2.0 3.0)'` |
| `%Geo.PointM{coordinates: {1.0, 2.0, 4.0}}` | `'POINT M(1.0 2.0 4.0)'` |
| `%Geo.PointZM{coordinates: {1.0, 2.0, 3.0, 4.0}}` | `'POINT ZM(1.0 2.0 3.0 4.0)'` |
| `%Geo.LineString{coordinates: [{0.0, 0.0}, {1.0, 1.0}]}` | `'LINESTRING(0.0 0.0,1.0 1.0)'` |
| `%Geo.LineStringZ{coordinates: [{0.0, 0.0, 0.0}, {1.0, 1.0, 1.0}]}` | `'LINESTRINGZ(0.0 0.0 0.0,1.0 1.0 1.0)'` |
| `%Geo.LineStringZM{coordinates: [{0.0, 0.0, 0.0, 5.0}, {1.0, 1.0, 1.0, 6.0}]}` | `'LINESTRINGZM(0.0 0.0 0.0 5.0,1.0 1.0 1.0 6.0)'` |
| `%Geo.Polygon{coordinates: [[{0.0, 0.0}, {0.0, 1.0}, {1.0, 1.0}, {0.0, 0.0}]]}` | `'POLYGON((0.0 0.0,0.0 1.0,1.0 1.0,0.0 0.0))'` |
| `%Geo.PolygonZ{coordinates: [[{0.0, 0.0, 0.0}, {0.0, 1.0, 0.0}, {1.0, 1.0, 0.0}, {0.0, 0.0, 0.0}]]}` | `'POLYGON((0.0 0.0 0.0,0.0 1.0 0.0,1.0 1.0 0.0,0.0 0.0 0.0))'` |
| `%Geo.MultiPoint{coordinates: [{0.0, 0.0}, {1.0, 1.0}]}` | `'MULTIPOINT(0.0 0.0,1.0 1.0)'` |
| `%Geo.MultiPointZ{coordinates: [{0.0, 0.0, 0.0}, {1.0, 1.0, 1.0}]}` | `'MULTIPOINTZ(0.0 0.0 0.0,1.0 1.0 1.0)'` |
| `%Geo.MultiLineString{coordinates: [[{0.0, 0.0}, {1.0, 1.0}]]}` | `'MULTILINESTRING((0.0 0.0,1.0 1.0))'` |
| `%Geo.MultiLineStringZ{coordinates: [[{0.0, 0.0, 0.0}, {1.0, 1.0, 1.0}]]}` | `'MULTILINESTRINGZ((0.0 0.0 0.0,1.0 1.0 1.0))'` |
| `%Geo.MultiPolygon{coordinates: [[[{0.0, 0.0}, {0.0, 1.0}, {1.0, 1.0}, {0.0, 0.0}]]}]` | `'MULTIPOLYGON(((0.0 0.0,0.0 1.0,1.0 1.0,0.0 0.0)))'` |
| `%Geo.MultiPolygonZ{coordinates: [[[{0.0, 0.0, 0.0}, {0.0, 1.0, 0.0}, {1.0, 1.0, 0.0}, {0.0, 0.0, 0.0}]]}]` | `'MULTIPOLYGONZ(((0.0 0.0 0.0,0.0 1.0 0.0,1.0 1.0 0.0,0.0 0.0 0.0)))'` |
| `%Geo.GeometryCollection{geometries: [%Geo.Point{coordinates: {1.0, 2.0}}, %Geo.LineString{coordinates: [{0.0, 0.0}, {1.0, 1.0}]}]}` | `'GEOMETRYCOLLECTION(POINT(1.0 2.0),LINESTRING(0.0 0.0,1.0 1.0))'` |

### Format queries

It is possible to format queries using the `:before_inline_callback` option.
Here is an example setup using [pgFormatter](https://github.com/darold/pgFormatter) as an external utility:
```elixir
defmodule MyApp.Application do
  def start(_type, _args) do
    Ecto.DevLogger.install(MyApp.Repo, before_inline_callback: &__MODULE__.format_sql_query/1)
  end

  def format_sql_query(query) do
    case System.shell("echo $SQL_QUERY | pg_format -", env: [{"SQL_QUERY", query}], stderr_to_stdout: true) do
      {formatted_query, 0} -> String.trim_trailing(formatted_query)
      _ -> query
    end
  end
end
```

### Running tests

You need to run a local PostgreSQL server for the tests to interact with. This is one way to do it:

```console
$ docker run -p5432:5432 --rm --name ecto_dev_logger_postgres -e POSTGRES_PASSWORD=postgres -d postgres
```

If you want PostGIS enabled (for geometry types and extensions), run a PostGIS image instead:

```console
$ docker run -p5432:5432 --rm --name ecto_dev_logger_postgis -e POSTGRES_PASSWORD=postgres -d postgis/postgis
```
