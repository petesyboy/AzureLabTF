"""
Handles the chat session and message management
"""
import requests
from typing import List, Dict, Generator, Optional

class ChatSession:
    def __init__(self, model_name: str):
        self.model_name = model_name
        self.base_url = "http://localhost:11434/api"
        self.context: List[Dict] = []
        
    def chat(self, message: str, system_prompt: Optional[str] = None) -> Generator[str, None, None]:
        """Send a message and get streamed response"""
        request_data = {
            "model": self.model_name,
            "messages": self.context + [{"role": "user", "content": message}]
        }
        
        if system_prompt:
            request_data["system"] = system_prompt
            
        try:
            response = requests.post(
                f"{self.base_url}/chat",
                json=request_data,
                stream=True
            )
            
            full_response = ""
            for line in response.iter_lines():
                if line:
                    chunk = line.decode()
                    try:
                        chunk_data = requests.json.loads(chunk)
                        if "error" in chunk_data:
                            yield f"Error: {chunk_data['error']}"
                            return
                        if "content" in chunk_data:
                            content = chunk_data["content"]
                            full_response += content
                            yield content
                    except requests.json.JSONDecodeError:
                        continue
                        
            # Update context with the completed exchange
            self.context.extend([
                {"role": "user", "content": message},
                {"role": "assistant", "content": full_response}
            ])
            
        except Exception as e:
            yield f"Error during chat: {str(e)}"
            
    def clear_context(self):
        """Clear the conversation history"""
        self.context = []
