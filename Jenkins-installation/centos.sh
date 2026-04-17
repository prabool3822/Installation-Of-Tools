#!/usr/bin/env bash
set -Eeuo pipefail

LOG_FILE="/var/log/jenkins-install-rhel.log"
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
  echo "Check logs with:"
  echo "  sudo systemctl status jenkins --no-pager -l"
  echo "  sudo journalctl -u jenkins -n 100 --no-pager"
  exit 1
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run with:"
    echo "sudo bash install-jenkins-rhel.sh"
    exit 1
  fi
}

detect_rhel_like() {
  [[ -f /etc/os-release ]] || fail "/etc/os-release not found"

  . /etc/os-release
  echo "Detected OS: ${PRETTY_NAME:-Unknown}"

  case "${ID:-}" in
    rhel|rocky|almalinux|ol|centos|amzn|fedora) ;;
    *)
      if [[ "${ID_LIKE:-}" != *"rhel"* && "${ID_LIKE:-}" != *"fedora"* ]]; then
        fail "This script supports only RHEL-like/Fedora systems."
      fi
      ;;
  esac
}

pkg_update() {
  if command -v dnf >/dev/null 2>&1; then
    dnf upgrade -y
  elif command -v yum >/dev/null 2>&1; then
    yum update -y
  else
    fail "Neither dnf nor yum found"
  fi
}

pkg_install() {
  if command -v dnf >/dev/null 2>&1; then
    dnf install -y "$@"
  elif command -v yum >/dev/null 2>&1; then
    yum install -y "$@"
  else
    fail "Neither dnf nor yum found"
  fi
}

install_prereqs() {
  log "Installing required packages"
  pkg_install wget curl fontconfig java-21-openjdk
  java -version || fail "Java installation failed"
}

setup_jenkins_repo() {
  log "Adding Jenkins rpm-stable repository"
  wget -O /etc/yum.repos.d/jenkins.repo \
    https://pkg.jenkins.io/rpm-stable/jenkins.repo
}

install_jenkins() {
  log "Installing Jenkins"
  pkg_install jenkins
  systemctl daemon-reload
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

open_firewall() {
  local port="$1"

  if command -v firewall-cmd >/dev/null 2>&1; then
    if systemctl is-active firewalld >/dev/null 2>&1; then
      firewall-cmd --permanent --add-port="${port}/tcp" || true
      firewall-cmd --reload || true
    fi
  fi
}

start_jenkins() {
  log "Starting Jenkins"
  systemctl enable jenkins
  systemctl reset-failed jenkins || true
  systemctl restart jenkins
}

wait_for_jenkins() {
  local retries=24
  local delay=5

  for ((i=1; i<=retries; i++)); do
    if systemctl is-active --quiet jenkins; then
      echo "Jenkins is active."
      return 0
    fi
    echo "Waiting for Jenkins... ($i/$retries)"
    sleep "$delay"
  done

  return 1
}

print_success() {
  local port="$1"
  local public_ip=""

  public_ip="$(curl -fsS --max-time 2 http://169.254.169.254/latest/meta-data/public-ipv4 || true)"

  echo
  echo "Jenkins installed successfully."
  echo "Open in browser:"
  if [[ -n "$public_ip" ]]; then
    echo "http://${public_ip}:${port}"
  else
    echo "http://<your-server-ip>:${port}"
  fi

  echo
  if [[ -f /var/lib/jenkins/secrets/initialAdminPassword ]]; then
    echo "Initial Admin Password:"
    cat /var/lib/jenkins/secrets/initialAdminPassword
  else
    echo "Password file not found yet. Try again after a few seconds:"
    echo "sudo cat /var/lib/jenkins/secrets/initialAdminPassword"
  fi

  echo
  echo "Make sure your EC2 Security Group allows inbound TCP ${port}."
}

print_failure() {
  echo
  echo "Jenkins failed to start."
  systemctl status jenkins --no-pager -l || true
  echo
  journalctl -u jenkins -n 80 --no-pager || true
}

main() {
  require_root
  detect_rhel_like
  pkg_update
  install_prereqs
  setup_jenkins_repo
  install_jenkins

  if is_port_in_use "$JENKINS_PORT"; then
    echo "Port $JENKINS_PORT is busy. Switching to $JENKINS_FALLBACK_PORT."
    set_jenkins_port_override "$JENKINS_FALLBACK_PORT"
    JENKINS_PORT="$JENKINS_FALLBACK_PORT"
  fi

  open_firewall "$JENKINS_PORT"
  start_jenkins

  if wait_for_jenkins; then
    print_success "$JENKINS_PORT"
  else
    print_failure
    fail "Jenkins did not start successfully."
  fi
}

main "$@"