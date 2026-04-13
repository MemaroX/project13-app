from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse
from pydantic import BaseModel
from typing import List, Dict, Optional
import datetime
import sqlite3
import json

app = FastAPI(title="A.E.G.I.S. Profile & Safety Suite")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

DB_PATH = "aegis_system.db"

def init_db():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    # Profiles Table
    cursor.execute('''CREATE TABLE IF NOT EXISTS profiles 
                      (id INTEGER PRIMARY KEY AUTOINCREMENT, 
                       name TEXT UNIQUE, 
                       role TEXT, 
                       condition TEXT, 
                       accessibility_mode INTEGER,
                       inactivity_limit INTEGER)''')
    
    # Purge old legacy profiles
    cursor.execute("DELETE FROM profiles WHERE name = 'AHMED STARK'")
    
    # Default Administrator Profile
    cursor.execute("INSERT OR IGNORE INTO profiles (name, role, condition, accessibility_mode, inactivity_limit) VALUES (?, ?, ?, ?, ?)",
                   ("Administrator", "ADMIN", "NONE", 0, 3600))
    cursor.execute("INSERT OR IGNORE INTO profiles (name, role, condition, accessibility_mode, inactivity_limit) VALUES (?, ?, ?, ?, ?)",
                   ("ELDERLY PARENT", "USER", "VISUAL_IMPAIRMENT", 1, 600))
    # Additional Conditions
    cursor.execute("INSERT OR IGNORE INTO profiles (name, role, condition, accessibility_mode, inactivity_limit) VALUES (?, ?, ?, ?, ?)",
                   ("EMERGENCY_RESPONDER", "RESPONDER", "NONE", 0, 3600))
    cursor.execute("INSERT OR IGNORE INTO profiles (name, role, condition, accessibility_mode, inactivity_limit) VALUES (?, ?, ?, ?, ?)",
                   ("GUEST_USER", "GUEST", "RESTRICTED", 0, 1800))
    
    conn.commit()
    conn.close()

init_db()

class ProfileUpdate(BaseModel):
    name: str
    condition: Optional[str] = "NONE"
    accessibility_mode: bool
    inactivity_limit: int

# --- CORE LOGIC & STATE ---
device_states = {
    "light": {"status": "OFF"}, 
    "door": {"status": "LOCKED"}, 
    "fan": {"status": "OFF"}, 
    "temp": 24.5
}

class ConnectionManager:
    def __init__(self):
        self.active_connections: List[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)

    def disconnect(self, websocket: WebSocket):
        if websocket in self.active_connections:
            self.active_connections.remove(websocket)

    async def broadcast(self, message: dict):
        for connection in self.active_connections:
            try:
                await connection.send_json(message)
            except:
                # Handle stale connections
                continue

manager = ConnectionManager()

# --- API ENDPOINTS ---

@app.get("/", response_class=HTMLResponse)
async def get_index():
    try:
        with open("simulation.html", "r") as f:
            return f.read()
    except FileNotFoundError:
        return "<h1>A.E.G.I.S. Brain Online</h1><p>Simulation file not found.</p>"

@app.get("/profiles")
async def get_profiles():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT name, role, condition, accessibility_mode, inactivity_limit FROM profiles")
    profiles = [{"name": r[0], "role": r[1], "condition": r[2], "accessibility": bool(r[3]), "limit": r[4]} for r in cursor.fetchall()]
    conn.close()
    return profiles

@app.post("/profiles/update")
async def update_profile(data: ProfileUpdate):
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("UPDATE profiles SET condition = ?, accessibility_mode = ?, inactivity_limit = ? WHERE name = ?",
                   (data.condition, int(data.accessibility_mode), data.inactivity_limit, data.name))
    conn.commit()
    conn.close()
    return {"status": "Profile Updated"}

@app.get("/status")
async def get_status():
    return {"devices": device_states, "sensors": {"temp": device_states["temp"]}}

@app.post("/emergency")
async def trigger_emergency():
    # Signal the simulator to enter SOS mode
    await manager.broadcast({
        "type": "EMERGENCY",
        "devices": device_states
    })
    return {"status": "SOS_BROADCASTED"}

@app.post("/toggle/{device_id}")
async def toggle_device(device_id: str):
    if device_id in device_states:
        old = device_states[device_id]["status"]
        if device_id == "light" or device_id == "fan":
            device_states[device_id]["status"] = "ON" if old == "OFF" else "OFF"
        elif device_id == "door":
            device_states[device_id]["status"] = "UNLOCKED" if old == "LOCKED" else "LOCKED"
        
        # Broadcast update to all connected simulators
        await manager.broadcast({
            "type": "UPDATE",
            "device": device_id,
            "data": device_states[device_id]
        })
        
    return device_states

@app.websocket("/ws/house")
async def websocket_endpoint(websocket: WebSocket):
    await manager.connect(websocket)
    try:
        # Send initial state synchronization
        await websocket.send_json({"type": "INIT", "data": device_states})
        while True:
            # Keep connection alive and listen for possible client commands
            data = await websocket.receive_text()
            # Simple heartbeat or command logic could go here
    except WebSocketDisconnect:
        manager.disconnect(websocket)
    except Exception as e:
        print(f"WS Error: {e}")
        manager.disconnect(websocket)
