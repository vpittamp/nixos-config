#!/usr/bin/env bash
set -e

echo "Setting up 1Password service account token..."

# Check if already logged in to personal account
if ! op account list | grep -q "vinod@pittampalli.com"; then
  echo "Please sign in to your personal 1Password account first:"
  eval $(op signin)
fi

# Fetch the service account token using secret reference
echo "Fetching service account token from 1Password..."
TOKEN=$(op read 'op://Employee/ja6iykklyslhq7tccnkgaj4joe/credential')

if [ -z "$TOKEN" ]; then
  echo "Error: Could not fetch token from 1Password"
  exit 1
fi

# Store securely
echo "$TOKEN" > /var/lib/onepassword/service-account-token
chmod 600 /var/lib/onepassword/service-account-token
chown vpittamp:users /var/lib/onepassword/service-account-token

echo "Service account token stored successfully!"
echo ""
echo "You can now use: source /etc/onepassword/load-token.sh"
echo "Or simply: git-push, git-pull, git-fetch (aliases configured)"
