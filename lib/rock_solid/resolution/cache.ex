defmodule RockSolid.Resolution.Cache do
  @moduledoc false
  alias RockSolid.Context
  alias RockSolid.Resolution

  require Logger

  @doc """
  Returns a schema from cache directory, or nil if it is not present
  """
  def get_schema(base_id) do
    path = expected_cache_filename(base_id)

    if File.exists?(path) do
      path |> File.read!() |> JSON.decode!()
    end
  end

  defp cache_dir, do: :filename.basedir(:user_cache, "rock_solid")

  defp expected_cache_filename(base_id) when is_binary(base_id) do
    Path.join(cache_dir(), "#{Base.encode32(base_id)}.json")
  end

  def put_schema(schema) do
    id = Resolution.id(schema)
    Context.put_schema(schema)
    store_in_local_dir(id, schema)
  end

  def store_in_local_dir(base_id, schema) do
    if not File.exists?(cache_dir()) do
      # Fails in CI, doesn't matter
      File.mkdir(cache_dir())
    end

    full_path = expected_cache_filename(base_id)

    case File.write(full_path, JSON.encode!(schema)) do
      :ok ->
        :ok

      {:error, r} ->
        Logger.error("saving file #{full_path}: #{inspect(r)}")
    end
  end

  def clear do
    if File.exists?(cache_dir()) do
      cache_dir()
      |> File.ls!()
      |> Enum.each(fn filename -> File.rm!(Path.join(cache_dir(), filename)) end)
    end
  end
end
