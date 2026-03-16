export AUTOSWITCH_VERSION="3.9.0"
export AUTOSWITCH_FILE=".venv"

AUTOSWITCH_RED="\e[31m"
AUTOSWITCH_GREEN="\e[32m"
AUTOSWITCH_PURPLE="\e[35m"
AUTOSWITCH_BOLD="\e[1m"
AUTOSWITCH_NORMAL="\e[0m"

function _validated_source() {
    local target_path="$1"

    if [[ "$target_path" == *'..'* ]]; then
        (>&2 printf "AUTOSWITCH WARNING: ")
        (>&2 printf "target virtualenv contains invalid characters\n")
        (>&2 printf "virtualenv activation cancelled\n")
        return
    else
        source "$target_path"
    fi
}

function _virtual_env_dir() {
    local project_dir="${1:-$PWD}"
    printf "%s/%s" "$project_dir" "$AUTOSWITCH_FILE"
}

function _python_version() {
    local PYTHON_BIN="$1"
    if [[ -f "$PYTHON_BIN" ]]; then
        printf "%s" "$($PYTHON_BIN --version 2>&1)"
    else
        printf "unknown"
    fi
}

function _autoswitch_message() {
    if [ -z "$AUTOSWITCH_SILENT" ]; then
        (>&2 printf "$@")
    fi
}

function _is_valid_virtualenv() {
    [[ -d "$1" ]] && [[ -f "$1/bin/activate" ]]
}

function _get_venv_type() {
    local venv_dir="$1"
    local venv_type="${2:-virtualenv}"
    if [[ -f "$venv_dir/Pipfile" ]]; then
        venv_type="pipenv"
    elif [[ -f "$venv_dir/poetry.lock" ]]; then
        venv_type="poetry"
    elif [[ -f "$venv_dir/uv.lock" ]]; then
        venv_type="uv"
    elif [[ -f "$venv_dir/requirements.txt" || -f "$venv_dir/setup.py" || -f "$venv_dir/pyproject.toml" ]]; then
        venv_type="virtualenv"
    fi
    printf "%s" "$venv_type"
}

function _get_venv_name() {
    local venv_dir="$1"
    local venv_type="$2"
    local venv_name="$(basename "$venv_dir")"

    if [[ "$venv_type" == "pipenv" ]]; then
        venv_name="${venv_name%-*}"
    fi

    printf "%s" "$venv_name"
}

function _maybeworkon() {
    local venv_dir="$1"
    local venv_type="$2"
    local venv_name="$(_get_venv_name "$venv_dir" "$venv_type")"

    local DEFAULT_MESSAGE_FORMAT="Switching to ${AUTOSWITCH_BOLD}%venv_type${AUTOSWITCH_NORMAL} project: ${AUTOSWITCH_BOLD}${AUTOSWITCH_PURPLE}%venv_name${AUTOSWITCH_NORMAL} ${AUTOSWITCH_GREEN}[🐍%py_version]${AUTOSWITCH_NORMAL}"
    if [[ "$LANG" != *".UTF-8" ]]; then
        DEFAULT_MESSAGE_FORMAT="${DEFAULT_MESSAGE_FORMAT/🐍/}"
    fi

    if [[ -z "$VIRTUAL_ENV" || "$venv_dir" != "$VIRTUAL_ENV" ]]; then
        if [[ ! -d "$venv_dir" ]]; then
            printf "Unable to find ${AUTOSWITCH_PURPLE}$venv_name${AUTOSWITCH_NORMAL} virtualenv\n"
            printf "If the issue persists run ${AUTOSWITCH_PURPLE}rmvenv && mkvenv${AUTOSWITCH_NORMAL} in this directory\n"
            return
        fi

        local py_version="$(_python_version "$venv_dir/bin/python")"
        local message="${AUTOSWITCH_MESSAGE_FORMAT:-"$DEFAULT_MESSAGE_FORMAT"}"
        message="${message//\%venv_type/$venv_type}"
        message="${message//\%venv_name/$venv_name}"
        message="${message//\%py_version/$py_version}"
        _autoswitch_message "${message}\n"

        if [[ "$venv_type" == "pipenv" && "$PIPENV_VERBOSITY" != -1 ]]; then
            export PIPENV_VERBOSITY=-1
        fi

        local activate_script="$venv_dir/bin/activate"
        _validated_source "$activate_script"
    fi
}

