defmodule RockSolid.Resolution.Resolvers.DummyResolver do
  @moduledoc """
  Dummy resolver when there are no remote schemas referenced
  """
  @behaviour RockSolid.Resolution.Resolver

  def resolve(id, _opts), do: {:error, "unexpected call to DummyResolver with #{id}"}
end
