"""
Environment setup utilities for the LLM chat extension
"""
from .venv import create_and_activate_venv
from .packages import install_packages

__all__ = ['create_and_activate_venv', 'install_packages']
