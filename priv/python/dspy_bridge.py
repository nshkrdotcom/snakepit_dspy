#!/usr/bin/env python3

# Debug logging disabled to prevent massive log files
import sys
import os

# DEBUG LOGGING DISABLED - define no-op function to prevent 172GB log files
def debug_log(message):
    """No-op debug logging to prevent massive log file spam"""
    pass

"""
DSPy Bridge for Snakepit Integration

This module provides a communication bridge between Snakepit and Python DSPy
processes using a JSON-based protocol with length-prefixed messages.

Features:
- Dynamic DSPy signature creation from Elixir definitions
- Program lifecycle management (create, execute, cleanup)
- Health monitoring and statistics
- Error handling and logging
- Memory management and cleanup

Protocol:
- 4-byte big-endian length header
- JSON message payload
- Request/response correlation with IDs

Usage:
    python3 dspy_bridge.py --mode pool-worker

The script reads from stdin and writes to stdout using the packet protocol.
"""

import sys
import json
import struct
import traceback
import time
import gc
import threading
import os
import argparse
import re
import signal
import atexit
from typing import Dict, Any, Optional, List, Union

# Handle DSPy import with fallback
try:
    import dspy
    DSPY_AVAILABLE = True
    print("DSPy imported successfully", file=sys.stderr)
except ImportError as e:
    DSPY_AVAILABLE = False
    print(f"DSPy not available: {e}", file=sys.stderr)
    # Create mock dspy module to prevent errors
    class MockDSPy:
        class Signature:
            pass
        class Predict:
            def __init__(self, signature):
                self.signature = signature
            def forward(self, **kwargs):
                return {"status": "error", "error": "DSPy not available"}
    dspy = MockDSPy()

# Handle Gemini API import with fallback
try:
    import google.generativeai as genai
    GEMINI_AVAILABLE = True
    print("Gemini API imported successfully", file=sys.stderr)
except ImportError:
    GEMINI_AVAILABLE = False
    print("Gemini API not available", file=sys.stderr)

# Global variables for language model configuration
current_lm = None
lm_type = None
lm_config = {}

def configure_gemini_api():
    """Configure Gemini API if available and API key is set."""
    global GEMINI_AVAILABLE
    
    if not GEMINI_AVAILABLE:
        return False
        
    api_key = os.getenv('GEMINI_API_KEY')
    if not api_key:
        print("GEMINI_API_KEY not found in environment", file=sys.stderr)
        return False
        
    try:
        genai.configure(api_key=api_key)
        print("Gemini API configured successfully", file=sys.stderr)
        return True
    except Exception as e:
        print(f"Failed to configure Gemini API: {e}", file=sys.stderr)
        return False

# Configure Gemini on import
GEMINI_CONFIGURED = configure_gemini_api()

class DSPySignatureBuilder:
    """Builds DSPy signatures from Elixir field definitions."""
    
    def __init__(self):
        self.signatures = {}
    
    def build_signature(self, signature_def: Dict[str, Any]) -> tuple:
        """Build a DSPy signature from field definitions.
        
        Returns:
            Tuple of (signature_class, field_mapping)
        """
        if not DSPY_AVAILABLE:
            raise RuntimeError("DSPy is not available")
            
        inputs = signature_def.get('inputs', [])
        outputs = signature_def.get('outputs', [])
        
        # Build field mapping for input/output translation
        field_mapping = {}
        
        # Build the signature string using DSPy's expected format
        # DSPy signatures use a simple format: "input1, input2 -> output1, output2"
        
        input_names = [field['name'] for field in inputs]
        output_names = [field['name'] for field in outputs]
        
        signature_string = f"{', '.join(input_names)} -> {', '.join(output_names)}"
        
        print(f"DEBUG: Building signature string: {signature_string}", file=sys.stderr)
        
        # Build field mapping
        for field in inputs + outputs:
            name = field['name']
            field_mapping[name] = name
        
        # Create the signature class using proper DSPy syntax
        import dspy
        
        # Create signature using the string format that DSPy expects
        signature_class = dspy.Signature(signature_string)
        
        print(f"DEBUG: Created signature class: {signature_class}", file=sys.stderr)
        print(f"DEBUG: Signature class type: {type(signature_class)}", file=sys.stderr)
        
        return signature_class, field_mapping

