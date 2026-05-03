defmodule RockSolid.Resolver do
  @moduledoc """
  Resolver that fetches schemas from ETS table or local cache
  """
  @behaviour JSV.Resolver

  alias RockSolid.Context

  # Consider whether it's possible that a used schema lives in local cache but not in ets
  # I think not? Since they're always fetched
  @impl true
  def resolve(uri, _opts) do
    {:ok, Context.fetch_schema!(uri)}
  rescue
    _ -> {:error, "#{uri} not in local cache"}
  end
end
