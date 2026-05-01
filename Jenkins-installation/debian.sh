#!/usr/bin/env bash
set -Eeuo pipefail

LOG_FILE="/var/log/jenkins-install.log"

JENKINS_PORT="${JENKINS_PORT:-8080}"
JENKINS_FALLBACK_PORT="8081"

exec > >(tee -a "$LOG_FILE") 2>&1

log() {
  echo
  echo "========== $1 =========="
}

fail() {
  echo
  echo "ERROR: $1"
  echo "Check logs:"
  echo "  sudo journalctl -u jenkins -n 100 --no-pager"
  echo "  sudo systemctl status jenkins --no-pager -l"
  exit 1
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run with sudo:"
    echo "sudo bash install-jenkins-ubuntu-ec2.sh"
    exit 1
  fi
}

check_ubuntu() {
  log "Checking OS"

  if [[ ! -f /etc/os-release ]]; then
    fail "/etc/os-release not found"
  fi

  . /etc/os-release

  if [[ "${ID:-}" != "ubuntu" && "${ID_LIKE:-}" != *"debian"* ]]; then
    fail "This script supports Ubuntu/Debian only"
  fi

  echo "Detected OS: ${PRETTY_NAME:-Unknown}"
}

apt_update_retry() {
  local n=0

  until [[ $n -ge 3 ]]; do
    if apt-get update; then
      return 0
    fi

    n=$((n + 1))
    echo "apt update failed. Retrying... ($n/3)"
    sleep 3
  done

  fail "apt update failed after 3 attempts"
}

install_base_packages() {
  log "Installing required packages"

  export DEBIAN_FRONTEND=noninteractive

  apt_update_retry

  apt-get install -y \
    ca-certificates \
    curl \
    wget \
    gnupg \
    fontconfig \
    lsb-release
}

install_java_21() {
  log "Checking Java 21"

  if command -v java >/dev/null 2>&1 && java -version 2>&1 | grep -q '"21\.'; then
    echo "Java 21 already installed"
    java -version
    return 0
  fi

  echo "Installing Java 21..."

  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y openjdk-21-jre

  java -version || fail "Java installation failed"

  if ! java -version 2>&1 | grep -q '"21\.'; then
    fail "Java 21 is not active"
  fi
}

setup_jenkins_repo() {
  log "Configuring Jenkins repository"

  mkdir -p /etc/apt/keyrings

  if [[ ! -f /etc/apt/keyrings/jenkins-keyring.asc ]]; then
    wget -O /etc/apt/keyrings/jenkins-keyring.asc \
      https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key
  else
    echo "Jenkins key already exists"
  fi

  cat >/etc/apt/sources.list.d/jenkins.list <<'EOF'
deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/
EOF

  apt_update_retry
}

is_jenkins_installed() {
  dpkg -s jenkins >/dev/null 2>&1
}

install_jenkins() {
  log "Checking Jenkins installation"

  if is_jenkins_installed; then
    echo "Jenkins is already installed. Skipping reinstall."
    return 0
  fi

  echo "Installing Jenkins..."

  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y jenkins
}

stop_jenkins_if_running() {
  log "Stopping Jenkins before port check"

  if systemctl list-unit-files | grep -q '^jenkins.service'; then
    systemctl stop jenkins || true
  fi
}

is_port_in_use_by_other_process() {
  local port="$1"

  if ! ss -ltnp "( sport = :$port )" | grep -q ":$port"; then
    return 1
  fi

  if ss -ltnp "( sport = :$port )" | grep ":$port" | grep -qi jenkins; then
    return 1
  fi

  return 0
}

set_jenkins_port_override() {
  local port="$1"

  log "Setting Jenkins port to $port"

  mkdir -p /etc/systemd/system/jenkins.service.d

  cat >/etc/systemd/system/jenkins.service.d/override.conf <<EOF
[Service]
Environment="JENKINS_PORT=$port"
EOF

  systemctl daemon-reload
}

allow_firewall_if_needed() {
  local port="$1"

  log "Checking UFW firewall"

  if command -v ufw >/dev/null 2>&1; then
    if ufw status 2>/dev/null | grep -qi "Status: active"; then
      ufw allow "${port}/tcp" || true
      echo "Allowed port ${port} in UFW"
    else
      echo "UFW is not active"
    fi
  else
    echo "UFW not installed"
  fi
}

start_jenkins() {
  log "Starting Jenkins"

  systemctl daemon-reload
  systemctl enable jenkins
  systemctl reset-failed jenkins || true
  systemctl restart jenkins
}

wait_for_service() {
  log "Waiting for Jenkins service"

  local retries=24
  local delay=5

  for ((i=1; i<=retries; i++)); do
    if systemctl is-active --quiet jenkins; then
      echo "Jenkins is active"
      return 0
    fi

    echo "Waiting for Jenkins... ($i/$retries)"
    sleep "$delay"
  done

  return 1
}

print_failure_diagnostics() {
  echo
  echo "===== Jenkins failed to start ====="
  systemctl status jenkins --no-pager -l || true

  echo
  journalctl -u jenkins -n 100 --no-pager || true
}

print_success_info() {
  local port="$1"

  echo
  echo "===== Jenkins installed/configured successfully ====="

  echo
  echo "Jenkins status:"
  systemctl status jenkins --no-pager -l || true

  echo
  echo "Listening port:"
  ss -tulnp | grep -E ":${port}\b" || true

  local public_ip=""
  public_ip="$(curl -fsS --max-time 2 http://169.254.169.254/latest/meta-data/public-ipv4 || true)"

  echo
  echo "Open Jenkins:"
  if [[ -n "$public_ip" ]]; then
    echo "http://${public_ip}:${port}"
  else
    echo "http://<your-ec2-public-ip>:${port}"
  fi

  echo
  echo "Initial Admin Password:"
  if [[ -f /var/lib/jenkins/secrets/initialAdminPassword ]]; then
    cat /var/lib/jenkins/secrets/initialAdminPassword
  else
    echo "Password file not ready yet."
    echo "Run this after 30 seconds:"
    echo "sudo cat /var/lib/jenkins/secrets/initialAdminPassword"
  fi

  echo
  echo "Important:"
  echo "Allow inbound TCP ${port} in EC2 Security Group."
}

main() {
  require_root
  check_ubuntu
  install_base_packages
  install_java_21
  setup_jenkins_repo
  install_jenkins
  
  sleep 7
  systemctl stop jenkins || true
  sleep 5
  
  if is_port_in_use_by_other_process "$JENKINS_PORT"; then
    echo "Port $JENKINS_PORT is used by another process."
    echo "Switching Jenkins to fallback port $JENKINS_FALLBACK_PORT"
    JENKINS_PORT="$JENKINS_FALLBACK_PORT"
  fi

  set_jenkins_port_override "$JENKINS_PORT"
  allow_firewall_if_needed "$JENKINS_PORT"
  start_jenkins

  if wait_for_service; then
    print_success_info "$JENKINS_PORT"
  else
    print_failure_diagnostics
    fail "Jenkins failed to start"
  fi
}

main "$@"