class DSPyProgramManager:
    """Manages DSPy programs and their execution."""
    
    def __init__(self):
        self.programs = {}
        self.signature_builder = DSPySignatureBuilder()
        
    def create_program(self, program_id: str, signature_def: Dict[str, Any], 
                      instructions: str = None, program_type: str = "predict") -> Dict[str, Any]:
        """Create a new DSPy program."""
        try:
            if not DSPY_AVAILABLE:
                return {
                    "status": "error",
                    "error": "DSPy is not available"
                }
            
            # Build the signature
            signature_class, field_mapping = self.signature_builder.build_signature(signature_def)
            
            # Create the program based on type
            if program_type == "predict":
                program = dspy.Predict(signature_class)
            else:
                return {
                    "status": "error", 
                    "error": f"Unsupported program type: {program_type}"
                }
            
            # Store the program
            self.programs[program_id] = {
                "program": program,
                "signature_class": signature_class,
                "field_mapping": field_mapping,
                "signature_def": signature_def,
                "instructions": instructions,
                "program_type": program_type,
                "created_at": time.time(),
                "execution_count": 0
            }
            
            return {
                "status": "ok",
                "program_id": program_id,
                "signature_def": signature_def,
                "program_type": program_type
            }
            
        except Exception as e:
            return {
                "status": "error",
                "error": f"Failed to create program: {str(e)}"
            }
    
    def execute_program(self, program_id: str, inputs: Dict[str, Any]) -> Dict[str, Any]:
        """Execute a DSPy program with given inputs."""
        try:
            if program_id not in self.programs:
                return {
                    "status": "error",
                    "error": f"Program '{program_id}' not found"
                }
            
            program_info = self.programs[program_id]
            program = program_info["program"]
            
            # Execute the program
            try:
                result = program(**inputs)
                
                # Update execution count
                program_info["execution_count"] += 1
                
                # Extract outputs based on signature
                outputs = {}
                signature_def = program_info["signature_def"]
                
                for output_field in signature_def.get("outputs", []):
                    field_name = output_field["name"]
                    if hasattr(result, field_name):
                        outputs[field_name] = getattr(result, field_name)
                
                return {
                    "status": "ok",
                    "program_id": program_id,
                    "inputs": inputs,
                    "outputs": outputs,
                    "execution_count": program_info["execution_count"]
                }
                
            except Exception as e:
                return {
                    "status": "error",
                    "error": f"Program execution failed: {str(e)}"
                }
            
        except Exception as e:
            return {
                "status": "error",
                "error": f"Failed to execute program: {str(e)}"
            }
    
    def get_program(self, program_id: str) -> Dict[str, Any]:
        """Get information about a program."""
        if program_id not in self.programs:
            return {
                "status": "error",
                "error": f"Program '{program_id}' not found"
            }
        
        program_info = self.programs[program_id]
        return {
            "status": "ok",
            "program_id": program_id,
            "signature_def": program_info["signature_def"],
            "instructions": program_info["instructions"],
            "program_type": program_info["program_type"],
            "created_at": program_info["created_at"],
            "execution_count": program_info["execution_count"]
        }
    
    def list_programs(self) -> Dict[str, Any]:
        """List all programs."""
        program_list = []
        for program_id, program_info in self.programs.items():
            program_list.append({
                "program_id": program_id,
                "program_type": program_info["program_type"],
                "created_at": program_info["created_at"],
                "execution_count": program_info["execution_count"]
            })
        
        return {
            "status": "ok",
            "programs": program_list,
            "count": len(program_list)
        }
    
    def delete_program(self, program_id: str) -> Dict[str, Any]:
        """Delete a program."""
        if program_id not in self.programs:
            return {
                "status": "error",
                "error": f"Program '{program_id}' not found"
            }
        
        del self.programs[program_id]
        return {
            "status": "ok",
            "program_id": program_id,
            "message": "Program deleted successfully"
        }
    
    def clear_session(self) -> Dict[str, Any]:
        """Clear all programs."""
        count = len(self.programs)
        self.programs.clear()
        return {
            "status": "ok",
            "message": f"Cleared {count} programs",
            "count": count
        }

