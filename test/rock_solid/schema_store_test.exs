defmodule RockSolid.SchemaStoreTest do
  use ExUnit.Case
  use ExUnitProperties

  @schemas_path "test/support/schemastore"

  @moduletag :integration

  describe "schemastore tests" do
    for filename <- File.ls!(@schemas_path) do
      test "schema #{filename}" do
        filename = unquote(filename)

        Path.join(@schemas_path, filename)
        |> File.read!()
        |> JSON.decode!()
        |> check_schema()
      end
    end
  end

  def check_schema(schema) do
    root = JSV.build!(schema)

    check all generated <- RockSolid.from_schema(schema) do
      assert {:ok, _} = JSV.validate(generated, root)
    end
  end
end
