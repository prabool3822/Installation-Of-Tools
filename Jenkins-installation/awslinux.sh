#!/usr/bin/env bash
set -Eeuo pipefail

LOG_FILE="/var/log/jenkins-install-amzn.log"
JENKINS_PORT="${JENKINS_PORT:-8080}"
FALLBACK_PORT="8081"

exec > >(tee -a "$LOG_FILE") 2>&1

log() {
  echo
  echo "========== $1 =========="
}

fail() {
  echo
  echo "ERROR: $1"
  echo "Check logs:"
  echo "  sudo systemctl status jenkins --no-pager -l"
  echo "  sudo journalctl -u jenkins -n 100 --no-pager"
  exit 1
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run with:"
    echo "sudo bash script.sh"
    exit 1
  fi
}

check_os() {
  [[ -f /etc/os-release ]] || fail "Cannot detect OS"
  . /etc/os-release

  if [[ "${ID}" != "amzn" ]]; then
    fail "This script is only for Amazon Linux"
  fi

  echo "Detected: ${PRETTY_NAME}"
}

install_java() {
  log "Installing Java 21 (Amazon Corretto)"
  dnf install -y java-21-amazon-corretto fontconfig

  java -version || fail "Java install failed"

  if ! java -version 2>&1 | grep -q '"21'; then
    fail "Java 21 is not active"
  fi
}

add_jenkins_repo() {
  log "Adding Jenkins repository"
  wget -O /etc/yum.repos.d/jenkins.repo \
    https://pkg.jenkins.io/rpm-stable/jenkins.repo

  rpm --import https://pkg.jenkins.io/rpm-stable/jenkins.io-2026.key
}

install_jenkins() {
  log "Installing Jenkins"
  dnf install -y jenkins
}

port_in_use() {
  ss -ltn "( sport = :$1 )" | grep -q ":$1"
}

set_port() {
  local PORT="$1"
  log "Setting Jenkins port to $PORT"

  mkdir -p /etc/systemd/system/jenkins.service.d

  cat > /etc/systemd/system/jenkins.service.d/override.conf <<EOF
[Service]
Environment="JENKINS_PORT=$PORT"
EOF

  systemctl daemon-reload
}

open_firewall() {
  local PORT="$1"

  if systemctl is-active firewalld >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port=${PORT}/tcp || true
    firewall-cmd --reload || true
  fi
}

start_jenkins() {
  log "Starting Jenkins"
  systemctl enable jenkins
  systemctl reset-failed jenkins || true
  systemctl restart jenkins
}

wait_for_start() {
  for i in {1..24}; do
    if systemctl is-active --quiet jenkins; then
      echo "Jenkins is running"
      return 0
    fi
    echo "Waiting for Jenkins... ($i/24)"
    sleep 5
  done
  return 1
}

print_success() {
  local PORT="$1"
  local PUBLIC_IP=""

  PUBLIC_IP="$(curl -fsS --max-time 2 http://169.254.169.254/latest/meta-data/public-ipv4 || true)"

  echo
  echo "========== SUCCESS =========="
  if [[ -n "$PUBLIC_IP" ]]; then
    echo "Access Jenkins: http://$PUBLIC_IP:$PORT"
  else
    echo "Access Jenkins: http://<your-ip>:$PORT"
  fi

  echo
  if [[ -f /var/lib/jenkins/secrets/initialAdminPassword ]]; then
    echo "Initial Admin Password:"
    cat /var/lib/jenkins/secrets/initialAdminPassword
  else
    echo "Wait a little, then run:"
    echo "sudo cat /var/lib/jenkins/secrets/initialAdminPassword"
  fi
}

main() {
  require_root
  check_os
  install_java
  add_jenkins_repo
  install_jenkins

  if port_in_use "$JENKINS_PORT"; then
    echo "Port $JENKINS_PORT busy -> switching to $FALLBACK_PORT"
    set_port "$FALLBACK_PORT"
    JENKINS_PORT="$FALLBACK_PORT"
  fi

  open_firewall "$JENKINS_PORT"
  start_jenkins

  if wait_for_start; then
    print_success "$JENKINS_PORT"
  else
    fail "Jenkins failed to start"
  fi
}

main "$@"