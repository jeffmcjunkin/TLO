#!/usr/bin/env bash
#
# install-roles.sh — install every Ansible role & collection TLO needs into the Ludus server.
#
# Run from the repo root on a machine with the `ludus` client configured (API key set, and
# --url pointing at your server). Example:
#     export LUDUS_API_KEY=<your-api-key>
#     LUDUS='ludus --url https://ludus.example.com:8080' ./scripts/install-roles.sh
#
set -uo pipefail
LUDUS="${LUDUS:-ludus}"

echo "==> Collections"
# ansible-core 2.19 requires data-tagging support in win_template. Older Windows
# collections silently copy raw Jinja into SQL configuration and PowerShell files.
$LUDUS ansible collection add ansible.windows --version 3.3.0 -f || exit 1
$LUDUS ansible collection add badsectorlabs.ludus_windows_utils || true   # LAPS / AD ACL helpers
$LUDUS ansible collection add microsoft.iis || true                       # IIS modules (oscar_vulnweb)

echo "==> Off-the-shelf Galaxy roles"
for r in geerlingguy.docker geerlingguy.pip gantsign.golang e1a.ludus_windows_smb_share; do
  $LUDUS ansible role add "$r" || true
done

echo "==> Pro / subscription roles"
$LUDUS ansible subscription-roles install -n "ludus_mythic,ludus_bulk_ad_content,ludus_local_users_and_groups,ludus_ghosts_client" || true
# Assumed already present on the server: badsectorlabs.ludus_mssql, ludus_adcs,
# ludus_elastic_agent, ludus_elastic_container.

echo "==> Custom TLO roles (this repo)"
for role in roles/*/; do
  name="$(basename "$role")"
  [ -f "${role}tasks/main.yml" ] || { echo "  skip $name (no tasks/main.yml)"; continue; }
  echo "  adding $name"
  $LUDUS ansible role add -d "$role" -f || echo "  !! failed to add $name"
done

echo "==> Done. Verify:  $LUDUS ansible role list"
