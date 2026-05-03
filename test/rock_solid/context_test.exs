defmodule RockSolid.ContextTest do
  use ExUnit.Case

  alias RockSolid.Context

  describe "get/1" do
    test "returns nil if value does not exist" do
      assert is_nil(Context.get({true, false}))
    end

    test "returns value if exists" do
      key = {%{"items" => %{"$ref" => "#/$defs/foo"}}, %{"$ref" => "#/$defs/foo"}}
      Context.put(key, false)

      assert Context.get(key) == false
    end
  end
end
