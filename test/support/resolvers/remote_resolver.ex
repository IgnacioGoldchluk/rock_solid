defmodule RockSolid.Resolvers.RemoteResolver do
  @moduledoc false
  require Logger

  # Files that for some reason often timeout when fetched remotely
  @pre_fetched %{
    "https://json.schemastore.org/partial-cibuildwheel.json" => "partial-cibuildwheel.json",
    "https://json.schemastore.org/foundryvtt-base-package-manifest.json" =>
      "foundryvtt-base-package-manifest.json",
    "https://json.schemastore.org/jscpd.json" => "jscpd.json",
    "https://json.schemastore.org/azure-iot-edge-deployment-1.0.json" =>
      "azure-iot-edge-deployment-1.0.json",
    "https://json.schemastore.org/compilerdefaults.json" => "compilerdefaults.json",
    "https://json.schemastore.org/ava.json" => "ava.json",
    "https://json.schemastore.org/semantic-release.json" => "semantic-release.json",
    "https://json.schemastore.org/kubernetes-definitions.json" => "kubernetes-definitions.json"
  }

  @doc """
  Fetches a schema from the given URL
  """
  def resolve(base_id, _) when is_map_key(@pre_fetched, base_id) do
    {:ok,
     File.read!(Path.join(["test", "support", "cached", @pre_fetched[base_id]])) |> JSON.decode!()}
  end

  def resolve(schema_url, _) when is_binary(schema_url) do
    Logger.info("Fetching #{schema_url}")

    case do_fetch_schema(schema_url) do
      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
        JSON.decode(body)

      {:error, _} = e ->
        e

      {:ok, response} ->
        Logger.error("Unexpected response to #{schema_url}: #{inspect(response)}")
        {:error, :unexpected_response}
    end
  end

  defp do_fetch_schema(schema_url) do
    [url: schema_url]
    |> Keyword.merge(Application.get_env(:rock_solid, :client_options, []))
    |> Req.request()
  end
end
