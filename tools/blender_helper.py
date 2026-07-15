"""
Helper script to communicate with Blender MCP addon on port 9876.
Used by Claude Code to create and export 3D models for Tormenta Imperial.
"""
import socket
import json
import sys
import time

BLENDER_HOST = '127.0.0.1'
BLENDER_PORT = 9876
TIMEOUT = 30

def send_to_blender(code: str, timeout: int = TIMEOUT) -> dict:
    """Send Python code to Blender for execution and return the result."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(timeout)
    sock.connect((BLENDER_HOST, BLENDER_PORT))
    msg = {'type': 'execute_code', 'params': {'code': code}}
    sock.sendall((json.dumps(msg) + '\n').encode())
    data = b''
    while True:
        try:
            chunk = sock.recv(65536)
            if not chunk:
                break
            data += chunk
        except socket.timeout:
            break
    sock.close()
    if data:
        return json.loads(data.decode())
    return {'status': 'error', 'message': 'No response from Blender'}

def get_scene_info() -> dict:
    """Get current scene information."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(5)
    sock.connect((BLENDER_HOST, BLENDER_PORT))
    msg = {'type': 'get_scene_info'}
    sock.sendall((json.dumps(msg) + '\n').encode())
    data = b''
    while True:
        try:
            chunk = sock.recv(16384)
            if not chunk:
                break
            data += chunk
        except socket.timeout:
            break
    sock.close()
    if data:
        return json.loads(data.decode())
    return {}

if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == 'info':
        print(json.dumps(get_scene_info(), indent=2))
    elif len(sys.argv) > 1 and sys.argv[1] == 'exec':
        code = sys.argv[2] if len(sys.argv) > 2 else sys.stdin.read()
        result = send_to_blender(code)
        print(json.dumps(result, indent=2))
    else:
        print("Usage: python blender_helper.py [info|exec <code>]")
