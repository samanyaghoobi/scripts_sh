# ============================
#        ZSH Configuration
# ============================
# Source .aliases if it exists
[ -f ~/.aliases ] && source ~/.aliases

# Source .zsh_aliases if it exists
[ -f ~/.zsh_aliases ] && source ~/.zsh_aliases

# ----------------------------
#     ZSH Environment Variables
# ----------------------------
export ZSH="$HOME/.oh-my-zsh"
export PATH="$PATH:/home/saman/.local/bin"
export V2RAY_LOCATION_ASSET=/usr/local/share/v2ray/
export MIBS=+custom
export CHROME_EXECUTABLE=/snap/bin/chromium
# proxies
#export http_proxy="https://127.0.0.1:20171"
#export https_proxy="https://127.0.0.1:20171"
#export all_proxy="socks5://127.0.0.1:20170"

# bypass proxy for local & RFC1918 ranges
#export NO_PROXY="localhost,127.0.0.1,::1,.local,.sinacomsys.local,127.0.0.0/8,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
#export no_proxy="$NO_PROXY"

# ----------------------------
#     ZSH Theme and Colorization
# ----------------------------
#source ~/.afmagic-custom.zsh-theme
ZSH_THEME="af-magic"
#ZSH_THEME="bira"
#ZSH_THEME="fox"
#ZSH_THEME="fino-time"
ZSH_COLORIZE_TOOL=chroma
ZSH_COLORIZE_STYLE="colorful"

# ----------------------------
#     ZLE Widgets
# ----------------------------
# Define missing ZLE widgets
zle -N menu-search
zle -N recent-paths

# ----------------------------
#     Plugins
# ----------------------------
plugins=(
    eza
    git
    sudo
    copypath
    colored-man-pages
    command-not-found
    zsh-autosuggestions
    fast-syntax-highlighting
)

# ----------------------------
#     Enable Correction
# ----------------------------
ENABLE_CORRECTION="true"

# ----------------------------
#     Source Oh My Zsh
# ----------------------------
source $ZSH/oh-my-zsh.sh

# ----------------------------
#     Additional Configurations
# ----------------------------
[[ -f ~/.zsh_aliases ]] && source ~/.zsh_aliases
[[ -f ~/.copyfile ]] && source ~/.copyfile

# ----------------------------
#     Conda Initialization
# ----------------------------
if command -v conda &> /dev/null; then
    :
else
    if [ ! -d "/home/saman/miniconda3" ]; then
        wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ~/.Miniconda.sh
        bash ~/.Miniconda.sh -b -p /home/saman/miniconda3
        rm ~/.Miniconda.sh
    fi
# export PATH="/home/saman/miniconda3/bin:$PATH"  # commented out by conda initialize
fi
# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('/home/saman/miniconda3/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/home/saman/miniconda3/etc/profile.d/conda.sh" ]; then
        . "/home/saman/miniconda3/etc/profile.d/conda.sh"
    else
        export PATH="/home/saman/miniconda3/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<

# ----------------------------
#     Flutter
# ----------------------------
FLUTTER_PATH="/home/saman/deployment/flutter/bin"
export PATH="$PATH":"$HOME/.pub-cache/bin"
if [ -d "$FLUTTER_PATH" ] && [[ ":$PATH:" != *":$FLUTTER_PATH:"* ]]; then
    export PATH="$PATH:$FLUTTER_PATH"
fi

## [Completion]
## Completion scripts setup. Remove the following line to uninstall
[[ -f /home/saman/.dart-cli-completion/zsh-config.zsh ]] && . /home/saman/.dart-cli-completion/zsh-config.zsh || true
## [/Completion]


# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('/home/saman/miniconda3/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/home/saman/miniconda3/etc/profile.d/conda.sh" ]; then
        . "/home/saman/miniconda3/etc/profile.d/conda.sh"
    else
        export PATH="/home/saman/miniconda3/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<

