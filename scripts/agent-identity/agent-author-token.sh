# agent-author-token: the current installation token of the GitHub App
# `pittampalli-agent-author`, for the workstation `agent` OS user only.
#
#   agent-author-token                 print the token (for GH_TOKEN)
#   agent-author-token git-credential <get|store|erase>
#                                      git credential helper; answers only for
#                                      https://github.com/<allowed repository>
#   agent-author-token status          where the token came from and when it
#                                      expires; never prints the token
#
# Source of truth: dev Secret agent-identity/agent-author-token (key `token`),
# minted every 30 min by GithubAccessToken/agent-author (1 h lifetime), read
# with the owner-issued bound ServiceAccount token of agent-identity/local-minter
# (`get` on that one Secret). See docs/AGENT_IDENTITY.md.
#
# The App token is cached only on tmpfs (@cacheDir@, mode 0700, owned by the
# agent user), never beyond its expiry, and refetched when less than
# MIN_REMAINING seconds remain. The bound ServiceAccount token never appears in
# argv (curl reads the header from a pipe).
#
# Substituted at build time: @stateDir@ @cacheDir@ @allowedRepos@ @agentUser@

set -euo pipefail
umask 077

state_dir="${AGENT_IDENTITY_STATE_DIR:-@stateDir@}"
cache_dir="${AGENT_IDENTITY_CACHE_DIR:-@cacheDir@}"
min_remaining="${AGENT_IDENTITY_MIN_REMAINING_SECONDS:-600}"
allowed_repos="@allowedRepos@"   # space separated owner/name
agent_user="@agentUser@"
namespace="agent-identity"
secret="agent-author-token"

server_file="$state_dir/dev-server"
ca_file="$state_dir/dev-ca.crt"
minter_token_file="$state_dir/dev-local-minter.token"
cache_token="$cache_dir/token"
cache_meta="$cache_dir/token.meta"

die() {
  printf 'agent-author-token: %s\n' "$*" >&2
  exit 1
}

warn() {
  printf 'agent-author-token: warning: %s\n' "$*" >&2
}

now() { date +%s; }

require_identity() {
  local me
  me="$(id -un)"
  [ "$me" = "$agent_user" ] \
    || die "runs only as the '$agent_user' user, not '$me' (the owner keeps his own gh login)"
}

require_minter_token() {
  [ -e "$minter_token_file" ] \
    || die "no bound ServiceAccount token at $minter_token_file; the owner issues it with: agent-identity-provision dev"
  local mode owner
  mode="$(stat -c '%a' "$minter_token_file")"
  owner="$(stat -c '%U' "$minter_token_file")"
  [ "$mode" = "600" ] && [ "$owner" = "$agent_user" ] \
    || die "$minter_token_file must be mode 600 owned by $agent_user, found mode $mode owned by $owner; re-run: agent-identity-provision dev"
  [ -r "$server_file" ] || die "no dev API server URL at $server_file; re-run: agent-identity-provision dev"
  [ -r "$ca_file" ] || die "no dev API CA at $ca_file; re-run: agent-identity-provision dev"
}

clear_cache() {
  rm -f "$cache_token" "$cache_meta"
}

# Print "<expires_epoch> <source>" from the cache, or nothing.
cached_meta() {
  [ -s "$cache_token" ] && [ -s "$cache_meta" ] || return 0
  cat "$cache_meta"
}

