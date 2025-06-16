#!/usr/bin/env bash
set -euo pipefail

# -------------------- Configuration --------------------
ZSH_THEME="af-magic"
ZSH_PLUGINS=(git zsh-autosuggestions zsh-syntax-highlighting fast-syntax-highlighting zsh-autocomplete copypath copyfile sudo command-not-found conda jamp)
PKGS=(curl git wget zsh build-essential lsd vim tmux xclip speedtest-cli net-tools proxychains docker.io docker-compose openjdk-21-jdk)

# Flags
IRAN_MIRROR=false

# -------------------- Argument Parser --------------------
for arg in "$@"; do
  case $arg in
    --iran)
      IRAN_MIRROR=true
      shift
      ;;
  esac
  shift
done

# -------------------- Functions --------------------

log() { echo -e "\033[1;32m[INFO]\033[0m $*"; }
err() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

ensure_root() {
  if [[ "$EUID" -ne 0 ]]; then
    err "This script must be run as root. Try: sudo $0"
  fi
}

install_packages() {
  log "Installing packages: ${PKGS[*]}"
  apt update || true
  DEBIAN_FRONTEND=noninteractive apt install -y "${PKGS[@]}"
}

install_zsh() {
  local user_home="$(eval echo "~$SUDO_USER")"
  if [ -d "$user_home/.oh-my-zsh" ]; then
    log "Oh My Zsh already installed. Skipping."
    return
  fi

  log "Installing Oh My Zsh"
  su -l "$SUDO_USER" -s /bin/bash <<EOF
    export RUNZSH=no
    export KEEP_ZSHRC=yes
    sh -c "\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
EOF
}

configure_zshrc() {
  local user_home
  user_home="$(eval echo "~$SUDO_USER")"
  local zshrc="$user_home/.zshrc"

  log "Updating .zshrc theme and plugins"
  sed -i "s/^ZSH_THEME=.*/ZSH_THEME=\"$ZSH_THEME\"/" "$zshrc" || echo "ZSH_THEME=\"$ZSH_THEME\"" >> "$zshrc"
  sed -i "s/^plugins=.*/plugins=(${ZSH_PLUGINS[*]})/" "$zshrc" || echo "plugins=(${ZSH_PLUGINS[*]})" >> "$zshrc"

  log "Appending aliases and environment settings to .zshrc"
  cat <<EOF >> "$zshrc"

# ---------------- Custom ZSH Aliases & Env ----------------
alias ls='lsd'
alias l='ls -l'
alias la='ls -a'
alias lla='ls -la'
alias lt='ls --tree'
alias code='code . --new-window '
alias zshConfig='vim ~/.zshrc'
alias sinaComSis='wine "/home/saman/.wine/drive_c/Program Files/Sina/Sina Communication System Co/SinaAutomationMain.exe"'
alias frEnable="setxkbmap -layout us,ir -option 'grp:alt_shift_toggle'"
alias sshNet='ssh root@45.145.6.153'
alias sshNet2='ssh root@185.31.200.115'
alias sshJenkins20='ssh jenkins@192.168.50.20'
alias "ip a"="ip --color=always a"

export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
export PATH=\$JAVA_HOME/bin:\$PATH

# >>> conda initialize >>>
__conda_setup="\$(~/.miniconda3/bin/conda shell.zsh hook 2> /dev/null)"
if [ \$? -eq 0 ]; then
    eval "\$__conda_setup"
else
    if [ -f "~/.miniconda3/etc/profile.d/conda.sh" ]; then
        . "~/.miniconda3/etc/profile.d/conda.sh"
    else
        export PATH="~/.miniconda3/bin:\$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<
EOF
}

setup_vim() {
  local user_home="$(eval echo "~$SUDO_USER")"
  log "Creating .vimrc"
  cat <<'EOF' > "$user_home/.vimrc"
# [Your full vimrc content inserted here]
EOF
  chown "$SUDO_USER":"$SUDO_USER" "$user_home/.vimrc"
}

setup_tmux() {
  local user_home="$(eval echo "~$SUDO_USER")"
  log "Creating .tmux.conf"
  cat <<'EOF' > "$user_home/.tmux.conf"
# [Your full tmux.conf content inserted here]
EOF
  chown "$SUDO_USER":"$SUDO_USER" "$user_home/.tmux.conf"
}

install_miniconda() {
  local miniconda_path="/home/$SUDO_USER/.miniconda3"
  if [ -d "$miniconda_path" ]; then
    log "Miniconda already installed at $miniconda_path. Skipping."
    return
  fi

  local installer="Miniconda3.sh"
  log "Installing Miniconda silently"
  curl -fsSL -o "$installer" https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
  bash "$installer" -b -p "$miniconda_path"
  chown -R "$SUDO_USER":"$SUDO_USER" "$miniconda_path"
  rm "$installer"

  log "Running conda init and disabling auto-activation"
  su -l "$SUDO_USER" -s /bin/bash -c "$miniconda_path/bin/conda init zsh"
  su -l "$SUDO_USER" -s /bin/bash -c "$miniconda_path/bin/conda config --set auto_activate_base false"
}

setup_docker_iran_mirror() {
  log "Configuring Docker for Iran mirror"
  cat > /etc/docker/daemon.json <<EOF
{
  "insecure-registries" : ["https://docker.arvancloud.ir"],
  "registry-mirrors": ["https://docker.arvancloud.ir"]
}
EOF
  docker logout || true
  systemctl restart docker
}

# -------------------- Main --------------------
ensure_root
install_packages
install_zsh
configure_zshrc
setup_vim
setup_tmux
install_miniconda

if [ "$IRAN_MIRROR" = true ]; then
  setup_docker_iran_mirror
fi

log "✅ Bootstrap complete. Logout and re-login to apply shell changes."