function _check_path() {
    local check_dir="$1"

    if _is_valid_virtualenv "${check_dir}/${AUTOSWITCH_FILE}"; then
        printf "%s/%s" "$check_dir" "$AUTOSWITCH_FILE"
        return
    elif [[ -f "${check_dir}/poetry.lock" ]]; then
        printf "%s/poetry.lock" "$check_dir"
        return
    elif [[ -f "${check_dir}/Pipfile" ]]; then
        printf "%s/Pipfile" "$check_dir"
        return
    elif [[ -f "${check_dir}/uv.lock" ]]; then
        printf "%s/uv.lock" "$check_dir"
        return
    else
        if [[ "$check_dir" = "/" || "$check_dir" = "$HOME" ]]; then
            return
        fi
        _check_path "$(dirname "$check_dir")"
    fi
}

function _activate_poetry() {
    local name="$(poetry env list --full-path | sort -k 2 | tail -n 1 | cut -d' ' -f1)"
    if [[ -n "$name" ]]; then
        _maybeworkon "$name" "poetry"
        return 0
    fi
    return 1
}

function _activate_pipenv() {
    local venv_path
    if venv_path="$(PIPENV_IGNORE_VIRTUALENVS=1 pipenv --venv 2>/dev/null)"; then
        _maybeworkon "$venv_path" "pipenv"
        return 0
    fi
    return 1
}

function _activate_uv() {
    if [[ -d ".venv" ]]; then
        _maybeworkon "$PWD/.venv" "uv"
        return 0
    fi
    return 1
}

function check_venv() {
    local venv_path="$(_check_path "$PWD")"

    if [[ -n "$venv_path" ]]; then
        if [[ "$venv_path" == *"/Pipfile" ]]; then
            if type "pipenv" > /dev/null && _activate_pipenv; then
                return
            fi
        elif [[ "$venv_path" == *"/poetry.lock" ]]; then
            if type "poetry" > /dev/null && _activate_poetry; then
                return
            fi
        elif [[ "$venv_path" == *"/uv.lock" ]]; then
            local uv_venv_path="$(dirname "$venv_path")/.venv"
            _maybeworkon "$uv_venv_path" "uv"
            return
        elif _is_valid_virtualenv "$venv_path"; then
            _maybeworkon "$venv_path" "virtualenv"
            return
        fi
    fi

    local venv_type="$(_get_venv_type "$PWD" "unknown")"
    if [[ "$venv_type" != "unknown" ]]; then
        printf "Python ${AUTOSWITCH_PURPLE}$venv_type${AUTOSWITCH_NORMAL} project detected. "
        printf "Run ${AUTOSWITCH_PURPLE}mkvenv${AUTOSWITCH_NORMAL} to setup autoswitching\n"
    fi

    _default_venv
}

function _default_venv() {
    if [[ -n "$VIRTUAL_ENV" ]]; then
        local venv_type="$(_get_venv_type "$OLDPWD")"
        local venv_name="$(_get_venv_name "$VIRTUAL_ENV" "$venv_type")"
        _autoswitch_message "Deactivating: ${AUTOSWITCH_BOLD}${AUTOSWITCH_PURPLE}%s${AUTOSWITCH_NORMAL}\n" "$venv_name"
        deactivate
    fi
}

function rmvenv() {
    local venv_type="$(_get_venv_type "$PWD" "unknown")"

    if [[ "$venv_type" == "pipenv" ]]; then
        deactivate 2>/dev/null
        pipenv --rm
    elif [[ "$venv_type" == "poetry" ]]; then
        deactivate 2>/dev/null
        poetry env remove "$(poetry run which python)"
    elif [[ "$venv_type" == "uv" ]]; then
        deactivate 2>/dev/null
        rm -rf ".venv"
    else
        local venv_path="$(_virtual_env_dir "$PWD")"

        if _is_valid_virtualenv "$venv_path"; then
            if [[ -n "$VIRTUAL_ENV" && "$VIRTUAL_ENV" == "$venv_path" ]]; then
                _default_venv
            fi

            printf "Removing ${AUTOSWITCH_PURPLE}%s${AUTOSWITCH_NORMAL}...\n" "$venv_path"
            /bin/rm -rf "$venv_path"
        else
            printf "No %s virtualenv directory in the current directory!\n" "$AUTOSWITCH_FILE"
        fi
    fi
}

function _missing_error_message() {
    local command="$1"
    printf "${AUTOSWITCH_BOLD}${AUTOSWITCH_RED}"
    printf "zsh-autoswitch-virtualenv requires '%s' to install this project!\n\n" "$command"
    printf "${AUTOSWITCH_NORMAL}"
    printf "If this is already installed but you are still seeing this message, \n"
    printf "then make sure the ${AUTOSWITCH_BOLD}%s${AUTOSWITCH_NORMAL} command is in your PATH.\n" "$command"
    printf "\n"
}

