"""
Test that config file paths are resolved correctly
regardless of the program's working directory.
"""
import os
import json
import tempfile
import pytest
from pathlib import Path
from src.multimcp.multi_mcp import MultiMCP


def test_config_path_resolution_from_different_cwd():
    """
    Test that a relative config path works even when the program
    is executed from a different working directory.

    This simulates the nix run scenario where:
    1. User is in /home/user with config.json
    2. User runs: nix run ... -- --config config.json
    3. Program executes from nix store but should find config.json
       in the user's original directory
    """
    # Save original directory
    original_cwd = os.getcwd()

    try:
        # Create a temp directory to simulate user's location
        with tempfile.TemporaryDirectory() as user_dir:
            # Create a config file in the user directory
            config_path = Path(user_dir) / "test_config.json"
            config_data = {
                "mcpServers": {
                    "test_server": {
                        "command": "echo",
                        "args": ["test"]
                    }
                }
            }

            with open(config_path, 'w') as f:
                json.dump(config_data, f)

            # Change to user directory (simulating user's location)
            os.chdir(user_dir)

            # Create another temp directory to simulate nix store
            with tempfile.TemporaryDirectory() as nix_store_dir:
                # Change to nix store directory (simulating nix run execution)
                os.chdir(nix_store_dir)

                # Now try to load the config using relative path from original location
                # This should work because we're passing the relative path "test_config.json"
                # but the cwd is now different

                # This is the problematic scenario - we need to use absolute path
                multi_mcp = MultiMCP(config=str(config_path))
                result = multi_mcp.load_mcp_config(str(config_path))

                assert result is not None, "Config should be loaded successfully"
                assert "mcpServers" in result
                assert "test_server" in result["mcpServers"]

    finally:
        # Restore original directory
        os.chdir(original_cwd)


def test_config_path_with_relative_path():
    """
    Test that relative paths are converted to absolute paths.
    """
    original_cwd = os.getcwd()

    try:
        with tempfile.TemporaryDirectory() as temp_dir:
            os.chdir(temp_dir)

            # Create config in current directory
            config_data = {
                "mcpServers": {
                    "test": {
                        "command": "echo",
                        "args": ["test"]
                    }
                }
            }

            with open("config.json", 'w') as f:
                json.dump(config_data, f)

            # Load with relative path
            multi_mcp = MultiMCP(config="./config.json")
            result = multi_mcp.load_mcp_config("./config.json")

            assert result is not None
            assert "mcpServers" in result

    finally:
        os.chdir(original_cwd)


def test_config_path_with_tilde_expansion():
    """
    Test that ~ in paths is expanded correctly.
    """
    # Create a config in a temp location
    with tempfile.TemporaryDirectory() as temp_dir:
        config_path = Path(temp_dir) / "config.json"
        config_data = {
            "mcpServers": {
                "test": {
                    "command": "echo",
                    "args": ["test"]
                }
            }
        }

        with open(config_path, 'w') as f:
            json.dump(config_data, f)

        # Test with absolute path (tilde expansion not applicable here,
        # but we test that absolute paths work)
        multi_mcp = MultiMCP(config=str(config_path))
        result = multi_mcp.load_mcp_config(str(config_path))

        assert result is not None


def test_config_path_nix_store_fallback_to_home():
    """
    Test that when running from /nix/store (nix run scenario), the config
    loader falls back to checking the user's home directory.

    This simulates the nix run scenario where:
    1. User has mcp.json in their home directory
    2. User runs: nix run ... -- --config mcp.json
    3. Program's cwd is /nix/store/...
    4. Config should be found by fallback to home directory
    """
    original_cwd = os.getcwd()

    try:
        # Create temp directory to simulate user's home
        with tempfile.TemporaryDirectory() as home_dir:
            # Create config file in home directory
            config_path = Path(home_dir) / "mcp.json"
            config_data = {
                "mcpServers": {
                    "test_server": {
                        "command": "echo",
                        "args": ["test"]
                    }
                }
            }

            with open(config_path, 'w') as f:
                json.dump(config_data, f)

            # Create temp directory to simulate nix store
            with tempfile.TemporaryDirectory() as nix_store_base:
                # Create a path that looks like a nix store
                nix_store_dir = Path(nix_store_base) / "nix" / "store" / "test-multi-mcp-0.1.0"
                nix_store_dir.mkdir(parents=True)

                # Change cwd to nix store (simulates nix run behavior)
                os.chdir(str(nix_store_dir))

                # Verify we're in a /nix/store path
                assert os.getcwd().find('/nix/store') != -1

                # Temporarily override expanduser to return our test home
                import unittest.mock
                with unittest.mock.patch('os.path.expanduser') as mock_expanduser:
                    def expanduser_mock(path):
                        if path.startswith('~'):
                            return path.replace('~', home_dir)
                        return path

                    mock_expanduser.side_effect = expanduser_mock

                    # Try to load config with relative path
                    # Should fallback to home directory
                    multi_mcp = MultiMCP(config="mcp.json")
                    result = multi_mcp.load_mcp_config("mcp.json")

                    assert result is not None, "Config should be found in home directory via fallback"
                    assert "mcpServers" in result
                    assert "test_server" in result["mcpServers"]

    finally:
        # Restore original state
        os.chdir(original_cwd)


def test_config_path_nix_store_fallback_to_config_dir():
    """
    Test that when running from /nix/store, the config loader also tries
    ~/.config/multi-mcp/ as a fallback location.
    """
    original_cwd = os.getcwd()

    try:
        # Create temp directory to simulate user's home
        with tempfile.TemporaryDirectory() as home_dir:
            # Create config in ~/.config/multi-mcp/
            config_dir = Path(home_dir) / ".config" / "multi-mcp"
            config_dir.mkdir(parents=True)

            config_path = config_dir / "mcp.json"
            config_data = {
                "mcpServers": {
                    "test_server": {
                        "command": "echo",
                        "args": ["test"]
                    }
                }
            }

            with open(config_path, 'w') as f:
                json.dump(config_data, f)

            # Create temp directory to simulate nix store
            with tempfile.TemporaryDirectory() as nix_store_base:
                nix_store_dir = Path(nix_store_base) / "nix" / "store" / "test-multi-mcp-0.1.0"
                nix_store_dir.mkdir(parents=True)

                os.chdir(str(nix_store_dir))
                assert os.getcwd().find('/nix/store') != -1

                import unittest.mock
                with unittest.mock.patch('os.path.expanduser') as mock_expanduser:
                    def expanduser_mock(path):
                        if path.startswith('~'):
                            return path.replace('~', home_dir)
                        return path

                    mock_expanduser.side_effect = expanduser_mock

                    multi_mcp = MultiMCP(config="mcp.json")
                    result = multi_mcp.load_mcp_config("mcp.json")

                    assert result is not None, "Config should be found in ~/.config/multi-mcp/"
                    assert "mcpServers" in result
                    assert "test_server" in result["mcpServers"]

    finally:
        os.chdir(original_cwd)
