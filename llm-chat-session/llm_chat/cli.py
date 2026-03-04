import sys
import time
import subprocess
import requests
from llm_chat import OllamaServer, ModelManager, ChatSession

# Initialize components
server = OllamaServer()
model_manager = ModelManager()
chat_session = None

def setup_environment():
    """Set up the chat environment"""
    print("🔍 Checking Ollama installation...")
    
    # Check if Ollama is installed
    if not server.is_installed():
        print("❌ Ollama is not installed.")
        if not server.show_installation_instructions():
            print("Installation cancelled. Exiting...")
            sys.exit(1)
    else:
        print("✓ Ollama is installed")
        
    # Start the server if not running
    print("🔍 Checking if Ollama server is running...")
    if not server.is_running():
        print("❌ Ollama server is not running. Starting...")
        if not server.start():
            print("❌ Failed to start Ollama server")
            print("💡 Try running 'ollama serve' manually in another terminal")
            sys.exit(1)
    else:
        print("✓ Ollama server is already running")
            
def setup_chat_session(model_name="codellama"):
    """Initialize or switch chat session"""
    global chat_session
    
    # Check if model is available
    if not model_manager.is_model_installed(model_name):
        print(f"Model {model_name} not found. Downloading...")
        if not model_manager.pull_model(model_name):
            print(f"Failed to download model {model_name}")
            return False
            
    # Create new chat session
    chat_session = ChatSession(model_name)
    return True

def get_available_models():
    """Get list of all available Ollama models"""
    try:
        response = requests.get('http://localhost:11434/api/tags', timeout=5)
        if response.status_code == 200:
            models = response.json().get('models', [])
            return [model.get('name') for model in models if model.get('name')]
        return []
    except Exception:
        return []

def select_model():
    """Let user select a model to use"""
    while True:
        print("\nAvailable options:")
        print("1. Use an existing model")
        print("2. Pull a new model")
        
        choice = input("\nEnter your choice (1/2): ").strip()
        
        if choice == "1":
            available_models = get_available_models()
            if not available_models:
                print("No models found. Please pull a model first.")
                continue
                
            print("\nAvailable models:")
            for idx, model in enumerate(available_models, 1):
                print(f"{idx}. {model}")
            
            try:
                model_idx = int(input("\nSelect model number: ")) - 1
                if 0 <= model_idx < len(available_models):
                    return available_models[model_idx]
                print("Invalid selection. Please try again.")
            except ValueError:
                print("Invalid input. Please enter a number.")
                
        elif choice == "2":
            model_name = input("\nEnter model name to pull (e.g., tinyllama, llama2, codellama): ").strip().lower()
            if model_name and install_model(model_name):
                return model_name
        else:
            print("Invalid choice. Please try again.")

def check_model_installed(model_name):
    """Check if specific model is installed"""
    try:
        # Try API check first
        available_models = get_available_models()
        if model_name in available_models:
            print(f"✓ {model_name} model found")
            return True

        # Fallback to CLI check
        result = subprocess.run(
            ['ollama', 'list'],
            capture_output=True,
            text=True,
            shell=True
        )
        return model_name in result.stdout.lower()
    except Exception as e:
        print(f"Error checking model installation: {e}")
        return False

def install_model(model_name):
    """Install specified model with progress monitoring"""
    print(f"\nDownloading {model_name} model (this may take several minutes)...")
    max_retries = 2
    
    for attempt in range(max_retries):
        try:
            process = subprocess.Popen(
                ['ollama', 'pull', model_name],
                shell=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )

            while True:
                output = process.stdout.readline()
                if output == '' and process.poll() is not None:
                    break
                if output:
                    print(output.strip())

            if process.returncode == 0:
                print(f"✓ {model_name} model installed successfully!")
                return True
            else:
                stderr = process.stderr.read()
                print(f"Error output: {stderr}")
                
        except Exception as e:
            print(f"Error on attempt {attempt + 1}: {e}")
            if attempt < max_retries - 1:
                print("Retrying download...")
                time.sleep(2)
    
    return False