# GET the minted Secret from the dev API server. Prints the Secret JSON.
fetch_secret_json() {
  local server url body code minter
  server="$(tr -d '[:space:]' <"$server_file")"
  url="$server/api/v1/namespaces/$namespace/secrets/$secret"
  minter="$(tr -d '[:space:]' <"$minter_token_file")"
  [ -n "$minter" ] || die "$minter_token_file is empty; re-run: agent-identity-provision dev"
  body="$(mktemp "$cache_dir/secret.XXXXXX")"
  # shellcheck disable=SC2064
  trap "rm -f '$body'" RETURN
  code="$(curl --silent --show-error --max-time 20 \
      --cacert "$ca_file" \
      --header @<(printf 'Authorization: Bearer %s\n' "$minter") \
      --output "$body" --write-out '%{http_code}' \
      "$url")" || die "could not reach the dev API server $server (curl exit $?)"
  minter=""
  case "$code" in
    200) cat "$body" ;;
    401) die "dev API server refused the bound local-minter token (HTTP 401): it has expired or was revoked; the owner re-issues it with: agent-identity-provision dev" ;;
    403) die "dev API server forbade get secret/$secret in $namespace for local-minter (HTTP 403): $(jq -r '.message // empty' "$body" 2>/dev/null)" ;;
    404) die "secret $namespace/$secret does not exist on dev (HTTP 404): stacks agent-identity (I1) is not synced, or the minter has not run" ;;
    *) die "dev API server answered HTTP $code for $namespace/$secret: $(jq -r '.message // empty' "$body" 2>/dev/null)" ;;
  esac
}

# Ask GitHub what this token is and when it expires.
# Prints "<expires_epoch|-> <comma separated repositories>".
inspect_token() {
  local token="$1" headers body code exp_header exp_epoch repos
  headers="$(mktemp "$cache_dir/h.XXXXXX")"
  body="$(mktemp "$cache_dir/b.XXXXXX")"
  # shellcheck disable=SC2064
  trap "rm -f '$headers' '$body'" RETURN
  code="$(curl --silent --show-error --max-time 20 \
      --header @<(printf 'Authorization: Bearer %s\nAccept: application/vnd.github+json\nX-GitHub-Api-Version: 2022-11-28\n' "$token") \
      --dump-header "$headers" --output "$body" --write-out '%{http_code}' \
      'https://api.github.com/installation/repositories?per_page=100')" \
    || die "could not reach api.github.com (curl exit $?)"
  [ "$code" = "200" ] \
    || die "GitHub refused the minted token on /installation/repositories (HTTP $code: $(jq -r '.message // empty' "$body" 2>/dev/null)); the dev minter may be failing"
  exp_header="$(tr -d '\r' <"$headers" | awk -F': ' 'tolower($1)=="github-authentication-token-expiration"{print $2}' | tail -n1)"
  exp_epoch="-"
  if [ -n "$exp_header" ]; then
    exp_epoch="$(date -d "$exp_header" +%s 2>/dev/null || echo -)"
  fi
  repos="$(jq -r '[.repositories[].full_name] | sort | join(",")' "$body")"
  printf '%s %s\n' "$exp_epoch" "$repos"
}

refresh() {
  require_minter_token
  mkdir -p "$cache_dir"
  local json token written_epoch inspect exp_epoch repos source expected tmp_token tmp_meta remaining
  json="$(fetch_secret_json)"
  token="$(printf '%s' "$json" | jq -r '.data.token // empty' | base64 -d 2>/dev/null || true)"
  [ -n "$token" ] || die "secret $namespace/$secret on dev has no data.token"
  # When ESO last wrote the Secret (fallback expiry source: write + 3600 s).
  written_epoch="$(printf '%s' "$json" \
    | jq -r '[.metadata.managedFields[]?.time // empty] + [.metadata.creationTimestamp] | max' \
    | xargs -I{} date -d {} +%s 2>/dev/null || echo 0)"
  json=""

  inspect="$(inspect_token "$token")"
  exp_epoch="${inspect%% *}"
  repos="${inspect#* }"
  # shellcheck disable=SC2086 # word splitting of the repository list is intended
  expected="$(printf '%s\n' $allowed_repos | sort | paste -sd, -)"
  if [ "$repos" != "$expected" ]; then
    token=""
    die "the minted token reaches repositories '$repos', not exactly '$expected'; refusing it (check GithubAccessToken/agent-author and the App installation)"
  fi
  if [ "$exp_epoch" = "-" ]; then
    [ "$written_epoch" -gt 0 ] || die "cannot determine the token's expiry: GitHub sent no expiration header and the Secret has no write time"
    exp_epoch=$((written_epoch + 3600))
    source="secret-write-time+3600s"
  else
    source="github-expiration-header"
  fi

  remaining=$((exp_epoch - $(now)))
  if [ "$remaining" -le 60 ]; then
    token=""
    die "the token on dev expires in ${remaining}s ($(date -d "@$exp_epoch" -Is), from $source); the minter re-mints every 30 min, so ExternalSecret $namespace/$secret is stale"
  fi
  if [ "$remaining" -lt "$min_remaining" ]; then
    warn "the token on dev expires in ${remaining}s (under ${min_remaining}s); ExternalSecret $namespace/$secret may be behind its 30 min refresh"
  fi

  tmp_token="$(mktemp "$cache_dir/token.XXXXXX")"
  tmp_meta="$(mktemp "$cache_dir/meta.XXXXXX")"
  printf '%s' "$token" >"$tmp_token"
  printf '%s %s\n' "$exp_epoch" "$source" >"$tmp_meta"
  mv -f "$tmp_token" "$cache_token"
  mv -f "$tmp_meta" "$cache_meta"
  token=""
}

