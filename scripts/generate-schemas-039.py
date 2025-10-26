#!/usr/bin/env python3
"""Generate JSON schemas for Feature 039 Pydantic models."""

import sys
import json
from pathlib import Path

# Add daemon module to path
sys.path.insert(0, str(Path(__file__).parent.parent / "home-modules" / "desktop" / "i3-project-event-daemon"))

from models import WindowIdentity, I3PMEnvironment, DiagnosticReport

def generate_schemas():
    """Generate JSON schemas for core models."""
    output_dir = Path(__file__).parent.parent / "specs" / "039-create-a-new" / "contracts"
    output_dir.mkdir(parents=True, exist_ok=True)

    # Generate WindowIdentity schema
    window_identity_schema = WindowIdentity.model_json_schema(mode='serialization')
    with open(output_dir / "window-identity-schema.json", "w") as f:
        json.dump(window_identity_schema, f, indent=2)
    print(f"✓ Generated window-identity-schema.json")

    # Generate I3PMEnvironment schema
    i3pm_env_schema = I3PMEnvironment.model_json_schema(mode='serialization')
    with open(output_dir / "i3pm-environment-schema.json", "w") as f:
        json.dump(i3pm_env_schema, f, indent=2)
    print(f"✓ Generated i3pm-environment-schema.json")

    # Generate DiagnosticReport schema
    diagnostic_schema = DiagnosticReport.model_json_schema(mode='serialization')
    with open(output_dir / "diagnostic-report-schema.json", "w") as f:
        json.dump(diagnostic_schema, f, indent=2)
    print(f"✓ Generated diagnostic-report-schema.json")

    print(f"\nAll schemas generated in {output_dir}")

if __name__ == "__main__":
    generate_schemas()