def setup():
    """Setup chat environment and initialize session"""
    print("\n=== Local LLM Chat Interface ===")
    
    # Setup environment
    try:
        setup_environment()
    except Exception as e:
        print(f"\n❌ Environment setup failed: {e}")
        return False
        
    # Initialize chat with default model
    try:
        if not setup_chat_session("codellama"):
            print("\n❌ Failed to initialize chat session")
            return False
    except Exception as e:
        print(f"\n❌ Chat session initialization failed: {e}")
        return False
        
    return True

def chat_with_llm(model_name):
    """Interactive chat session with selected model"""
    # Double-check if Ollama server is running before starting chat
    if not server.is_running():
        print("❌ Ollama server is not running. Attempting to start...")
        if not server.start():
            print("❌ Failed to start Ollama server.")
            print("💡 Try running 'ollama serve' manually in another terminal")
            print("💡 Or check if Ollama is properly installed")
            return
        print("✓ Ollama server started successfully")
    else:
        print("✓ Ollama server is running")
    
    print(f"\n=== {model_name.upper()} Chat Session ===")
    print("Type 'exit' to quit, 'help' for commands")
    
    try:
        import ollama
    except ImportError:
        print("Installing ollama package...")
        subprocess.check_call([sys.executable, "-m", "pip", "install", "ollama"])
        import ollama
    
    while True:
        try:
            user_input = input("\nYou: ").strip()
            if not user_input:
                continue
                
            if user_input.lower() == 'exit':
                print("👋 Goodbye!")
                break
                
            if user_input.lower() == 'help':
                print("\nAvailable commands:")
                print("- exit: End the chat session")
                print("- help: Show this help message")
                print(f"- switch: Switch to a different model (current: {model_name})")
                continue
                
            if user_input.lower() == 'switch':
                new_model = select_model()
                if new_model:
                    model_name = new_model
                    print(f"\nSwitched to {model_name.upper()}")
                continue
            
            response = ollama.chat(model=model_name, messages=[
                {
                    'role': 'user',
                    'content': user_input
                }
            ])
            
            print(f"\n{model_name.capitalize()}: {response['message']['content']}")
            
        except KeyboardInterrupt:
            print("\n\n👋 Chat session interrupted. Goodbye!")
            break
        except Exception as e:
            print(f"\n❌ Error during chat: {str(e)}")
            print("Please check if Ollama server is still running.")
            break

def main():
    """Main entry point for the CLI"""
    print("🔧 Starting Local LLM Chat...")
    
    # Check installation and start server through setup_environment
    print("🔍 Verifying Ollama installation and server status...")
    if not server.is_installed():
        print("❌ Ollama is not installed.")
        if not server.show_installation_instructions():
            print("Installation cancelled. Exiting...")
            sys.exit(1)
    
    # Ensure Ollama server is running before model selection
    if not server.is_running():
        print("❌ Ollama server is not running. Attempting to start...")
        if not server.start():
            print("❌ Failed to start Ollama server.")
            print("💡 Try running 'ollama serve' manually in another terminal")
            print("💡 Or restart your computer if you just installed Ollama")
            sys.exit(1)
        print("✓ Ollama server started successfully")
    else:
        print("✓ Ollama server is running")
    
    print("🎯 Starting model selection...")
    model_name = select_model()
    print(f"📝 Selected model: {model_name}")
    
    if model_name:
        print("🚀 Starting chat session...")
        chat_with_llm(model_name)
    else:
        print("\n❌ Failed to select or download a model.")
        sys.exit(1)

if __name__ == "__main__":
    if setup():
        main()
    else:
        print("\n❌ Failed to set up the chat environment.")
        print("Please fix the above issues and try again.")
        sys.exit(1)