# Ensure a cached token with more than min_remaining seconds left.
ensure_token() {
  require_identity
  local meta exp_epoch
  meta="$(cached_meta)"
  if [ -n "$meta" ]; then
    exp_epoch="${meta%% *}"
    if [ $((exp_epoch - $(now))) -gt "$min_remaining" ]; then
      return 0
    fi
    clear_cache
  fi
  refresh
}

print_token() {
  ensure_token
  cat "$cache_token"
}

repo_allowed() {
  local path="${1%.git}" repo
  path="${path%/}"
  for repo in $allowed_repos; do
    [ "${path,,}" = "${repo,,}" ] && return 0
  done
  return 1
}

git_credential() {
  local action="${1:-}" line protocol="" host="" path=""
  while IFS= read -r line && [ -n "$line" ]; do
    case "$line" in
      protocol=*) protocol="${line#protocol=}" ;;
      host=*) host="${line#host=}" ;;
      path=*) path="${line#path=}" ;;
    esac
  done
  case "$action" in
    get) ;;
    erase)
      # git saw our token rejected: drop the cache so the next call refetches.
      if [ "$host" = "github.com" ]; then clear_cache; fi
      return 0 ;;
    *) return 0 ;;
  esac
  if [ "$protocol" != "https" ] || [ "$host" != "github.com" ]; then
    printf 'agent-author-token: no credential for %s://%s (only https://github.com)\n' "$protocol" "$host" >&2
    printf 'quit=1\n'
    return 0
  fi
  if [ -z "$path" ]; then
    printf 'agent-author-token: git sent no repository path; set credential.useHttpPath=true\n' >&2
    printf 'quit=1\n'
    return 0
  fi
  if ! repo_allowed "$path"; then
    printf 'agent-author-token: refusing credentials for github.com/%s: the agent identity may write only to %s\n' "$path" "$allowed_repos" >&2
    printf 'quit=1\n'
    return 0
  fi
  local token
  token="$(print_token)" || { printf 'quit=1\n'; return 0; }
  printf 'username=x-access-token\npassword=%s\n' "$token"
}

status() {
  require_identity
  ensure_token
  local exp_epoch source
  read -r exp_epoch source <"$cache_meta"
  printf 'identity:   pittampalli-agent-author (GitHub App installation token)\n'
  printf 'source:     dev secret %s/%s via %s\n' "$namespace" "$secret" "$(tr -d '[:space:]' <"$server_file")"
  printf 'expires:    %s (in %ss, from %s)\n' "$(date -d "@$exp_epoch" -Is)" "$((exp_epoch - $(now)))" "$source"
  printf 'cache:      %s (tmpfs)\n' "$cache_token"
  printf 'git writes: %s\n' "$allowed_repos"
}

case "${1:-token}" in
  token) print_token ;;
  git-credential) shift; git_credential "${1:-}" ;;
  status) status ;;
  -h|--help|help) printf 'usage: agent-author-token [token | git-credential <get|store|erase> | status]\n' ;;
  *) die "unknown command '$1' (token | git-credential <action> | status)" ;;
esac
