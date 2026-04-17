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
    echo "Run this script with sudo:"
    echo "sudo bash install-jenkins-ubuntu-ec2.sh"
    exit 1
  fi
}

check_ubuntu() {
  if [[ ! -f /etc/os-release ]]; then
    fail "/etc/os-release not found. Unsupported system."
  fi

  . /etc/os-release

  if [[ "${ID:-}" != "ubuntu" && "${ID_LIKE:-}" != *"debian"* ]]; then
    fail "This script is for Ubuntu/Debian-like systems only."
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
  fail "apt update failed after multiple attempts."
}

install_base_packages() {
  log "Installing required packages"
  export DEBIAN_FRONTEND=noninteractive
  apt_update_retry
  apt-get install -y ca-certificates curl wget gnupg fontconfig lsb-release
}

install_java_21() {
  log "Installing Java 21"
  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y openjdk-21-jre

  if ! command -v java >/dev/null 2>&1; then
    fail "Java command not found after installation."
  fi

  java -version || fail "Java installation appears broken."

  if ! java -version 2>&1 | grep -q '"21\.'; then
    fail "Java 21 is not active. Jenkins current LTS needs Java 21 or newer supported version."
  fi
}

setup_jenkins_repo() {
  log "Configuring Jenkins LTS repository"

  mkdir -p /etc/apt/keyrings

  wget -O /etc/apt/keyrings/jenkins-keyring.asc \
    https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key

  cat >/etc/apt/sources.list.d/jenkins.list <<'EOF'
deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/
EOF

  apt_update_retry
}

install_jenkins() {
  log "Installing Jenkins"
  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y jenkins
}

is_port_in_use() {
  local port="$1"
  ss -ltn "( sport = :$port )" | grep -q ":$port"
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

  if command -v ufw >/dev/null 2>&1; then
    if ufw status 2>/dev/null | grep -qi "Status: active"; then
      ufw allow "${port}/tcp" || true
    fi
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
  local retries=24
  local delay=5

  for ((i=1; i<=retries; i++)); do
    if systemctl is-active --quiet jenkins; then
      echo "Jenkins is active."
      return 0
    fi
    echo "Waiting for Jenkins to start... ($i/$retries)"
    sleep "$delay"
  done

  return 1
}

print_failure_diagnostics() {
  echo
  echo "===== Jenkins failed to start ====="
  systemctl status jenkins --no-pager -l || true
  echo
  journalctl -u jenkins -n 80 --no-pager || true
}

print_success_info() {
  local port="$1"
  echo
  echo "===== Jenkins installed successfully ====="
  echo "Service status:"
  systemctl status jenkins --no-pager -l || true

  local public_ip=""
  public_ip="$(curl -fsS --max-time 2 http://169.254.169.254/latest/meta-data/public-ipv4 || true)"

  echo
  echo "Open Jenkins in your browser:"
  if [[ -n "$public_ip" ]]; then
    echo "http://${public_ip}:${port}"
  else
    echo "http://<your-ec2-public-ip>:${port}"
  fi

  echo
  if [[ -f /var/lib/jenkins/secrets/initialAdminPassword ]]; then
    echo "Initial Admin Password:"
    cat /var/lib/jenkins/secrets/initialAdminPassword
  else
    echo "Jenkins started, but initialAdminPassword file is not visible yet."
    echo "Try after 15-30 seconds:"
    echo "sudo cat /var/lib/jenkins/secrets/initialAdminPassword"
  fi

  echo
  echo "Important: make sure your EC2 Security Group allows inbound TCP ${port}."
}

main() {
  require_root
  check_ubuntu
  install_base_packages
  install_java_21
  setup_jenkins_repo
  install_jenkins

  if is_port_in_use "$JENKINS_PORT"; then
    echo "Port $JENKINS_PORT is already in use. Switching Jenkins to $JENKINS_FALLBACK_PORT."
    set_jenkins_port_override "$JENKINS_FALLBACK_PORT"
    JENKINS_PORT="$JENKINS_FALLBACK_PORT"
  fi

  allow_firewall_if_needed "$JENKINS_PORT"
  start_jenkins

  if wait_for_service; then
    print_success_info "$JENKINS_PORT"
  else
    print_failure_diagnostics
    fail "Jenkins did not start successfully."
  fi
}

main "$@"