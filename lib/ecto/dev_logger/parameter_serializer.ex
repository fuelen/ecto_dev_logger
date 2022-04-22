defmodule Ecto.DevLogger.ParameterSerializer do
  @moduledoc """
  Allows one to serialize a custom ecto type to a string.

  ## Postgrex.Range Example

      defmodule CustomSerializer do
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

   ## Configuration

  in `config.exs`

      config :ecto_dev_logger, :serializer, CustomSerializer

  """

  defmodule Error do
    @moduledoc false
    defexception [:parameter]

    def message(%{parameter: parameter}) do
      "Unable to serialize parameter: #{inspect(parameter)}"
    end
  end

  @callback stringify_ecto_params(param :: any()) :: String.t() | nil

  def stringify_ecto_params(param, config) do
    serializer = Keyword.get(config, :serializer, __MODULE__.Default)
    serializer.stringify_ecto_params(param)
  end

  defmacro __using__(_opts) do
    quote do
      @behaviour unquote(__MODULE__)
      @before_compile unquote(__MODULE__)
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      @impl true
      def stringify_ecto_params(parameter) do
        raise Error, parameter: parameter
      end
    end
  end
end
