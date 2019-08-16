#!/usr/bin/env python

import dbus
import os

def connect(address):
    return dbus.connection.Connection(address)

conn = connect("unix:path=/run/pulse/dbus-socket")
core = conn.get_object(object_path="/org/pulseaudio/stream_restore1")

entries = core.Get("org.PulseAudio.Ext.StreamRestore1","Entries", dbus_interface="org.freedesktop.DBus.Properties")

add_entry=True
for entrypath in entries:
  entry = conn.get_object(object_path=entrypath) 
  name=entry.Get("org.PulseAudio.Ext.StreamRestore1.RestoreEntry","Name")
  device=entry.Get("org.PulseAudio.Ext.StreamRestore1.RestoreEntry","Device")
  if name=="sink-input-by-media-role:music" and device=="fakeairport":
    add_entry=False 
  else:
    entry.Remove()
    print("Entry with name: {} and device: {} removed".format(name,device))

if add_entry:
  outentry=core.AddEntry("sink-input-by-media-role:music","fakeairport",dbus.Array(signature="(uu)"),False,False)
