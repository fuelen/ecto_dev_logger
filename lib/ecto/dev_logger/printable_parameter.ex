defprotocol Ecto.DevLogger.PrintableParameter do
  @moduledoc """
  A protocol for rendering values as valid, copy‑pastable SQL expressions.

  `Ecto.DevLogger` calls this protocol for every bound parameter when it inlines values
  into the logged SQL.

  When should I implement this?
  - When a value you pass as a query parameter is a struct or type that does not
    have a built‑in implementation.
  - This is common with PostgreSQL custom/extension types that live outside `postgrex`
    (e.g. third‑party extensions), or with domain‑specific structs used via custom `Ecto.Type`s
    (for example: `Money`, `LTree`, or proprietary composite types).

  Without an implementation, the logger falls back to `inspect/1`, which may not be
  valid SQL and therefore not directly runnable.

  How to implement
  - If your value can be represented as a single string literal that your database accepts,
    implement `to_string_literal/1` and have `to_expression/1` wrap it in single quotes.
  - If it must be rendered as a structured SQL expression (e.g. `ROW(...)`, casts, or
    constructor functions), implement `to_expression/1` directly and return `nil` from
    `to_string_literal/1`.

  Example: PostgreSQL composite type represented by a struct

      defmodule MyApp.Money do
        defstruct [:currency, :amount]
      end

      defimpl Ecto.DevLogger.PrintableParameter, for: MyApp.Money do
        def to_expression(%MyApp.Money{} = money) do
          string = to_string_literal(money)
          "'\#{String.replace(string, "'", "''")}'"
        end

        def to_string_literal(%MyApp.Money{currency: cur, amount: amt}) do
          "(\#{cur},\#{amt})"
        end
      end

  Arrays and tuples
  - When all elements implement `to_string_literal/1`, lists and tuples are formatted as
    PostgreSQL array and composite string literals (`'{...}'` and `'(...)'`). Otherwise,
    they are rendered using `ARRAY[...]` and `ROW(...)`, with each element formatted via
    `to_expression/1`.

  `to_expression/1` is the main function and `to_string_literal/1` is an optional helper for it.
  """

  @doc """
  Converts term to a valid SQL expression.
  """
  @spec to_expression(any()) :: String.t()
  def to_expression(term)

  @doc """
  Converts term to a string literal.
  """
  @spec to_string_literal(any()) :: String.t() | nil
  def to_string_literal(term)
end

defmodule Ecto.DevLogger.Utils do
  @moduledoc false
  def in_string_quotes(string) do
    "'#{String.replace(string, "'", "''")}'"
  end

  def all_to_string_literal(list) do
    result =
      Enum.reduce_while(list, {:ok, []}, fn element, {:ok, acc} ->
        case Ecto.DevLogger.PrintableParameter.to_string_literal(element) do
          nil -> {:halt, :error}
          string_literal -> {:cont, {:ok, [{element, string_literal} | acc]}}
        end
      end)

    with {:ok, list} <- result do
      {:ok, Enum.reverse(list)}
    end
  end
end

defimpl Ecto.DevLogger.PrintableParameter, for: Atom do
  def to_expression(nil), do: "NULL"
  def to_expression(true), do: "true"
  def to_expression(false), do: "false"
  def to_expression(atom), do: atom |> Atom.to_string() |> Ecto.DevLogger.Utils.in_string_quotes()

  def to_string_literal(nil), do: "NULL"
  def to_string_literal(true), do: "true"
  def to_string_literal(false), do: "false"
  def to_string_literal(atom), do: Atom.to_string(atom)
end

defimpl Ecto.DevLogger.PrintableParameter, for: Map do
  def to_expression(map) do
    map |> to_string_literal() |> Ecto.DevLogger.Utils.in_string_quotes()
  end

  def to_string_literal(map), do: Jason.encode!(map)
end

for geo_mod <- [
      Geo.Point,
      Geo.PointZ,
      Geo.PointM,
      Geo.PointZM,
      Geo.LineString,
      Geo.LineStringZ,
      Geo.LineStringZM,
      Geo.Polygon,
      Geo.PolygonZ,
      Geo.MultiPoint,
      Geo.MultiPointZ,
      Geo.MultiLineString,
      Geo.MultiLineStringZ,
      Geo.MultiPolygon,
      Geo.MultiPolygonZ,
      Geo.GeometryCollection
    ] do
  if Code.ensure_loaded?(geo_mod) do
    defimpl Ecto.DevLogger.PrintableParameter, for: geo_mod do
      def to_expression(geometry) do
        geometry |> to_string_literal() |> Ecto.DevLogger.Utils.in_string_quotes()
      end

      def to_string_literal(geometry), do: to_string(geometry)
    end
  end