function randstr() {
    ${AUTOSWITCH_DEFAULT_PYTHON:-python3} -c "from __future__ import print_function; import string, random; print(''.join(random.choice(string.ascii_lowercase) for _ in range(4)))"
}

function mkvenv() {
    local venv_type="$(_get_venv_type "$PWD" "unknown")"
    local params
    params=("${@[@]}")

    if [[ "$venv_type" == "pipenv" ]]; then
        if ! type "pipenv" > /dev/null; then
            _missing_error_message pipenv
            return
        fi
        if [[ "$AUTOSWITCH_PIPINSTALL" = "FULL" ]]; then
            pipenv install --dev $params
        else
            pipenv install --dev --editable . $params
        fi
        _activate_pipenv
        return

    elif [[ "$venv_type" == "poetry" ]]; then
        if ! type "poetry" > /dev/null; then
            _missing_error_message poetry
            return
        fi
        poetry install $params
        _activate_poetry
        return

    elif [[ "$venv_type" == "uv" ]]; then
        if ! type "uv" > /dev/null; then
            _missing_error_message uv
            return
        fi
        uv sync $params
        _activate_uv
        return

    else
        local python_bin
        local venv_path="$(_virtual_env_dir "$PWD")"

        if [[ -n "$AUTOSWITCH_DEFAULT_PYTHON" ]]; then
            python_bin="$AUTOSWITCH_DEFAULT_PYTHON"
        elif type python3 > /dev/null 2>&1; then
            python_bin="python3"
        elif type python > /dev/null 2>&1; then
            python_bin="python"
        else
            _missing_error_message python3
            return
        fi

        if [[ -e "$venv_path" ]]; then
            printf "%s already exists. If this is a mistake use the rmvenv command\n" "$venv_path"
            return
        fi

        printf "Creating ${AUTOSWITCH_PURPLE}%s${AUTOSWITCH_NORMAL} virtualenv\n" "$venv_path"

        if [[ -n "$AUTOSWITCH_DEFAULT_PYTHON" ]]; then
            printf "${AUTOSWITCH_PURPLE}"
            printf 'Using $AUTOSWITCH_DEFAULT_PYTHON='
            printf "%s" "$AUTOSWITCH_DEFAULT_PYTHON"
            printf "${AUTOSWITCH_NORMAL}\n"
        fi

        if [[ ${params[(I)--verbose]} -eq 0 ]]; then
            "$python_bin" -m venv "$venv_path"
        else
            "$python_bin" -m venv "$venv_path" > /dev/null
        fi

        _maybeworkon "$venv_path" "virtualenv"
        install_requirements
    fi
}

function install_requirements() {
    if [[ -f "$AUTOSWITCH_DEFAULT_REQUIREMENTS" ]]; then
        printf "Install default requirements? (${AUTOSWITCH_PURPLE}$AUTOSWITCH_DEFAULT_REQUIREMENTS${AUTOSWITCH_NORMAL}) [y/N]: "
        read ans

        if [[ "$ans" = "y" || "$ans" == "Y" ]]; then
            pip install -r "$AUTOSWITCH_DEFAULT_REQUIREMENTS"
        fi
    fi

    if [[ -f "$PWD/setup.py" ]]; then
        printf "Found a ${AUTOSWITCH_PURPLE}setup.py${AUTOSWITCH_NORMAL} file. Install dependencies? [y/N]: "
        read ans

        if [[ "$ans" = "y" || "$ans" = "Y" ]]; then
            if [[ "$AUTOSWITCH_PIPINSTALL" = "FULL" ]]; then
                pip install .
            else
                pip install -e .
            fi
        fi
    fi

    setopt localoptions
    setopt nullglob
    local requirements
    for requirements in **/*requirements.txt
    do
        printf "Found a ${AUTOSWITCH_PURPLE}%s${AUTOSWITCH_NORMAL} file. Install? [y/N]: " "$requirements"
        read ans

        if [[ "$ans" = "y" || "$ans" = "Y" ]]; then
            pip install -r "$requirements"
        fi
    done
}

function enable_autoswitch_virtualenv() {
    disable_autoswitch_virtualenv
    add-zsh-hook chpwd check_venv
}

function disable_autoswitch_virtualenv() {
    add-zsh-hook -D chpwd check_venv
}

function _autoswitch_startup() {
    local python_bin="${AUTOSWITCH_DEFAULT_PYTHON:-python3}"
    if ! type "${python_bin}" > /dev/null; then
        printf "WARNING: python binary '${python_bin}' not found on PATH.\n"
        printf "zsh-autoswitch-virtualenv plugin will be disabled.\n"
    else
        enable_autoswitch_virtualenv
        check_venv
    fi
    add-zsh-hook -D precmd _autoswitch_startup
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd _autoswitch_startup
