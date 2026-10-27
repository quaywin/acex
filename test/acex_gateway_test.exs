defmodule AcexGatewayTest do
  use ExUnit.Case, async: true

  test "version returns valid semantic version" do
    assert {:ok, _} = Version.parse(AcexGateway.version())
  end
end