end

defimpl Ecto.DevLogger.PrintableParameter, for: Tuple do
  def to_expression(tuple) do
    case to_string_literal(tuple) do
      nil ->
        "ROW(" <>
          Enum.map_join(
            Tuple.to_list(tuple),
            ",",
            &Ecto.DevLogger.PrintableParameter.to_expression/1
          ) <> ")"

      value ->
        Ecto.DevLogger.Utils.in_string_quotes(value)
    end
  end

  def to_string_literal(tuple) do
    case Ecto.DevLogger.Utils.all_to_string_literal(Tuple.to_list(tuple)) do
      :error ->
        nil

      {:ok, list} ->
        body =
          Enum.map_join(list, ",", fn {element, string_literal} ->
            case element do
              nil ->
                ""

              "" ->
                ~s|""|

              _ ->
                string = String.replace(string_literal, "\"", "\\\"")

                if String.contains?(string, [",", "(", ")"]) do
                  ~s|"#{string}"|
                else
                  string
                end
            end
          end)

        "(" <> body <> ")"
    end
  end
end

defimpl Ecto.DevLogger.PrintableParameter, for: Decimal do
  def to_expression(decimal), do: to_string_literal(decimal)
  def to_string_literal(decimal), do: Decimal.to_string(decimal)
end

defimpl Ecto.DevLogger.PrintableParameter, for: Integer do
  def to_expression(integer), do: to_string_literal(integer)
  def to_string_literal(integer), do: Integer.to_string(integer)
end

defimpl Ecto.DevLogger.PrintableParameter, for: Float do
  def to_expression(float), do: to_string_literal(float)
  def to_string_literal(float), do: Float.to_string(float)
end

defimpl Ecto.DevLogger.PrintableParameter, for: Date do
  def to_expression(date) do
    date
    |> to_string_literal()
    |> Ecto.DevLogger.Utils.in_string_quotes()
  end

  def to_string_literal(date), do: Date.to_string(date)
end

defimpl Ecto.DevLogger.PrintableParameter, for: DateTime do
  def to_expression(date_time) do
    date_time
    |> to_string_literal()
    |> Ecto.DevLogger.Utils.in_string_quotes()
  end

  def to_string_literal(date_time), do: DateTime.to_string(date_time)
end

defimpl Ecto.DevLogger.PrintableParameter, for: NaiveDateTime do
  def to_expression(naive_date_time) do
    naive_date_time
    |> to_string_literal()
    |> Ecto.DevLogger.Utils.in_string_quotes()
  end

  def to_string_literal(naive_date_time), do: NaiveDateTime.to_string(naive_date_time)
end

defimpl Ecto.DevLogger.PrintableParameter, for: Time do
  def to_expression(time) do
    time
    |> to_string_literal()
    |> Ecto.DevLogger.Utils.in_string_quotes()
  end

  def to_string_literal(time), do: Time.to_string(time)
end

defimpl Ecto.DevLogger.PrintableParameter, for: BitString do
  def to_expression(binary) do
    if String.valid?(binary) do
      Ecto.DevLogger.Utils.in_string_quotes(binary)
    else
      "DECODE('#{Base.encode64(binary)}','BASE64')"
    end
  end

  def to_string_literal(binary) do
    if String.valid?(binary) do
      binary
    end
  end
end

defimpl Ecto.DevLogger.PrintableParameter, for: List do
  def to_expression(list) do
    case to_string_literal(list) do
      nil ->
        "ARRAY[" <>
          Enum.map_join(list, ",", &Ecto.DevLogger.PrintableParameter.to_expression/1) <> "]"

      value ->
        Ecto.DevLogger.Utils.in_string_quotes(value)
    end
  end

  def to_string_literal(list) do
    case Ecto.DevLogger.Utils.all_to_string_literal(list) do
      :error ->
        nil

      {:ok, elements_with_string_literals} ->
        if tsvector?(list) do
          Enum.map_join(elements_with_string_literals, " ", fn {_element, string_literal} ->
            string_literal
          end)
        else
          body =
            Enum.map_join(elements_with_string_literals, ",", fn {element, string_literal} ->
              cond do
                is_list(element) or is_nil(element) ->
                  string_literal

                element == "" ->
                  ~s|""|

                true ->
                  string = String.replace(string_literal, "\"", "\\\"")

                  if String.downcase(string) == "null" or
                       String.contains?(string, [",", "{", "}"]) do
                    ~s|"#{string}"|
                  else
                    string
                  end
              end
            end)

          "{" <> body <> "}"
        end
    end
  end

  # tsvector is a list of lexemes.
  # By checking only the first element we assume that the others are also lexemes.
  defp tsvector?([%{__struct__: Postgrex.Lexeme} | _]) do
    true
  end

  defp tsvector?(_list) do
    false
  end
