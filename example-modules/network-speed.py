#!/bin/python
import time

INTERFACE = "eth0" 

def get_bytes(interface):
    with open('/proc/net/dev', 'r') as f:
        for line in f:
            if interface in line:
                parts = line.split()
                rx = int(parts[1])  # Receive bytes
                tx = int(parts[9])  # Transmit bytes
                return rx, tx
    raise ValueError(f"Interface {interface} not found")

rx1, tx1 = get_bytes(INTERFACE)
while True:
    time.sleep(1)
    rx2, tx2 = get_bytes(INTERFACE)
    rx_rate = rx2 - rx1
    tx_rate = tx2 - tx1
    rx1 = rx2
    tx1 = tx2
    print(f"{rx_rate / 1024 / 1024:.2f} MiB/s", flush=True)
