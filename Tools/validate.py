#!/usr/bin/python3
"""Checks every message the plugin would send against the DynamicLake app running on this Mac.

DynamicLake validates a message before it checks who sent it, so a message that passes comes back
"Client is not trusted" and one that doesn't comes back with the validation error. Nothing is shown.
Usage: make validate   (or: make -s demo | Tools/validate.py)
"""
import json, os, socket, struct, sys

path = "/tmp/dynamiclake-json-%d.sock" % os.getuid()
messages = [json.loads(line) for line in sys.stdin if line.startswith("{")]
sock = socket.socket(socket.AF_UNIX)
try:
    sock.connect(path)
except OSError:
    sys.exit("DynamicLake isn't running (no socket at %s)" % path)
sock.settimeout(3)

def read_frame():
    head = b""
    while len(head) < 4:
        head += sock.recv(4 - len(head))
    (length,) = struct.unpack(">I", head)
    body = b""
    while len(body) < length:
        body += sock.recv(length - len(body))
    return json.loads(body)

failed = 0
for message in messages:
    data = json.dumps(message).encode()
    sock.sendall(struct.pack(">I", len(data)) + data)
    reply = read_frame()
    error = reply.get("error", "")
    if error and error != "Client is not trusted.":
        failed += 1
        print("REJECTED %s: %s" % (message.get("type"), error))
print("%d of %d messages valid" % (len(messages) - failed, len(messages)))
sys.exit(1 if failed else 0)