end

if Code.ensure_loaded?(Postgrex.MACADDR) do
  defimpl Ecto.DevLogger.PrintableParameter, for: Postgrex.MACADDR do
    def to_expression(macaddr) do
      macaddr
      |> to_string_literal()
      |> Ecto.DevLogger.Utils.in_string_quotes()
    end

    def to_string_literal(macaddr) do
      macaddr.address
      |> Tuple.to_list()
      |> Enum.map_join(":", fn value ->
        value
        |> Integer.to_string(16)
        |> String.pad_leading(2, "0")
      end)
    end
  end
end

if Code.ensure_loaded?(Postgrex.Range) do
  defimpl Ecto.DevLogger.PrintableParameter, for: Postgrex.Range do
    def to_expression(range) do
      range
      |> to_string_literal()
      |> Ecto.DevLogger.Utils.in_string_quotes()
    end

    def to_string_literal(%Postgrex.Range{lower: :empty}), do: "empty"
    def to_string_literal(%Postgrex.Range{upper: :empty}), do: "empty"

    def to_string_literal(%Postgrex.Range{} = range) do
      left_bracket = if range.lower_inclusive, do: "[", else: "("
      right_bracket = if range.upper_inclusive, do: "]", else: ")"

      lower =
        case range.lower do
          :unbound -> ""
          value -> Ecto.DevLogger.PrintableParameter.to_string_literal(value)
        end

      upper =
        case range.upper do
          :unbound -> ""
          value -> Ecto.DevLogger.PrintableParameter.to_string_literal(value)
        end

      left_bracket <> lower <> "," <> upper <> right_bracket
    end
  end
end

if Code.ensure_loaded?(Postgrex.Multirange) do
  defimpl Ecto.DevLogger.PrintableParameter, for: Postgrex.Multirange do
    def to_expression(%Postgrex.Multirange{} = multirange) do
      multirange
      |> to_string_literal()
      |> Ecto.DevLogger.Utils.in_string_quotes()
    end

    def to_string_literal(%Postgrex.Multirange{ranges: ranges}) do
      ranges = ranges || []

      body =
        Enum.map_join(ranges, ",", fn %Postgrex.Range{} = range ->
          Ecto.DevLogger.PrintableParameter.to_string_literal(range)
        end)

      "{" <> body <> "}"
    end
  end
end

if Code.ensure_loaded?(Postgrex.Interval) do
  defimpl Ecto.DevLogger.PrintableParameter, for: Postgrex.Interval do
    def to_expression(struct),
      do: Postgrex.Interval.to_string(struct) |> Ecto.DevLogger.Utils.in_string_quotes()

    def to_string_literal(struct),
      do: Postgrex.Interval.to_string(struct)
  end
end

if Code.ensure_loaded?(Postgrex.INET) do
  defimpl Ecto.DevLogger.PrintableParameter, for: Postgrex.INET do
    def to_expression(inet) do
      inet
      |> to_string_literal()
      |> Ecto.DevLogger.Utils.in_string_quotes()
    end

    def to_string_literal(inet) do
      netmask =
        case inet.netmask do
          nil -> ""
          netmask -> "/#{netmask}"
        end

      "#{:inet.ntoa(inet.address)}#{netmask}"
    end
  end
end

if Code.ensure_loaded?(Postgrex.Lexeme) do
  defimpl Ecto.DevLogger.PrintableParameter, for: Postgrex.Lexeme do
    def to_expression(lexeme) do
      raise "Invalid parameter: #{lexeme} must be inside a list"
    end

    def to_string_literal(lexeme) do
      word =
        if String.contains?(lexeme.word, [",", "'", " ", ":"]) do
          Ecto.DevLogger.Utils.in_string_quotes(lexeme.word)
        else
          lexeme.word
        end

      case lexeme.positions do
        [] ->
          word

        positions ->
          positions =
            Enum.map_join(positions, ",", fn {position, weight} ->
              if weight in [nil, :D] do
                Integer.to_string(position)
              else
                [Integer.to_string(position), Atom.to_string(weight)]
              end
            end)

          "#{word}:#{positions}"
      end
    end
  end
end

defimpl Ecto.DevLogger.PrintableParameter, for: Ecto.DevLogger.NumericEnum do
  def to_expression(enum), do: "#{enum.integer}/*#{enum.atom}*/"
  def to_string_literal(_numeric_enum), do: nil
end
