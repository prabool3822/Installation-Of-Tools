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
    echo "sudo bash install-jenkins-amzn.sh"
    exit 1
  fi
}

check_os() {
  log "Checking OS"

  [[ -f /etc/os-release ]] || fail "Cannot detect OS"
  . /etc/os-release

  if [[ "${ID:-}" != "amzn" ]]; then
    fail "This script is only for Amazon Linux"
  fi

  echo "Detected: ${PRETTY_NAME:-Amazon Linux}"
}

install_base_packages() {
  log "Installing base packages"

  dnf install -y \
    wget \
    curl \
    fontconfig
}

install_java() {
  log "Checking Java 21"

  if command -v java >/dev/null 2>&1 && java -version 2>&1 | grep -q '"21'; then
    echo "Java 21 already installed"
    java -version
    return 0
  fi

  echo "Installing Java 21 Amazon Corretto..."

  dnf install -y java-21-amazon-corretto

  java -version || fail "Java install failed"

  if ! java -version 2>&1 | grep -q '"21'; then
    fail "Java 21 is not active"
  fi
}

add_jenkins_repo() {
  log "Configuring Jenkins repository"

  if [[ ! -f /etc/yum.repos.d/jenkins.repo ]]; then
    wget -O /etc/yum.repos.d/jenkins.repo \
      https://pkg.jenkins.io/rpm-stable/jenkins.repo
  else
    echo "Jenkins repo already exists"
  fi

  rpm --import https://pkg.jenkins.io/rpm-stable/jenkins.io-2026.key
}

is_jenkins_installed() {
  rpm -q jenkins >/dev/null 2>&1
}

install_jenkins() {
  log "Checking Jenkins installation"

  if is_jenkins_installed; then
    echo "Jenkins is already installed. Skipping reinstall."
    return 0
  fi

  echo "Installing Jenkins..."
  dnf install -y jenkins
}

stop_jenkins_if_running() {
  log "Stopping Jenkins before port check"

  if systemctl list-unit-files | grep -q '^jenkins.service'; then
    systemctl stop jenkins || true
  fi
}

port_in_use_by_other_process() {
  local PORT="$1"

  if ! ss -ltnp "( sport = :$PORT )" | grep -q ":$PORT"; then
    return 1
  fi

  if ss -ltnp "( sport = :$PORT )" | grep ":$PORT" | grep -qi jenkins; then
    return 1
  fi

  return 0
}

set_port() {
  local PORT="$1"

  log "Setting Jenkins port to $PORT"

  mkdir -p /etc/systemd/system/jenkins.service.d

  cat >/etc/systemd/system/jenkins.service.d/override.conf <<EOF
[Service]
Environment="JENKINS_PORT=$PORT"
EOF

  systemctl daemon-reload
}

open_firewall() {
  local PORT="$1"

  log "Checking firewalld"

  if systemctl is-active --quiet firewalld; then
    firewall-cmd --permanent --add-port="${PORT}/tcp" || true
    firewall-cmd --reload || true
    echo "Opened port $PORT in firewalld"
  else
    echo "firewalld is not active"
  fi
}

start_jenkins() {
  log "Starting Jenkins"

  systemctl daemon-reload
  systemctl enable jenkins
  systemctl reset-failed jenkins || true
  systemctl restart jenkins
}

wait_for_start() {
  log "Waiting for Jenkins"

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

  echo
  echo "Jenkins status:"
  systemctl status jenkins --no-pager -l || true

  echo
  echo "Listening port:"
  ss -tulnp | grep -E ":${PORT}\b" || true

  echo
  if [[ -n "$PUBLIC_IP" ]]; then
    echo "Access Jenkins: http://$PUBLIC_IP:$PORT"
  else
    echo "Access Jenkins: http://<your-ec2-public-ip>:$PORT"
  fi

  echo
  if [[ -f /var/lib/jenkins/secrets/initialAdminPassword ]]; then
    echo "Initial Admin Password:"
    cat /var/lib/jenkins/secrets/initialAdminPassword
  else
    echo "Wait a little, then run:"
    echo "sudo cat /var/lib/jenkins/secrets/initialAdminPassword"
  fi

  echo
  echo "Important:"
  echo "Allow inbound TCP $PORT in your EC2 Security Group."
}

main() {
  require_root
  check_os
  install_base_packages
  install_java
  add_jenkins_repo
  install_jenkins

  sleep 7
  systemctl stop jenkins || true
  sleep 5

  if port_in_use_by_other_process "$JENKINS_PORT"; then
    echo "Port $JENKINS_PORT is used by another process."
    echo "Switching Jenkins to $FALLBACK_PORT"
    JENKINS_PORT="$FALLBACK_PORT"
  fi

  set_port "$JENKINS_PORT"
  open_firewall "$JENKINS_PORT"
  start_jenkins

  if wait_for_start; then
    print_success "$JENKINS_PORT"
  else
    fail "Jenkins failed to start"
  fi
}

main "$@"
