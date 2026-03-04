import venv
import os
from pathlib import Path
import sys

def create_and_activate_venv():
    print("Setting up virtual environment...")
    # Create venv in the current workspace directory
    venv_path = Path('.') / '.venv'
    
    if not venv_path.exists():
        venv.create(venv_path, with_pip=True)
        print(f"Created virtual environment at {venv_path}")
    else:
        print(f"Using existing virtual environment at {venv_path}")
    
    # Get the absolute paths
    venv_path = venv_path.resolve()
    
    # Get the Python executable path in the venv
    if os.name == 'nt':  # Windows
        python_path = venv_path / 'Scripts' / 'python.exe'
        activate_script = venv_path / 'Scripts' / 'activate.ps1'
    else:  # Unix-like
        python_path = venv_path / 'bin' / 'python'
        activate_script = venv_path / 'bin' / 'activate'
    
    # Write the paths to files for the extension to use
    with open(".venv_python_path", "w") as f:
        f.write(str(python_path))
    with open(".venv_activate_path", "w") as f:
        f.write(str(activate_script))

if __name__ == "__main__":
    try:
        create_and_activate_venv()
    except Exception as e:
        print(f"Error during venv setup: {e}")
        sys.exit(1)
