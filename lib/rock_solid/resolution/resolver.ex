defmodule RockSolid.Resolution.Resolver do
  @moduledoc """
  Behaviour to resolve references
  """

  @callback resolve(String.t(), any()) :: {:ok, map()} | {:error, any()}
end
