# Test PWA Fixtures for Unit Testing
{ lib }:

{
  # Minimal valid PWA (minimum required fields)
  minimal = {
    name = "MinimalPWA";
    url = "https://example.com";
    domain = "example.com";
    icon = "file:///tmp/test-icon.png";
    description = "Minimal test PWA";
    ulid = "01HQTEST000000000000000001";
  };

  # Complete PWA (all fields populated)
  complete = {
    name = "CompletePWA";
    url = "https://complete.example.com";
    domain = "complete.example.com";
    icon = "file:///tmp/complete-icon.png";
    description = "Complete test PWA with all fields";
    categories = "Network;WebBrowser;";
    keywords = "test;complete;pwa;";
    scope = "https://complete.example.com/";
    ulid = "01HQTEST000000000000000002";
  };

  # Invalid ULID - wrong length
  invalidUlidLength = {
    name = "InvalidLengthPWA";
    url = "https://invalid.example.com";
    domain = "invalid.example.com";
    icon = "file:///tmp/invalid-icon.png";
    description = "PWA with invalid ULID length";
    ulid = "TOOLONG000000000000000000001";  # 28 chars instead of 26
  };

  # Invalid ULID - forbidden characters (I, L, O, U)
  invalidUlidChars = {
    name = "InvalidCharsPWA";
    url = "https://badchars.example.com";
    domain = "badchars.example.com";
    icon = "file:///tmp/badchars-icon.png";
    description = "PWA with forbidden ULID characters";
    ulid = "01HQTEST000000000INVALID0";  # Contains I, L - forbidden in ULID
  };

  # Edge case - localhost URL
  localhost = {
    name = "LocalhostPWA";
    url = "http://localhost:3000";
    domain = "localhost";
    icon = "file:///tmp/localhost-icon.png";
    description = "Localhost development PWA";
    ulid = "01HQTEST000000000000000003";
  };

  # Edge case - long name and description
  longFields = {
    name = "This Is A Very Long PWA Name That Tests The Maximum Length Constraint For Display Names In The System";
    url = "https://longfields.example.com";
    domain = "longfields.example.com";
    icon = "file:///tmp/longfields-icon.png";
    description = "This is an extremely long description that tests the maximum length constraint for PWA descriptions in the system. It should be validated properly to ensure it doesn't exceed the defined limits and cause issues.";
    ulid = "01HQTEST000000000000000004";
  };

  # Edge case - minimal scope (root)
  rootScope = {
    name = "RootScopePWA";
    url = "https://rootscope.example.com";
    domain = "rootscope.example.com";
    icon = "file:///tmp/rootscope-icon.png";
    description = "PWA with root scope";
    scope = "https://rootscope.example.com/";
    ulid = "01HQTEST000000000000000005";
  };

  # Edge case - nested scope
  nestedScope = {
    name = "NestedScopePWA";
    url = "https://nested.example.com/app/dashboard";
    domain = "nested.example.com";
    icon = "file:///tmp/nested-icon.png";
    description = "PWA with nested scope path";
    scope = "https://nested.example.com/app/";
    ulid = "01HQTEST000000000000000006";
  };

  # Edge case - HTTPS icon URL (not file://)
  remoteIcon = {
    name = "RemoteIconPWA";
    url = "https://remoteicon.example.com";
    domain = "remoteicon.example.com";
    icon = "https://remoteicon.example.com/icon.png";
    description = "PWA with remote HTTPS icon";
    ulid = "01HQTEST000000000000000007";
  };

  # Edge case - special characters in name
  specialChars = {
    name = "Special & Chars: PWA (test)";
    url = "https://special.example.com";
    domain = "special.example.com";
    icon = "file:///tmp/special-icon.png";
    description = "PWA with special characters & symbols";
    ulid = "01HQTEST000000000000000008";
  };

  # Real-world example - YouTube-like PWA
  youtubeExample = {
    name = "YouTube";
    url = "https://www.youtube.com";
    domain = "youtube.com";
    icon = "file:///etc/nixos/assets/pwa-icons/youtube.png";
    description = "YouTube Video Platform";
    categories = "AudioVideo;Video;";
    keywords = "video;streaming;youtube;";
    scope = "https://www.youtube.com/";
    ulid = "01HQ1Z9J8G7X2K5MNBVWXYZ013";
  };

  # Real-world example - Google AI-like PWA
  googleAIExample = {
    name = "Google AI";
    url = "https://gemini.google.com/app";
    domain = "gemini.google.com";
    icon = "file:///etc/nixos/assets/pwa-icons/google-ai.png";
    description = "Google Gemini AI Assistant";
    categories = "Network;Development;";
    keywords = "ai;gemini;google;assistant;";
    scope = "https://gemini.google.com/";
    ulid = "01HQ1Z9J8G7X2K5MNBVWXYZ014";
  };
}
