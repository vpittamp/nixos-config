#!/usr/bin/env bash

# Script to retrieve API keys from 1Password and configure Home Assistant
# Requires 1Password CLI to be configured

echo "Setting up LLM API keys for Home Assistant..."

# Function to get key from 1Password
get_1password_field() {
    local item_name="$1"
    local field_name="$2"

    echo "Retrieving $field_name from $item_name in 1Password..."
    op item get "$item_name" --fields "$field_name" 2>/dev/null
}

# Try to get keys from 1Password
echo "Attempting to retrieve API keys from 1Password..."
echo "Note: You may need to sign in to 1Password CLI first with: op signin"

# OpenAI API Key
OPENAI_KEY=$(get_1password_field "OpenAI API" "credential" || \
             get_1password_field "OpenAI" "api_key" || \
             get_1password_field "OpenAI" "password")

# Anthropic API Key
ANTHROPIC_KEY=$(get_1password_field "Anthropic API" "credential" || \
                get_1password_field "Anthropic" "api_key" || \
                get_1password_field "Claude API" "api_key" || \
                get_1password_field "Anthropic" "password")

# Google AI Key
GOOGLE_AI_KEY=$(get_1password_field "Google AI" "api_key" || \
                get_1password_field "Gemini API" "api_key" || \
                get_1password_field "Google Generative AI" "api_key")

# Create secrets file
SECRETS_FILE="/var/lib/hass/secrets.yaml"

# Check if we got any keys
if [ -z "$OPENAI_KEY" ] && [ -z "$ANTHROPIC_KEY" ] && [ -z "$GOOGLE_AI_KEY" ]; then
    echo "No API keys found in 1Password."
    echo "Please ensure you have items named 'OpenAI API', 'Anthropic API', or 'Google AI' in 1Password"
    echo ""
    echo "Alternatively, you can manually edit $SECRETS_FILE with your API keys"
    exit 1
fi

# Update secrets file
echo "Updating Home Assistant secrets file..."

sudo tee "$SECRETS_FILE" > /dev/null <<EOF
# Home Assistant Secrets File
# Auto-generated from 1Password on $(date)

# OpenAI API Configuration
openai_api_key: "${OPENAI_KEY:-sk-YOUR_OPENAI_API_KEY_HERE}"
openai_model: "gpt-4-turbo-preview"

# Anthropic Claude API Configuration
anthropic_api_key: "${ANTHROPIC_KEY:-sk-ant-YOUR_ANTHROPIC_API_KEY_HERE}"
anthropic_model: "claude-3-opus-20240229"

# Google AI (Gemini) Configuration
google_generative_ai_key: "${GOOGLE_AI_KEY:-YOUR_GOOGLE_AI_KEY_HERE}"

# Home location (update if needed)
latitude: 40.7128
longitude: -74.0060
elevation: 10
EOF

# Set proper permissions
sudo chown hass:hass "$SECRETS_FILE"
sudo chmod 600 "$SECRETS_FILE"

echo "Secrets file updated successfully!"
echo ""
echo "Found keys:"
[ -n "$OPENAI_KEY" ] && echo "✓ OpenAI API key configured"
[ -n "$ANTHROPIC_KEY" ] && echo "✓ Anthropic API key configured"
[ -n "$GOOGLE_AI_KEY" ] && echo "✓ Google AI key configured"
echo ""
echo "Restarting Home Assistant to apply changes..."
sudo systemctl restart home-assistant

echo "Done! LLM integrations should now be available in Home Assistant."