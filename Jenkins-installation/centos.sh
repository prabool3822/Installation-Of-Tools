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
  log "Checking OS"

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
  log "Updating packages"

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
  log "Checking required packages"

  pkg_install wget curl fontconfig

  if command -v java >/dev/null 2>&1 && java -version 2>&1 | grep -q '"21'; then
    echo "Java 21 already installed"
    java -version
    return 0
  fi

  echo "Installing Java 21..."
  pkg_install java-21-openjdk

  java -version || fail "Java installation failed"

  if ! java -version 2>&1 | grep -q '"21'; then
    fail "Java 21 is not active"
  fi
}

setup_jenkins_repo() {
  log "Adding Jenkins rpm-stable repository"

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
    systemctl daemon-reload
    return 0
  fi

  echo "Installing Jenkins..."
  pkg_install jenkins
  systemctl daemon-reload
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

open_firewall() {
  local port="$1"

  log "Checking firewalld"

  if command -v firewall-cmd >/dev/null 2>&1; then
    if systemctl is-active --quiet firewalld; then
      firewall-cmd --permanent --add-port="${port}/tcp" || true
      firewall-cmd --reload || true
      echo "Opened port ${port} in firewalld"
    else
      echo "firewalld is not active"
    fi
  else
    echo "firewall-cmd not installed"
  fi
}

start_jenkins() {
  log "Starting Jenkins"

  systemctl daemon-reload
  systemctl enable jenkins
  systemctl reset-failed jenkins || true
  systemctl restart jenkins
}

wait_for_jenkins() {
  log "Waiting for Jenkins"

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
  echo "========== SUCCESS =========="

  echo
  echo "Jenkins status:"
  systemctl status jenkins --no-pager -l || true

  echo
  echo "Listening port:"
  ss -tulnp | grep -E ":${port}\b" || true

  echo
  echo "Open Jenkins:"
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
  journalctl -u jenkins -n 100 --no-pager || true
}

main() {
  require_root
  detect_rhel_like
  pkg_update
  install_prereqs
  setup_jenkins_repo
  install_jenkins

  stop_jenkins_if_running

  if is_port_in_use_by_other_process "$JENKINS_PORT"; then
    echo "Port $JENKINS_PORT is used by another process."
    echo "Switching Jenkins to $JENKINS_FALLBACK_PORT."
    JENKINS_PORT="$JENKINS_FALLBACK_PORT"
  fi

  set_jenkins_port_override "$JENKINS_PORT"
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
