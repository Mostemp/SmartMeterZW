from flask import Flask, jsonify, request
from flask_cors import CORS
import sqlite3
import random
import time
import os

app = Flask(__name__)
CORS(app)

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DATABASE = os.path.join(BASE_DIR, 'smartmeter.db')

def get_db_connection():
    conn = sqlite3.connect(DATABASE)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    print("Initializing SQLite database...")
    with sqlite3.connect(DATABASE) as conn:
        conn.execute('''
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                username TEXT UNIQUE NOT NULL,
                password TEXT NOT NULL,
                meter_number TEXT UNIQUE NOT NULL,
                unit_balance REAL DEFAULT 45.72,
                last_updated REAL NOT NULL,
                tamper_triggered_time REAL DEFAULT 0,
                usage_history TEXT DEFAULT '12.4,10.1,13.8,9.5,11.2,14.0,10.8',
                address TEXT DEFAULT 'Unknown'
            )
        ''')
        # Seed default users if table is empty
        cursor = conn.cursor()
        cursor.execute("PRAGMA table_info(users)")
        columns = [row[1] for row in cursor.fetchall()]
        if 'address' not in columns:
            conn.execute("ALTER TABLE users ADD COLUMN address TEXT DEFAULT 'Unknown'")
        
        cursor.execute("SELECT COUNT(*) FROM users")
        if cursor.fetchone()[0] == 0:
            print("Pre-seeding default demo users...")
            now = time.time()
            # Demo User 1: admin (Original pin 1234)
            cursor.execute(
                "INSERT INTO users (username, password, meter_number, unit_balance, last_updated, address) VALUES (?, ?, ?, ?, ?, ?)",
                ("admin", "1234", "1234567890", 45.72, now, "25 Samora Machel Ave, Harare")
            )
            # Demo User 2: user1
            cursor.execute(
                "INSERT INTO users (username, password, meter_number, unit_balance, last_updated, address) VALUES (?, ?, ?, ?, ?, ?)",
                ("user1", "password", "9876543210", 120.50, now, "12 Main St, Harare")
            )
            conn.commit()
            print("Pre-seeding complete.")

# Call initialization on load
init_db()

def get_simulated_consumption():
    hour = time.localtime().tm_hour
    base = 0.8
    if 6 <= hour < 9:     base = 2.4
    elif 17 <= hour < 21: base = 3.1
    elif 0 <= hour < 5:   base = 0.3
    return round(base + random.uniform(-0.2, 0.3), 2)

def get_user_by_request():
    meter_number = request.headers.get('X-Meter-Number') or request.args.get('meter_number')
    conn = get_db_connection()
    cursor = conn.cursor()
    
    if meter_number:
        cursor.execute("SELECT * FROM users WHERE meter_number = ?", (meter_number,))
        user = cursor.fetchone()
        if user:
            conn.close()
            return dict(user)
            
    # Fallback to the most recently updated active user (e.g. actively used in mobile app)
    cursor.execute("SELECT * FROM users ORDER BY last_updated DESC LIMIT 1")
    user = cursor.fetchone()
    conn.close()
    if user:
        return dict(user)
    return None

def update_user_state(user):
    conn = get_db_connection()
    with conn:
        conn.execute('''
            UPDATE users 
            SET unit_balance = ?, 
                last_updated = ?, 
                tamper_triggered_time = ?, 
                usage_history = ? 
            WHERE id = ?
        ''', (
            user['unit_balance'],
            user['last_updated'],
            user['tamper_triggered_time'],
            user['usage_history'],
            user['id']
        ))
    conn.close()

def drain_balance(user):
    now = time.time()
    elapsed_hours = (now - user["last_updated"]) / 3600
    consumption_kw = get_simulated_consumption()
    units_used = consumption_kw * elapsed_hours
    user["unit_balance"] = max(0.0, round(user["unit_balance"] - units_used, 2))
    user["last_updated"] = now
    update_user_state(user)

# ─── API Endpoints ────────────────────────────────────────

@app.route('/api/status', methods=['GET'])
def get_status():
    user = get_user_by_request()
    if not user:
        return jsonify({"error": "No users found in database"}), 404
        
    if user["meter_number"].startswith("GUEST"):
        return jsonify({
            "username": user["username"],
            "meter_number": user["meter_number"],
            "unit_balance": 0.0,
            "consumption_kw": 0.0,
            "tamper_alert": False,
            "voltage": 0.0,
            "status": "GUEST"
        })
        
    drain_balance(user)
    consumption = get_simulated_consumption()

    # Check if tamper was triggered within the last 15 seconds (guarantees phone 5s polling catches it)
    tamper_time = user.get('tamper_triggered_time', 0)
    tamper = (time.time() - tamper_time) < 15

    return jsonify({
        "username": user["username"],
        "meter_number": user["meter_number"],
        "unit_balance": user["unit_balance"],
        "consumption_kw": consumption,
        "tamper_alert": tamper,
        "voltage": round(220 + random.uniform(-5, 5), 1),
        "status": "LOW_BALANCE" if user["unit_balance"] < 5 else "NORMAL"
    })

@app.route('/api/tamper', methods=['POST'])
def trigger_tamper():
    user = get_user_by_request()
    if not user:
        return jsonify({"error": "User not found"}), 404
        
    if user["meter_number"].startswith("GUEST"):
        return jsonify({"success": False, "message": "Cannot trigger tamper alert on guest account"}), 400
        
    user['tamper_triggered_time'] = time.time()
    update_user_state(user)
    print(f"TAMPER ALERT triggered for meter {user['meter_number']}!")
    return jsonify({"success": True})

