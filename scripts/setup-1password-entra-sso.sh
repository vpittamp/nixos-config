#!/usr/bin/env bash
# Setup 1Password SSO with Microsoft Entra ID
# This script automates the creation and configuration of the Entra ID application

set -e

echo "🔐 Setting up 1Password SSO with Microsoft Entra ID"
echo "=================================================="
echo ""

# Configuration
APP_NAME="1Password EPM"
REDIRECT_URI="https://pittampalli.1password.com/sso/oidc/redirect/"
TENANT_ID=$(az account show --query tenantId -o tsv)

echo "Tenant ID: $TENANT_ID"
echo ""

# Step 1: Create App Registration
echo "Step 1: Creating app registration..."
APP_ID=$(az ad app create \
  --display-name "$APP_NAME" \
  --sign-in-audience AzureADMyOrg \
  --query appId -o tsv)

echo "✅ App created with ID: $APP_ID"
echo ""

# Step 2: Create Service Principal (Enterprise Application)
echo "Step 2: Creating service principal..."
az ad sp create --id "$APP_ID"
echo "✅ Service principal created"
echo ""

# Step 3: Configure Redirect URI and enable ID tokens
echo "Step 3: Configuring redirect URI and ID tokens..."
az ad app update --id "$APP_ID" \
  --web-redirect-uris "$REDIRECT_URI" \
  --enable-id-token-issuance true

echo "✅ Redirect URI configured: $REDIRECT_URI"
echo ""

# Step 4: Configure API Permissions (Microsoft Graph - OpenID)
echo "Step 4: Configuring API permissions..."

# Microsoft Graph API ID
GRAPH_API_ID="00000003-0000-0000-c000-000000000000"

# Permission IDs for Microsoft Graph
# openid: 37f7f235-527c-4136-accd-4a02d197296e
# profile: 14dad69e-099b-42c9-810b-d002981feec1
# email: 64a6cdd6-aab1-4aaf-94b8-3cc8405e90d0

az ad app permission add --id "$APP_ID" \
  --api "$GRAPH_API_ID" \
  --api-permissions \
    37f7f235-527c-4136-accd-4a02d197296e=Scope \
    14dad69e-099b-42c9-810b-d002981feec1=Scope \
    64a6cdd6-aab1-4aaf-94b8-3cc8405e90d0=Scope

echo "✅ API permissions configured (openid, profile, email)"
echo ""

# Grant admin consent
echo "Step 5: Granting admin consent..."
az ad app permission admin-consent --id "$APP_ID"
echo "✅ Admin consent granted"
echo ""

# Step 6: Add optional UPN claim
echo "Step 6: Configuring optional claims (UPN)..."
cat > /tmp/optional-claims.json <<EOF
{
  "idToken": [
    {
      "name": "upn",
      "source": null,
      "essential": false,
      "additionalProperties": []
    }
  ]
}
EOF

az ad app update --id "$APP_ID" \
  --optional-claims "@/tmp/optional-claims.json"

rm /tmp/optional-claims.json
echo "✅ Optional UPN claim configured"
echo ""

# Step 7: Create Client Secret
echo "Step 7: Creating client secret..."
SECRET_EXPIRY_DATE=$(date -u -d "+24 months" '+%Y-%m-%dT%H:%M:%SZ')
SECRET_RESULT=$(az ad app credential reset --id "$APP_ID" \
  --append \
  --display-name "1Password SSO" \
  --end-date "$SECRET_EXPIRY_DATE" \
  --query password -o tsv)

echo "✅ Client secret created (expires in 24 months)"
echo ""

# Get OpenID configuration URL
OPENID_CONFIG_URL="https://login.microsoftonline.com/$TENANT_ID/v2.0/.well-known/openid-configuration"

# Summary
echo "=================================================="
echo "✅ Setup Complete!"
echo "=================================================="
echo ""
echo "📋 Configuration Details:"
echo "------------------------"
echo ""
echo "Application ID:"
echo "  $APP_ID"
echo ""
echo "OpenID Configuration URL:"
echo "  $OPENID_CONFIG_URL"
echo ""
echo "Client Secret:"
echo "  $SECRET_RESULT"
echo ""
echo "Redirect URI (already configured):"
echo "  $REDIRECT_URI"
echo ""
echo "⚠️  IMPORTANT: Save the client secret securely!"
echo "   It will not be shown again."
echo ""
echo "=================================================="
echo ""
echo "📝 Next Steps:"
echo "------------------------"
echo "1. Go to 1Password.com → Policies → Configure Identity Provider"
echo "2. Select 'Microsoft Entra ID'"
echo "3. Enter the following values:"
echo "   - Application ID: $APP_ID"
echo "   - OpenID configuration document URL: $OPENID_CONFIG_URL"
echo "   - Client Type: Private Client"
echo "   - Application Secret: $SECRET_RESULT"
echo "4. Test the connection"
echo "5. Configure which users/groups can use SSO"
echo ""

# Store credentials in 1Password
echo "💾 Storing credentials in 1Password..."
op item create \
  --category="API Credential" \
  --title="Microsoft Entra ID - 1Password SSO" \
  --vault="Employee" \
  --url="https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/Overview/appId/$APP_ID" \
  application_id="$APP_ID" \
  client_secret="$SECRET_RESULT" \
  tenant_id="$TENANT_ID" \
  openid_config_url="$OPENID_CONFIG_URL" \
  redirect_uri="$REDIRECT_URI" \
  secret_expiry_date="$SECRET_EXPIRY_DATE" \
  "notesPlain=Microsoft Entra ID application for 1Password SSO. Client secret expires on $SECRET_EXPIRY_DATE. Set a reminder to rotate it before expiration." \
  > /dev/null

echo "✅ Credentials saved to 1Password Employee vault"
echo ""
echo "Secret reference for automation:"
echo "  op://Employee/Microsoft Entra ID - 1Password SSO/client_secret"
echo ""
