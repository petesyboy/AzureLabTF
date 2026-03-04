"""
Handles model management and operations
"""
import requests
from typing import List, Dict, Optional

class ModelManager:
    def __init__(self):
        self.base_url = "http://localhost:11434/api"
        
    def list_models(self) -> List[str]:
        """Get list of installed models"""
        try:
            response = requests.get(f"{self.base_url}/tags")
            if response.status_code == 200:
                models = response.json().get('models', [])
                return [model['name'] for model in models]
            return []
        except Exception as e:
            print(f"Error listing models: {e}")
            return []
            
    def is_model_installed(self, model_name: str) -> bool:
        """Check if a specific model is installed"""
        return model_name in self.list_models()
        
    def pull_model(self, model_name: str) -> bool:
        """Download a new model"""
        try:
            print(f"Downloading model {model_name}...")
            response = requests.post(
                f"{self.base_url}/pull",
                json={"name": model_name}
            )
            return response.status_code == 200
        except Exception as e:
            print(f"Error downloading model: {e}")
            return False
            
    def get_model_info(self, model_name: str) -> Optional[Dict]:
        """Get information about a specific model"""
        try:
            response = requests.get(f"{self.base_url}/show", params={"name": model_name})
            if response.status_code == 200:
                return response.json()
            return None
        except Exception as e:
            print(f"Error getting model info: {e}")
            return None
