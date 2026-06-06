#!/usr/bin/env bash
# alice 로 SSH 타겟 접속 (대화형). 비밀번호는 brokering 으로 화면에 표시됨.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/common.sh"

WHO="${1:-alice}"
export BOUNDARY_TOKEN="$(bday_token "$WHO")"
echo "==> '$WHO' 로 ssh-target 접속 (계정 $SSH_USER, 비번은 Boundary 가 brokering)"
exec boundary connect ssh -target-id="$(tf_out ssh_target_id)" \
  -token=env://BOUNDARY_TOKEN \
  -- -l "$SSH_USER" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