class DSPyBridge:
    """Main bridge class handling communication with Snakepit."""
    
    def __init__(self):
        self.start_time = time.time()
        self.request_count = 0
        self.program_manager = DSPyProgramManager()
        
    def handle_ping(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """Handle ping command."""
        self.request_count += 1
        
        return {
            "status": "ok",
            "bridge_type": "dspy",
            "dspy_available": DSPY_AVAILABLE,
            "gemini_available": GEMINI_CONFIGURED,
            "uptime": time.time() - self.start_time,
            "mode": "pool-worker",
            "timestamp": time.time(),
            "python_version": sys.version,
            "worker_id": args.get("worker_id", "unknown")
        }
    
    def handle_configure_lm(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """Handle configure_lm command to set up language model."""
        global current_lm, lm_type, lm_config
        
        try:
            if not DSPY_AVAILABLE:
                return {"status": "error", "error": "DSPy is not available"}
            
            model = args.get("model")
            api_key = args.get("api_key") 
            provider = args.get("provider", "google")
            
            if not model:
                return {"status": "error", "error": "Model name is required"}
            if not api_key:
                return {"status": "error", "error": "API key is required"}
            
            # Configure DSPy language model
            if provider == "google" and model.startswith("gemini"):
                # Use LiteLLM for Gemini via DSPy
                import dspy
                
                # Debug: Print configuration details
                print(f"DEBUG: Configuring DSPy with model: gemini/{model}", file=sys.stderr)
                print(f"DEBUG: API key length: {len(api_key) if api_key else 0}", file=sys.stderr)
                
                try:
                    # Create LM instance
                    lm = dspy.LM(f"gemini/{model}", api_key=api_key)
                    
                    # Test the LM with a simple call
                    print(f"DEBUG: Testing LM with simple call", file=sys.stderr)
                    test_response = lm("Hello, this is a test.")
                    print(f"DEBUG: Test response: {test_response}", file=sys.stderr)
                    
                    # Configure DSPy to use this LM
                    dspy.configure(lm=lm)
                    
                    current_lm = lm
                    lm_type = "gemini"
                    lm_config = {"model": model, "api_key": api_key[:8] + "...", "provider": provider}
                    
                    print(f"DEBUG: DSPy configured successfully", file=sys.stderr)
                    
                    return {
                        "status": "ok", 
                        "message": f"Configured {model} language model",
                        "model": model,
                        "provider": provider
                    }
                    
                except Exception as e:
                    print(f"DEBUG: LM configuration failed: {str(e)}", file=sys.stderr)
                    import traceback
                    print(f"DEBUG: Traceback: {traceback.format_exc()}", file=sys.stderr)
                    return {"status": "error", "error": f"LM configuration failed: {str(e)}"}
            else:
                return {"status": "error", "error": f"Unsupported provider/model: {provider}/{model}"}
                
        except Exception as e:
            return {"status": "error", "error": f"LM configuration failed: {str(e)}"}
    
    def handle_create_program(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """Handle create_program command."""
        try:
            program_id = args.get("id")
            signature = args.get("signature")
            instructions = args.get("instructions", "")
            program_type = args.get("program_type", "predict")
            
            if not program_id:
                return {"status": "error", "error": "Program ID is required"}
            
            if not signature:
                return {"status": "error", "error": "Signature is required"}
            
            return self.program_manager.create_program(
                program_id, signature, instructions, program_type
            )
            
        except Exception as e:
            return {"status": "error", "error": f"Create program failed: {str(e)}"}
    
    def handle_execute_program(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """Handle execute_program command."""
        try:
            program_id = args.get("program_id")
            inputs = args.get("inputs", {})
            
            if not program_id:
                return {"status": "error", "error": "Program ID is required"}
            
            # Check if program_data is provided (cross-worker execution)
            program_data = args.get('program_data')
            if program_data is not None:
                # Use program_data when provided (cross-worker execution)
                # Recreate the program object from the stored data
                program_info = self._recreate_program_from_data(program_data)
                
                # Execute with recreated program
                return self._execute_with_program_info(program_info, inputs)
            else:
                # Fall back to local storage when no program_data is provided
                return self.program_manager.execute_program(program_id, inputs)
            
        except Exception as e:
            import traceback
            error_details = f"Execute program failed: {str(e)}\nTraceback: {traceback.format_exc()}"
            return {"status": "error", "error": error_details}
    
    def _recreate_program_from_data(self, program_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Recreates a program object from stored data for stateless workers.
        
        Args:
            program_data: The program data retrieved from SessionStore
            
        Returns:
            Dictionary containing recreated program info
        """
        if not DSPY_AVAILABLE:
            raise RuntimeError("DSPy not available - cannot recreate programs")
        
        try:
            signature_def = program_data.get('signature_def', {})
            
            # Recreate the signature and program
            signature_class, field_mapping = self.program_manager.signature_builder.build_signature(signature_def)
            
            if not current_lm:
                raise RuntimeError("No LM is loaded.")
            
            # Create the program
            import dspy
            program = dspy.Predict(signature_class)
            
            return {
                'program': program,
                'signature_class': signature_class,
                'field_mapping': field_mapping,
                'signature_def': signature_def,
                'program_id': program_data.get('program_id'),
                'created_at': program_data.get('created_at'),
                'execution_count': program_data.get('execution_count', 0),
                'last_executed': program_data.get('last_executed')
            }
            
        except Exception as e:
            import traceback
            error_details = f"Failed to recreate program: {str(e)}\nTraceback: {traceback.format_exc()}"
            raise RuntimeError(error_details)
    
    def _execute_with_program_info(self, program_info: Dict[str, Any], inputs: Dict[str, Any]) -> Dict[str, Any]:
        """Execute a program using recreated program info."""
        try:
            program = program_info['program']
            field_mapping = program_info['field_mapping']
            
            # Convert inputs using field mapping
            dspy_inputs = {}
            for key, value in inputs.items():
                dspy_field = field_mapping.get(key, key)
                dspy_inputs[dspy_field] = value
            
            # Execute the program
            debug_log(f"Executing program with inputs: {dspy_inputs}")
            debug_log(f"Current LM status: {current_lm is not None}")
            if current_lm:
                debug_log(f"Current LM type: {type(current_lm)}")
            
            result = program(**dspy_inputs)
            debug_log(f"Program execution result type: {type(result)}")
            debug_log(f"Result attributes: {[attr for attr in dir(result) if not attr.startswith('_')]}")
            debug_log(f"Result __dict__: {result.__dict__ if hasattr(result, '__dict__') else 'No __dict__'}")
            
            # Check what's actually available on the result object
            print(f"DEBUG: Result type: {type(result)}", file=sys.stderr)
            print(f"DEBUG: Result dir: {[attr for attr in dir(result) if not attr.startswith('_')]}", file=sys.stderr)
            if hasattr(result, '__dict__'):
                print(f"DEBUG: Result dict: {result.__dict__}", file=sys.stderr)
            
            # Extract only the expected output fields from the signature
            signature_def = program_info.get('signature_def', {})
            expected_outputs = signature_def.get('outputs', [])
            
            outputs = {}
            
            # First try to extract using field mapping
            field_mapping = program_info.get('field_mapping', {})
            if field_mapping:
                for original_name, sanitized_name in field_mapping.items():
                    # Only extract output fields
                    if any(field['name'] == original_name for field in expected_outputs):
                        if hasattr(result, sanitized_name):
                            outputs[original_name] = str(getattr(result, sanitized_name))
                        else:
                            outputs[original_name] = f"Field '{sanitized_name}' not found in prediction."
            
            # If no field mapping or outputs still empty, try direct field names
            if not outputs:
                for output_field in expected_outputs:
                    field_name = output_field['name']
                    
                    if hasattr(result, field_name):
                        outputs[field_name] = str(getattr(result, field_name))
                    else:
                        outputs[field_name] = f"Field '{field_name}' not found in prediction."
            
            # If still no outputs, try DSPy-specific extraction methods
            if not outputs or all("[" in str(v) and "]" in str(v) for v in outputs.values()):
                print("DEBUG: Using DSPy-specific extraction", file=sys.stderr)
                
                # Try to access the result using DSPy's internal structure
                if hasattr(result, '_store') and result._store:
                    print(f"DEBUG: Found _store: {result._store}", file=sys.stderr)
                    for expected_field in [field['name'] for field in expected_outputs]:
                        if expected_field in result._store:
                            outputs[expected_field] = str(result._store[expected_field])
                
                # Try accessing completions directly
                if hasattr(result, '_completions') and result._completions:
                    print(f"DEBUG: Found _completions: {result._completions}", file=sys.stderr)
                    # For simple cases, try to extract the first completion
                    try:
                        completion_values = list(result._completions.values())
                        if completion_values and completion_values[0]:
                            first_completion = completion_values[0][0]
                            # For Q&A, assume first output field gets the completion
                            if expected_outputs:
                                outputs[expected_outputs[0]['name']] = str(first_completion)
                    except Exception as e:
                        print(f"DEBUG: Error extracting completions: {e}", file=sys.stderr)
                
                # Final fallback: extract from __dict__
                if not outputs and hasattr(result, '__dict__'):
                    result_dict = result.__dict__
                    for k, v in result_dict.items():
                        if not k.startswith('_') and k != 'completions':
                            outputs[k] = str(v)
            
            # If we still have no real outputs, provide diagnostic info
            if not outputs or all("[" in str(v) and "]" in str(v) for v in outputs.values()):
                print("DEBUG: No outputs extracted, providing diagnostic info", file=sys.stderr)
                for expected_field in [field['name'] for field in expected_outputs]:
                    outputs[expected_field] = f"[DEBUG: Empty completions, LM may not be responding. Store: {result._store if hasattr(result, '_store') else 'N/A'}]"
            
            return {
                "status": "ok",
                "outputs": outputs,
                "program_id": program_info.get('program_id'),
                "execution_time": time.time()
            }
            
        except Exception as e:
            import traceback
            error_details = f"Program execution failed: {str(e)}\nTraceback: {traceback.format_exc()}"
            return {"status": "error", "error": error_details}
    
    def process_command(self, command: str, args: Dict[str, Any]) -> Dict[str, Any]:
        """Process a command and return the result."""
        handlers = {
            "ping": self.handle_ping,
            "configure_lm": self.handle_configure_lm,
            "create_program": self.handle_create_program,
            "execute_program": self.handle_execute_program,
            "get_program": lambda args: self.program_manager.get_program(args.get("program_id")),
            "list_programs": lambda args: self.program_manager.list_programs(),
            "delete_program": lambda args: self.program_manager.delete_program(args.get("program_id")),
            "clear_session": lambda args: self.program_manager.clear_session()
        }
        
        handler = handlers.get(command)
        if handler:
            try:
                return handler(args)
            except Exception as e:
                return {
                    "status": "error",
                    "error": f"Command '{command}' failed: {str(e)}"
                }
        else:
            return {
                "status": "error",
                "error": f"Unknown command: {command}",
                "supported_commands": list(handlers.keys())
            }

class ProtocolHandler:
    """Handles the wire protocol for communication with Snakepit."""
    
    def __init__(self):
        self.bridge = DSPyBridge()
    
    def read_message(self) -> Optional[Dict[str, Any]]:
        """Read a message from stdin using the 4-byte length protocol."""
        try:
            # Read 4-byte length header
            length_data = sys.stdin.buffer.read(4)
            if len(length_data) != 4:
                return None
            
            # Unpack length (big-endian)
            length = struct.unpack('>I', length_data)[0]
            
            # Read JSON payload
            json_data = sys.stdin.buffer.read(length)
            if len(json_data) != length:
                return None
            
            # Parse JSON
            return json.loads(json_data.decode('utf-8'))
        except Exception as e:
            print(f"Error reading message: {e}", file=sys.stderr)
            return None
    
    def write_message(self, message: Dict[str, Any]) -> bool:
        """Write a message to stdout using the 4-byte length protocol."""
        try:
            # Encode JSON
            json_data = json.dumps(message, separators=(',', ':')).encode('utf-8')
            
            # Write length header (big-endian)
            length = struct.pack('>I', len(json_data))
            sys.stdout.buffer.write(length)
            
            # Write JSON payload
            sys.stdout.buffer.write(json_data)
            sys.stdout.buffer.flush()
            
            return True
        except Exception as e:
            print(f"Error writing message: {e}", file=sys.stderr)
            return False
    
    def run(self):
        """Main message loop."""
        print("DSPy Bridge started in pool-worker mode", file=sys.stderr)
        print(f"DSPy available: {DSPY_AVAILABLE}", file=sys.stderr)
        
        while True:
            # Read request
            request = self.read_message()
            if request is None:
                break
            
            # Extract request details
            request_id = request.get("id")
            command = request.get("command")
            args = request.get("args", {})
            
            try:
                # Process command
                result = self.bridge.process_command(command, args)
                
                # Send success response
                response = {
                    "id": request_id,
                    "success": True,
                    "result": result,
                    "timestamp": time.time()
                }
            except Exception as e:
                # Send error response
                response = {
                    "id": request_id,
                    "success": False,
                    "error": str(e),
                    "timestamp": time.time()
                }
            
            # Write response
            if not self.write_message(response):
                break

def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(description="DSPy Bridge for Snakepit")
    parser.add_argument("--mode", default="pool-worker", help="Bridge mode")
    args = parser.parse_args()
    
    if args.mode == "pool-worker":
        handler = ProtocolHandler()
        try:
            handler.run()
        except KeyboardInterrupt:
            print("DSPy Bridge shutting down", file=sys.stderr)
        except Exception as e:
            print(f"DSPy Bridge error: {e}", file=sys.stderr)
            sys.exit(1)
    else:
        print(f"Unknown mode: {args.mode}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()