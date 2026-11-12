#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
host_vars="${repo_root}/host_vars/scherbius.yml"
service_tasks="${repo_root}/roles/services/tasks/main.yml"
vitorpy_nginx="${repo_root}/roles/services/templates/nginx/vitorpy.conf.j2"
retired_fixture="${repo_root}/tests/fixtures/retired-profiles.yml"
ansible_temp="$(mktemp -d /tmp/ansible-scherbius-retirement-test.XXXXXX)"
trap 'rm -rf -- "${ansible_temp}"' EXIT

scherbius_json="$(
  ANSIBLE_CONFIG="${repo_root}/ansible.cfg" \
    ANSIBLE_LOCAL_TEMP="${ansible_temp}/local" \
    ANSIBLE_REMOTE_TEMP="${ansible_temp}/remote" \
    ansible-inventory --playbook-dir "${repo_root}" -i "${retired_fixture}" --host scherbius
)"
active_inventory_json="$(
  ANSIBLE_CONFIG="${repo_root}/ansible.cfg" \
    ANSIBLE_LOCAL_TEMP="${ansible_temp}/local" \
    ANSIBLE_REMOTE_TEMP="${ansible_temp}/remote" \
    ansible-inventory --playbook-dir "${repo_root}" --list
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
  .arch_host_firewall_allowed_tcp_ports_extra == [] and
  .arch_host_firewall_allowed_udp_ports_extra == [41641] and
  .arch_tailscale_app_connector_enabled == false and
  .arch_tailscale_app_connector_retired == true and
  .arch_bitmagnet_enabled == false and
  (.arch_locked_users == ["tiago", "matas"]) and
  ([.arch_retired_systemd_units[].name] == ["lob-game-server.service", "lob-ws-bridge.service"]) and
  .arch_nginx_managed_confs == [] and
  (.arch_nginx_removed_confs == ["atproto-bot-webhook.conf", "lob-web.conf", "gramps.conf", "jellyfin.conf", "vitorpy.conf"]) and
  .arch_nginx_removed_blocks == []
' <<< "${scherbius_json}" >/dev/null
jq -e '
  (._meta.hostvars | keys | sort) == ["mediaserver", "zygalski"]
' <<< "${active_inventory_json}" >/dev/null

require_literal "Lock retired local accounts" "${service_tasks}"
require_literal "Terminate retired local account sessions and user services" "${service_tasks}"
require_literal "Remove retired system service unit files" "${service_tasks}"
require_literal "Remove retired nginx virtual hosts" "${service_tasks}"
require_literal "Remove retired nginx routes from retained virtual hosts" "${service_tasks}"
require_literal "retirement" "${service_tasks}"
require_literal "Stop advertising the ForwardMX app connector" "${repo_root}/retire-scherbius.yml"

reject_literal "8081" "${host_vars}"
reject_literal "location /noreposts/" "${vitorpy_nginx}"
reject_literal "following-no-reposts.vitorpy.com" "${vitorpy_nginx}"
reject_literal "127.0.0.1:3000" "${vitorpy_nginx}"

test ! -e "${repo_root}/roles/services/templates/nginx/atproto-bot-webhook.conf.j2"
test ! -e "${repo_root}/roles/services/templates/nginx/lob-web.conf.j2"

echo "Scherbius retirement invariants passed"
