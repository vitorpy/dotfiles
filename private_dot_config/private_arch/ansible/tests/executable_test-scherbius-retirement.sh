#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
host_vars="${repo_root}/host_vars/scherbius.yml"
service_tasks="${repo_root}/roles/services/tasks/main.yml"
vitorpy_nginx="${repo_root}/roles/services/templates/nginx/vitorpy.conf.j2"
ansible_temp="$(mktemp -d /tmp/ansible-scherbius-retirement-test.XXXXXX)"
trap 'rm -rf -- "${ansible_temp}"' EXIT

scherbius_json="$(
  ANSIBLE_CONFIG="${repo_root}/ansible.cfg" \
    ANSIBLE_LOCAL_TEMP="${ansible_temp}/local" \
    ANSIBLE_REMOTE_TEMP="${ansible_temp}/remote" \
    ansible-inventory --playbook-dir "${repo_root}" --host scherbius
)"

require_literal() {
  local literal="$1"
  local file="$2"
  grep -Fq -- "${literal}" "${file}" || {
    echo "missing '${literal}' in ${file}" >&2
    exit 1
  }
}

reject_literal() {
  local literal="$1"
  local file="$2"
  if grep -Fq -- "${literal}" "${file}"; then
    echo "retired literal '${literal}' remains in ${file}" >&2
    exit 1
  fi
}

jq -e '
  (.arch_firewall_allowed_tcp_ports_extra | index(8081) == null) and
  (.arch_locked_users == ["tiago", "matas"]) and
  ([.arch_retired_systemd_units[].name] == ["lob-game-server.service", "lob-ws-bridge.service"]) and
  ([.arch_nginx_managed_confs[].name] == ["vitorpy.conf", "jellyfin.conf"]) and
  (.arch_nginx_removed_confs == ["atproto-bot-webhook.conf", "lob-web.conf"]) and
  (.arch_nginx_removed_blocks | length == 2)
' <<< "${scherbius_json}" >/dev/null

require_literal "Lock retired local accounts" "${service_tasks}"
require_literal "Terminate retired local account sessions and user services" "${service_tasks}"
require_literal "Remove retired system service unit files" "${service_tasks}"
require_literal "Remove retired nginx virtual hosts" "${service_tasks}"
require_literal "Remove retired nginx routes from retained virtual hosts" "${service_tasks}"
require_literal "retirement" "${service_tasks}"

reject_literal "8081" "${host_vars}"
reject_literal "location /noreposts/" "${vitorpy_nginx}"
reject_literal "following-no-reposts.vitorpy.com" "${vitorpy_nginx}"
reject_literal "127.0.0.1:3000" "${vitorpy_nginx}"

test ! -e "${repo_root}/roles/services/templates/nginx/atproto-bot-webhook.conf.j2"
test ! -e "${repo_root}/roles/services/templates/nginx/lob-web.conf.j2"

echo "Scherbius retirement invariants passed"
