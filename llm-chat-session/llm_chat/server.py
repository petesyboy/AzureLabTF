"""
Handles server management and status checks for Ollama
"""
import subprocess
import time
import os
import platform
import requests
import webbrowser
from pathlib import Path

class OllamaServer:
    def __init__(self):
        self.system = platform.system().lower()
        
    def is_installed(self):
        """Check if Ollama is installed and accessible"""
        try:
            if self.system == "windows":
                # Check both Program Files locations and PATH
                program_files = os.environ.get('ProgramFiles')
                program_files_x86 = os.environ.get('ProgramFiles(x86)')
                potential_paths = [
                    os.path.join(program_files or '', 'Ollama', 'ollama.exe'),
                    os.path.join(program_files_x86 or '', 'Ollama', 'ollama.exe')
                ]
                
                # Check if ollama exists in any of the potential paths
                for path in potential_paths:
                    if os.path.exists(path):
                        return True
                        
                # Check if ollama is in PATH
                result = subprocess.run(['where', 'ollama'], capture_output=True, text=True)
                return result.returncode == 0
            else:
                # Unix-like systems
                result = subprocess.run(['which', 'ollama'], capture_output=True, text=True)
                return result.returncode == 0
        except Exception as e:
            print(f"Error checking Ollama installation: {e}")
            return False

    def show_installation_instructions(self):
        """Show installation instructions and guide user through the process"""
        print("\n" + "="*60)
        print("🤖 OLLAMA INSTALLATION REQUIRED")
        print("="*60)
        print("\nOllama is not installed on your system.")
        print("Ollama is required to run local LLM models.")
        
        if self.system == "windows":
            print("\n📋 Windows Installation Options:")
            print("1. Automatic installation using winget (recommended)")
            print("2. Manual installation from website")
            print("\n🚀 Option 1 - Automatic (requires Windows Package Manager):")
            print("   - Will attempt to install Ollama automatically")
            print("\n📋 Option 2 - Manual installation:")
            print("   1. Go to https://ollama.ai/download")
            print("   2. Download the Windows installer")
            print("   3. Run the installer as Administrator")
            print("   4. Restart your terminal/VS Code after installation")
        else:
            print("\n📋 Installation Steps:")
            print("1. Visit https://ollama.ai/download")
            print("2. Follow the installation instructions for your OS")
            print("3. Restart your terminal after installation")
            print("4. Run this script again")
        
        print("\n" + "="*60)
        
        while True:
            if self.system == "windows":
                choice = input("\nChoose installation method:\n1. Try automatic installation (winget)\n2. Open download page in browser\n3. Check installation again\n4. Exit\n\nEnter choice (1/2/3/4): ").strip()
            else:
                choice = input("\nWould you like to:\n1. Open download page in browser\n2. Check installation again\n3. Exit\n\nEnter choice (1/2/3): ").strip()
            
            if choice == "1":
                if self.system == "windows":
                    # Try automatic installation with winget
                    if self.try_winget_install():
                        return True
                    else:
                        print("❌ Automatic installation failed. Please try manual installation.")
                        continue
                else:
                    # Open browser for non-Windows
                    try:
                        webbrowser.open("https://ollama.ai/download")
                        print("✓ Download page opened in your browser")
                        input("\nPress Enter after you've completed the installation...")
                        
                        if self.is_installed():
                            print("✓ Ollama installation detected!")
                            return True
                        else:
                            print("❌ Ollama still not detected. Please ensure it's properly installed and restart your terminal.")
                            continue
                    except Exception as e:
                        print(f"❌ Could not open browser: {e}")
                        continue
                        
            elif choice == "2":
                if self.system == "windows":
                    # Open browser for manual installation
                    try:
                        webbrowser.open("https://ollama.ai/download")
                        print("✓ Download page opened in your browser")
                        input("\nPress Enter after you've completed the installation...")
                        
                        if self.is_installed():
                            print("✓ Ollama installation detected!")
                            return True
                        else:
                            print("❌ Ollama still not detected. Please ensure it's properly installed and restart your terminal.")
                            continue
                    except Exception as e:
                        print(f"❌ Could not open browser: {e}")
                        continue
                else:
                    # Check installation for non-Windows
                    print("🔍 Checking installation...")
                    if self.is_installed():
                        print("✓ Ollama installation detected!")
                        return True
                    else:
                        print("❌ Ollama still not detected.")
                        continue
                    
            elif choice == "3":
                if self.system == "windows":
                    print("🔍 Checking installation...")
                    if self.is_installed():
                        print("✓ Ollama installation detected!")
                        return True
                    else:
                        print("❌ Ollama still not detected.")
                        continue
                else:
                    print("Installation cancelled by user.")
                    return False
                    
            elif choice == "4" and self.system == "windows":
                print("Installation cancelled by user.")
                return False
                
            else:
                max_choice = 4 if self.system == "windows" else 3
                print(f"Invalid choice. Please enter 1, 2, 3{', or 4' if self.system == 'windows' else ''}.")
                continue

    def try_winget_install(self):
        """Try to install Ollama using Windows Package Manager (winget)"""
        print("\n🔄 Attempting automatic installation with winget...")
        
        try:
            # Check if winget is available
            result = subprocess.run(['winget', '--version'], capture_output=True, text=True, shell=True)
            if result.returncode != 0:
                print("❌ Windows Package Manager (winget) is not available.")
                print("💡 Please update Windows to the latest version or install winget manually.")
                return False
            
            print("✓ winget found, attempting to install Ollama...")
            
            # Try to install Ollama
            install_result = subprocess.run(
                ['winget', 'install', '--id', 'Ollama.Ollama', '--accept-package-agreements', '--accept-source-agreements'],
                capture_output=True,
                text=True,
                shell=True
            )
            
            if install_result.returncode == 0:
                print("✓ Ollama installation completed!")
                print("🔄 Checking installation...")
                
                # Wait a moment for installation to register
                time.sleep(3)
                
                if self.is_installed():
                    print("✅ Ollama successfully installed and detected!")
                    print("💡 You may need to restart your terminal or VS Code for full functionality.")
                    return True
                else:
                    print("⚠️ Installation completed but Ollama not detected in PATH.")
                    print("💡 Please restart your terminal or VS Code and try again.")
                    return False
            else:
                print("❌ winget installation failed:")
                print(install_result.stderr)
                return False
                
        except Exception as e:
            print(f"❌ Error during automatic installation: {e}")
            return False

    def is_running(self):
        """Check if Ollama server is running and responding"""
        try:
            # Try a simple version check with short timeout
            response = requests.get('http://localhost:11434/api/version', timeout=2)
            return response.status_code == 200
        except Exception:
            return False

    def start(self):
        """Start the Ollama server with retries and proper monitoring"""
        max_retries = 3
        retry_delay = 2

        for attempt in range(max_retries):
            try:
                print(f"Starting Ollama server (attempt {attempt + 1}/{max_retries})...")
                
                # Start the server process in background
                if self.system == "windows":
                    process = subprocess.Popen(
                        ['ollama', 'serve'],
                        shell=True,
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                        creationflags=subprocess.CREATE_NEW_PROCESS_GROUP
                    )
                else:
                    process = subprocess.Popen(
                        ['ollama', 'serve'],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                        preexec_fn=os.setsid
                    )

                print("Waiting for server to start", end="")
                
                # Check server status with timeout
                max_wait_time = 30  # 30 seconds timeout
                for i in range(max_wait_time):
                    time.sleep(1)
                    print(".", end="", flush=True)
                    
                    if self.is_running():
                        print("\n✓ Ollama server is ready!")
                        return True
                    
                    # Check if process died
                    if process.poll() is not None:
                        print(f"\nServer process exited with code: {process.returncode}")
                        break

                print(f"\nServer startup timed out after {max_wait_time} seconds")
                
                # Try to terminate the process gracefully
                try:
                    process.terminate()
                    process.wait(timeout=5)
                except:
                    try:
                        process.kill()
                    except:
                        pass

            except Exception as e:
                print(f"\nError starting server (attempt {attempt + 1}): {e}")
                if attempt < max_retries - 1:
                    print(f"Retrying in {retry_delay} seconds...")
                    time.sleep(retry_delay)

        return False
