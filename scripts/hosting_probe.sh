#!/usr/bin/env bash
# Probe a hosted Cirql deploy for the three SOH-162 deciders.
#   scripts/hosting_probe.sh write  https://<host>   # HTTPS + client bundle + seed a probe person
#   (restart / redeploy the host)
#   scripts/hosting_probe.sh verify https://<host>   # does the probe person survive?
set -u
MODE=${1:?write|verify}; B=${2:?base url, e.g. https://x.jachammer.ai}; B=${B%/}
STATE=.jac/hosting_probe.env; mkdir -p .jac
json() { python3 -c "import sys,json;d=json.load(sys.stdin);print(eval(sys.argv[1]))" "$1"; }
login() {
  curl -s -X POST "$B/user/login" -H "Content-Type: application/json" \
    -d "{\"identity\":{\"type\":\"email\",\"value\":\"$EMAIL\"},\"credential\":{\"type\":\"password\",\"password\":\"probe-secret-123\"}}" \
    | json 'd["data"]["token"]'
}
spawn() { curl -s -X POST "$B/walker/$1" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d "$2"; }

if [ "$MODE" = write ]; then
  echo "== 3. HTTPS"
  case "$B" in https://*) ;; *) echo "   FAIL: base url is not https://";; esac
  if curl -sS -o /dev/null -w "   https status %{http_code}, TLS verify %{ssl_verify_result} (0 = valid cert)\n" "$B/"; then :; else echo "   FAIL: no valid HTTPS"; fi
  echo "== 2. Serves the cl bundle, same origin as the API"
  PAGE=$(curl -s "$B/")
  echo "$PAGE" | grep -q '__jac_init__' && echo "   PASS: / serves the Jac client shell" || echo "   FAIL: / is not the Jac client (first 200 chars: ${PAGE:0:200})"
  EMAIL="probe.$(date +%s)@example.com"
  curl -s -X POST "$B/user/register" -H "Content-Type: application/json" \
    -d "{\"identities\":[{\"type\":\"email\",\"value\":\"$EMAIL\"}],\"credential\":{\"type\":\"password\",\"password\":\"probe-secret-123\"}}" >/dev/null
  TOKEN=$(login) || true
  echo "   Ping: $(spawn Ping '{}' | head -c 120)"
  echo "== 1. Persistence (seed)"
  echo "   DevAddPerson: $(spawn DevAddPerson '{"name":"Hosting Probe"}' | head -c 160)"
  echo "EMAIL=$EMAIL" > "$STATE"; echo "B=$B" >> "$STATE"
  echo "   Seeded. Now restart AND redeploy on the host, then: $0 verify $B"
else
  # shellcheck disable=SC1090
  source "$STATE"
  TOKEN=$(login) || { echo "FAIL: login lost -> user store did not persist"; exit 1; }
  OUT=$(spawn ListPeople '{}')
  echo "$OUT" | grep -q "Hosting Probe" && echo "PASS: user + graph survived ($EMAIL)" || echo "FAIL: graph lost. ListPeople: ${OUT:0:200}"
fi
