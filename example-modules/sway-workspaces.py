#!/bin/python
import os
import sys
import json
import select
import selectors
import subprocess

f = os.popen("swaymsg -t subscribe -m \"['workspace']\"", 'r')
selector = selectors.DefaultSelector()
selector.register(sys.stdin, selectors.EVENT_READ)
selector.register(f, selectors.EVENT_READ)
last_ws = []
def show_workspaces():
    global last_ws
    sw = os.popen("swaymsg -t get_workspaces", 'r')
    obj = json.loads(sw.read())
    sw.close()
    items = []
    last_ws = obj
    for ws in obj:
        if ws['visible']:
            items.append({ 'text': '' + str(ws['num']) + '', 'fg': '000000ff', 'bg': 'ffffffff'})
        else:
            items.append({ 'text': '' + str(ws['num']) + '', 'bg': '00000022', 'fg': 'ffffffff'})
    print(json.dumps({'items': items}), flush=True)
def process_event(event):
    global last_ws
    event_obj = None
    try:
        event_obj = json.loads(event) 
    except:
        return
    try:
        if event_obj['type'] == 'Click':
            click = event_obj['event']
            if click['button'] == 'Left':
                workspace = last_ws[click['item']]['num']
                pop = os.popen('swaymsg workspace ' + str(workspace), 'r')
                pop.close()
        elif event_obj['type'] == 'Scroll':
            scroll_dir = event_obj['event']['dir']
            if scroll_dir == -1:
                pop = os.popen('swaymsg workspace next', 'r')
                pop.close()
            elif scroll_dir == 1:
                pop = os.popen('swaymsg workspace prev', 'r')
                pop.close()
                
    except Exception as e:
        print(e, file=sys.stderr)
        return

show_workspaces()
while True:
    selected  = selector.select()
    for key, _ in selected:
        if key.fd == sys.stdin.fileno(): process_event(sys.stdin.readline())
        elif key.fd == f.fileno():
            f.readline()
            show_workspaces()
