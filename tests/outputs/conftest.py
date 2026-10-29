"""pytest configuration for tests/outputs (helpers live in outputs_helpers.py)."""
import pytest

from outputs_helpers import REPO


def pytest_configure(config):
    config.addinivalue_line("markers", "slow: starts the Shiny app and drives it with Playwright (skipped with -m 'not slow' / --fast)")


@pytest.fixture(scope="session")
def repo():
    return REPO
