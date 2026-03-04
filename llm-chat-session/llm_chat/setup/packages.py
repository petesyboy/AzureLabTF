import subprocess
import sys

def install_packages():
    print("Installing required packages...")
    packages = ['requests', 'ollama']
    for package in packages:
        print(f"Installing {package}...")
        subprocess.check_call([sys.executable, "-m", "pip", "install", package])
    print("All packages installed successfully!")

if __name__ == "__main__":
    try:
        install_packages()
    except Exception as e:
        print(f"Error during package installation: {e}")
        sys.exit(1)
