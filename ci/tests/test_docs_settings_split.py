"""Run the generated settings splitter regression suite in the CI tests job."""

import runpy
from pathlib import Path


SPLITTER_TEST = (
    Path(__file__).parents[1]
    / "jobs/scripts/docs/autogenerate/test_session_settings_split.py"
)


def test_generated_settings_split():
    test_module = runpy.run_path(str(SPLITTER_TEST))
    assert test_module["main"]() == 0
