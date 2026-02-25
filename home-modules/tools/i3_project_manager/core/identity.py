"""
Identity and normalization utilities for i3-project-manager.
Centralizes logic for parsing, validating, and comparing project identities.
"""

import re
from typing import Optional

def normalize_session_name_key(value: Optional[str]) -> str:
    """Normalize session names so separator variants map to one logical key.
    Treats stacks/main, stacks_main, and stacks-main as the same identity.
    """
    raw = str(value or "").strip().lower()
    if not raw:
        return ""
    return re.sub(r"[^a-z0-9]+", "-", raw).strip("-")

def project_names_match(
    preferred_project: Optional[str], candidate_project: Optional[str]
) -> bool:
    """Best-effort project name matching across short/qualified forms."""
    if not preferred_project or not candidate_project:
        return False

    preferred = preferred_project.strip().lower()
    candidate = candidate_project.strip().lower()
    if not preferred or not candidate:
        return False
    if preferred == candidate:
        return True

    def normalize(name: str) -> str:
        return re.sub(r"[:/]+", "/", name)
        
    pref_norm = normalize(preferred)
    cand_norm = normalize(candidate)
    
    if pref_norm.endswith("/" + cand_norm) or cand_norm.endswith("/" + pref_norm):
        return True
        
    return normalize_session_name_key(preferred) == normalize_session_name_key(candidate)
