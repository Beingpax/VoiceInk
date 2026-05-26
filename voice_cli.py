#!/usr/bin/env python3
"""
VoiceInk CLI Client for AI Agents
A zero-dependency CLI tool allowing local agents to programmatically prompt the user
and receive dictated answers via VoiceInk's built-in MCP server.

Usage:
  python3 voice_cli.py dictate --question "What is the status of your deployment?"
"""

import sys
import json
import argparse
import urllib.request
import urllib.parse

# Default server port is 51089
DEFAULT_PORT = 51089

def run_dictation(question, port):
    url = f"http://localhost:{port}/sse"
    print(f"[*] Connecting to VoiceInk SSE server at {url}...", file=sys.stderr)
    
    req = urllib.request.Request(url, headers={"User-Agent": "VoiceInkCLI/1.0"})
    try:
        response = urllib.request.urlopen(req)
    except Exception as e:
        print(f"[-] Error connecting to VoiceInk server on port {port}. Is VoiceInk running? Error: {e}", file=sys.stderr)
        sys.exit(1)
        
    current_event = None
    
    while True:
        line_bytes = response.readline()
        if not line_bytes:
            break
        line = line_bytes.decode('utf-8').strip()
        
        if line.startswith("event:"):
            current_event = line[6:].strip()
        elif line.startswith("data:"):
            data_val = line[5:].strip()
            
            if current_event == "endpoint":
                parsed_url = urllib.parse.urlparse("http://localhost" + data_val)
                query_params = urllib.parse.parse_qs(parsed_url.query)
                session_id = query_params.get("session_id", [None])[0]
                
                if session_id:
                    trigger_dictation(session_id, question, port)
            elif current_event == "message":
                try:
                    payload = json.loads(data_val)
                    if "result" in payload:
                        result = payload["result"]
                        if "content" in result:
                            for item in result["content"]:
                                if item.get("type") == "text":
                                    # Output only the raw text to stdout
                                    print(item.get("text"))
                                    return
                    elif "error" in payload:
                        print(f"[-] Error from server: {payload['error']}", file=sys.stderr)
                        sys.exit(1)
                except Exception as e:
                    print(f"[-] Error parsing event message: {e}", file=sys.stderr)
                    
        elif not line:
            current_event = None

def trigger_dictation(session_id, question, port):
    post_url = f"http://localhost:{port}/message?session_id={session_id}"
    payload = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "tools/call",
        "params": {
            "name": "ask_user_dictation",
            "arguments": {
                "questions": [question]
            }
        }
    }
    
    req_data = json.dumps(payload).encode('utf-8')
    req = urllib.request.Request(
        post_url,
        data=req_data,
        headers={
            "Content-Type": "application/json",
            "User-Agent": "VoiceInkCLI/1.0"
        },
        method="POST"
    )
    
    try:
        urllib.request.urlopen(req)
        print(f"[*] Prompt sent to VoiceInk: '{question}'", file=sys.stderr)
        print("[*] Recording... Please speak your answer.", file=sys.stderr)
    except Exception as e:
        print(f"[-] Error sending dictation trigger: {e}", file=sys.stderr)
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description="VoiceInk CLI Client for AI Agents")
    subparsers = parser.add_subparsers(dest="command", required=True)
    
    dictate_parser = subparsers.add_parser("dictate", help="Trigger user dictation and get transcription")
    dictate_parser.add_argument("--question", "-q", required=True, help="Question/prompt to show/read to the user")
    dictate_parser.add_argument("--port", "-p", type=int, default=DEFAULT_PORT, help=f"VoiceInk server port (default: {DEFAULT_PORT})")
    
    args = parser.parse_args()
    
    if args.command == "dictate":
        run_dictation(args.question, args.port)

if __name__ == "__main__":
    main()
