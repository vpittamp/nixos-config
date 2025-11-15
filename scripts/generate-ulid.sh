#!/usr/bin/env bash
# Generate a valid ULID (Universally Unique Lexicographically Sortable Identifier)
# Per spec: https://github.com/ulid/spec
#
# ULID Format:
# - 26 characters total
# - Crockford Base32 alphabet: 0123456789ABCDEFGHJKMNPQRSTVWXYZ (excludes I, L, O, U)
# - First character must be 0-7 (to fit within 48-bit timestamp max)
# - Structure: ttttttttttrrrrrrrrrrrrrrrr (10 timestamp + 16 random)
# - Maximum valid ULID: 7ZZZZZZZZZZZZZZZZZZZZZZZZZ

set -euo pipefail

# Generate valid ULID using Python (most portable)
python3 -c '
import random

# Crockford Base32 alphabet (excludes I, L, O, U)
alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

# First character must be 0-7 for valid ULID (48-bit timestamp constraint)
# Per spec: max ULID is 7ZZZZZZZZZZZZZZZZZZZZZZZZZ
valid_first = "01234567"

# Generate ULID
first = random.choice(valid_first)
rest = "".join(random.choice(alphabet) for _ in range(25))
ulid = first + rest

print(ulid)
'
