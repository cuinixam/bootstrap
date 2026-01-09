#!/bin/bash
set -e

# Default configuration
PYTHON_VERSION="3.11"
BREW_INSTALLER_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
BOOTSTRAP_JSON="bootstrap.json"

# Function to read config from bootstrap.json using Python (if available) or grep
load_config() {
    if [ -f "$BOOTSTRAP_JSON" ]; then
        # Check if python3 is available for JSON parsing
        if command -v python3 &>/dev/null; then
             PV=$(python3 -c "import json; print(json.load(open('$BOOTSTRAP_JSON')).get('python_version', ''))" 2>/dev/null)
             if [ -n "$PV" ]; then PYTHON_VERSION="$PV"; fi

             BI=$(python3 -c "import json; print(json.load(open('$BOOTSTRAP_JSON')).get('brew_installer', ''))" 2>/dev/null)
             if [ -n "$BI" ]; then BREW_INSTALLER_URL="$BI"; fi
        else
            # Fallback to grep/sed (simple extraction)
            # Pattern: "python_version": "3.11"
            PV=$(grep -o '"python_version"[[:space:]]*:[[:space:]]*"[^"]*"' "$BOOTSTRAP_JSON" | sed -E 's/.*: *"([^"]*)".*/\1/')
            if [ -n "$PV" ]; then PYTHON_VERSION="$PV"; fi
            
            BI=$(grep -o '"brew_installer"[[:space:]]*:[[:space:]]*"[^"]*"' "$BOOTSTRAP_JSON" | sed -E 's/.*: *"([^"]*)".*/\1/')
            if [ -n "$BI" ]; then BREW_INSTALLER_URL="$BI"; fi
        fi
    fi
}

install_homebrew() {
    if ! command -v brew &>/dev/null; then
        echo "Homebrew not found. Installing..."
        echo "Installer URL: $BREW_INSTALLER_URL"
        
        # Install Homebrew
        /bin/bash -c "$(curl -fsSL "$BREW_INSTALLER_URL")"
        
        # Configure shell environment for Homebrew
        if [[ "$OSTYPE" == "darwin"* ]]; then
             if [ -f "/opt/homebrew/bin/brew" ]; then
                 eval "$(/opt/homebrew/bin/brew shellenv)"
             elif [ -f "/usr/local/bin/brew" ]; then
                 eval "$(/usr/local/bin/brew shellenv)"
             fi
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
             if [ -d "/home/linuxbrew/.linuxbrew" ]; then
                 eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
             fi
        fi
        
        # Verify installation
        if ! command -v brew &>/dev/null; then
             echo "Error: Homebrew installation failed or not found in PATH."
             exit 1
        fi
    else
        echo "Homebrew is already installed."
    fi
}

install_brew_dependencies() {
    if [ -f "Brewfile" ]; then
        echo "Found Brewfile. Installing dependencies..."
        brew bundle --no-lock
    fi
}

install_python() {
    # Extract major.minor for brew formula (e.g. 3.11 from 3.11.9)
    MAJOR_MINOR=$(echo "$PYTHON_VERSION" | cut -d. -f1,2)
    FORMULA="python@$MAJOR_MINOR"
    
    echo "Checking for $FORMULA..."
    
    # Check if installed
    if ! brew list --versions "$FORMULA" >/dev/null; then
        echo "Installing $FORMULA..."
        brew install "$FORMULA"
    else
        echo "$FORMULA is already installed."
    fi
    
    # Locate the python executable
    # 'brew --prefix' gives the installation path
    PREFIX=$(brew --prefix "$FORMULA")
    PYTHON_EXEC="$PREFIX/bin/python$MAJOR_MINOR"
    
    if [ ! -x "$PYTHON_EXEC" ]; then
        echo "Error: Python executable not found at $PYTHON_EXEC"
        exit 1
    fi
    
    echo "Python executable: $PYTHON_EXEC"
}

run_bootstrap_py() {
    if [ -f "pyproject.toml" ] || [ -f "Pipfile" ]; then
        echo "Setting up Python environment..."
        BOOTSTRAP_PY="./bootstrap.py"
        if [ -f "$BOOTSTRAP_PY" ]; then
            "$PYTHON_EXEC" "$BOOTSTRAP_PY"
        else
            echo "Error: bootstrap.py not found in current directory!"
            exit 1
        fi
    else
        echo "No Python configuration found (pyproject.toml or Pipfile). Skipping Python environment setup."
    fi
}

main() {
    load_config
    echo "Bootstrap Configuration:"
    echo "  Python Version: $PYTHON_VERSION"
    echo "  Brew Installer: $BREW_INSTALLER_URL"
    
    install_homebrew
    install_brew_dependencies
    install_python
    run_bootstrap_py
}

main