@app.route('/api/history', methods=['GET'])
def get_history():
    user = get_user_by_request()
    if not user:
        return jsonify({"error": "User not found"}), 404
        
    if user["meter_number"].startswith("GUEST"):
        return jsonify({"history": []})
        
    # Parse history values
    history_str = user.get('usage_history', '12.4,10.1,13.8,9.5,11.2,14.0,10.8')
    base = [float(x) for x in history_str.split(',')]
    
    history = []
    days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    for i, day in enumerate(days):
        history.append({
            "day": day,
            "Units": round(base[i % len(base)] + random.uniform(-0.5, 0.5), 1)
        })
    return jsonify({"history": history})

@app.route('/api/topup/<int:amount>', methods=['POST'])
def topup(amount):
    user = get_user_by_request()
    if not user:
        return jsonify({"error": "User not found"}), 404
        
    units = round(amount / 0.35, 2)
    user["unit_balance"] = round(user["unit_balance"] + units, 2)
    update_user_state(user)
    return jsonify({
        "success": True,
        "units_added": units,
        "new_balance": user["unit_balance"]
    })

@app.route('/api/topup_zig/<int:amount>', methods=['POST'])
def topup_zig(amount):
    user = get_user_by_request()
    if not user:
        return jsonify({"error": "User not found"}), 404
        
    # 1 Unit = 0.35 USD. At 1 USD = 25 ZiG, 1 Unit = 8.75 ZiG
    units = round(amount / 8.75, 2)
    user["unit_balance"] = round(user["unit_balance"] + units, 2)
    update_user_state(user)
    return jsonify({
        "success": True,
        "units_added": units,
        "new_balance": user["unit_balance"]
    })

@app.route('/api/consume/<int:amount>', methods=['POST'])
def consume_units(amount):
    user = get_user_by_request()
    if not user:
        return jsonify({"error": "User not found"}), 404
    
    user["unit_balance"] = max(0.0, round(user["unit_balance"] - amount, 2))
    update_user_state(user)
    return jsonify({
        "success": True,
        "units_consumed": amount,
        "new_balance": user["unit_balance"]
    })

@app.route('/api/reset_units', methods=['POST'])
def reset_units():
    user = get_user_by_request()
    if not user:
        return jsonify({"error": "User not found"}), 404
        
    user["unit_balance"] = 50.00
    update_user_state(user)
    return jsonify({
        "success": True,
        "new_balance": user["unit_balance"]
    })

@app.route('/api/login', methods=['POST'])
def login():
    data = request.get_json() or {}
    username = data.get('username', '').strip()
    password = data.get('password', '').strip()
    
    if not username or not password:
        return jsonify({"success": False, "message": "Missing username or password"}), 400
        
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute(
        "SELECT * FROM users WHERE username = ? AND password = ?",
        (username, password)
    )
    user = cursor.fetchone()
    conn.close()
    
    if user:
        user_dict = dict(user)
        return jsonify({
            "success": True,
            "message": "Login successful",
            "user": {
                "username": user_dict["username"],
                "meter_number": user_dict["meter_number"],
                "unit_balance": user_dict["unit_balance"]
            }
        })
    else:
        return jsonify({"success": False, "message": "Invalid username or password"}), 401

@app.route('/api/register', methods=['POST'])
def register():
    data = request.get_json() or {}
    username = data.get('username', '').strip()
    password = data.get('password', '').strip()
    meter_number = data.get('meter_number', '').strip()
    address = data.get('address', 'Unknown').strip()
    
    if not username or not password:
        return jsonify({"success": False, "message": "Missing username or password"}), 400
        
    is_guest = False
    if not meter_number:
        is_guest = True
        meter_number = f"GUEST_{random.randint(1000000000, 9999999999)}"
        
    conn = get_db_connection()
    cursor = conn.cursor()
    try:
        initial_balance = 0.00 if is_guest else 50.00
        cursor.execute(
            "INSERT INTO users (username, password, meter_number, unit_balance, last_updated, address) VALUES (?, ?, ?, ?, ?, ?)",
            (username, password, meter_number, initial_balance, time.time(), address)
        )
        conn.commit()
        conn.close()
        reg_type = "Non-Meter Guest" if is_guest else "Meter Owner"
        return jsonify({
            "success": True, 
            "message": f"Registration successful as {reg_type}! Please log in."
        })
    except sqlite3.IntegrityError:
        conn.close()
        return jsonify({"success": False, "message": "Username or Meter Number already registered!"}), 400

@app.route('/api/meter_info/<meter_number>', methods=['GET'])
def get_meter_info(meter_number):
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM users WHERE meter_number = ?", (meter_number,))
    user = cursor.fetchone()
    conn.close()
    if user:
        user_dict = dict(user)
        return jsonify({
            "success": True,
            "username": user_dict["username"],
            "meter_number": user_dict["meter_number"],
            "address": user_dict.get("address", "Unknown")
        })
    else:
        return jsonify({"success": False, "message": "Meter not found"}), 404

@app.after_request
def add_cors_headers(response):
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS, PUT, DELETE'
    response.headers['Access-Control-Allow-Headers'] = 'Content-Type, X-Meter-Number, Authorization'
    response.headers['Access-Control-Allow-Private-Network'] = 'true'
    return response

@app.route('/')
@app.route('/meter')
def serve_meter():
    meter_path = os.path.join(os.path.dirname(__file__), 'meter.html')
    if os.path.exists(meter_path):
        with open(meter_path, 'r', encoding='utf-8') as f:
            return f.read(), 200, {'Content-Type': 'text/html; charset=utf-8'}
    return "meter.html not found", 404

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)