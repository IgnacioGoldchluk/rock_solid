defmodule RockSolid.Schemas.BooleanTest do
  use ExUnit.Case, async: true

  alias RockSolid.Schemas

  describe "new/1" do
    test "creates boolean schema" do
      schema = %{"type" => "boolean", "enum" => [true, false]}

      assert {:ok, schema} == Schemas.Boolean.new(schema)
    end
  end
end
