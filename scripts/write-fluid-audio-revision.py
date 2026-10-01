"""Include the FluidAudio revision actually checked out by Xcode."""
import json
import os
from pathlib import Path

workspace = json.loads(Path(os.environ["SCRIPT_INPUT_FILE_0"]).read_text())
dependency = next(
    item for item in workspace["object"]["dependencies"]
    if item["packageRef"]["identity"] == "fluidaudio"
)
output = Path(os.environ["SCRIPT_OUTPUT_FILE_0"])
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(dependency["state"]["checkoutState"]["revision"] + "\n")
