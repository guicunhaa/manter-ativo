#!/bin/bash
set -euo pipefail
SRC="${1:?missing helpers dir}"
USER_NAME="${2:?missing user name}"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
printf '%s ALL=(root) NOPASSWD: /usr/local/bin/manter-ativo-on, /usr/local/bin/manter-ativo-off\n' "$USER_NAME" >"$TMP"
install -d -o root -g wheel -m 755 /usr/local/bin
install -o root -g wheel -m 755 "$SRC/manter-ativo-on" /usr/local/bin/manter-ativo-on
install -o root -g wheel -m 755 "$SRC/manter-ativo-off" /usr/local/bin/manter-ativo-off
install -o root -g wheel -m 440 "$TMP" /etc/sudoers.d/manter-ativo
if ! /usr/sbin/visudo -cf /etc/sudoers.d/manter-ativo >/dev/null; then
  rm -f /etc/sudoers.d/manter-ativo
  echo "Regra sudoers invalida" >&2
  exit 1
fi
echo OK
