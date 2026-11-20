defmodule AcexGateway.UpdaterTest do
  use ExUnit.Case, async: false

  alias AcexGateway.System.Updater

  setup do
    Updater.ensure_cache()
    :ok
  end

  test "native_installed? returns boolean based on environment" do
    is_native = Updater.native_installed?()
    assert is_boolean(is_native)
  end

  test "detect_update_method returns one of valid atoms" do
    method = Updater.detect_update_method()
    assert method in [:native, :watchtower, :script, :manual]
  end

  test "verify_sha256_against_sums correctly parses checksum format" do
    # Create temporary file to test hashing
    tmp_path = Path.join(System.tmp_dir!(), "test-file-#{System.unique_integer([:positive])}.tar.gz")
    test_content = "acex gateway test release tarball content"
    File.write!(tmp_path, test_content)

    on_exit(fn -> File.rm(tmp_path) end)

    expected_hash =
      :crypto.hash(:sha256, test_content)
      |> Base.encode16(case: :lower)

    tarball_name = Path.basename(tmp_path)

    sums_body = """
    d41d8cd98f00b204e9800998ecf8427e other-archive.tar.gz
    #{expected_hash}  #{tarball_name}
    """

    assert :ok = Updater.verify_sha256_against_sums(tmp_path, tarball_name, sums_body)

    # Test mismatch
    bad_sums_body = """
    1111111111111111111111111111111111111111111111111111111111111111  #{tarball_name}
    """
    assert {:error, "Checksum mismatch for " <> ^tarball_name} =
             Updater.verify_sha256_against_sums(tmp_path, tarball_name, bad_sums_body)

    # Test not found
    missing_sums = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  unrelated.tar.gz"
    assert {:error, "Checksum entry not found for " <> ^tarball_name} =
             Updater.verify_sha256_against_sums(tmp_path, tarball_name, missing_sums)
  end

  test "trigger_update returns valid response structure" do
    assert {:ok, resp} = Updater.trigger_update()
    assert is_map(resp)
    assert Map.has_key?(resp, :status)
    assert Map.has_key?(resp, :method)
  end
end
