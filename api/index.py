from flask import Flask, jsonify, request
from flask_cors import CORS
import sqlite3
import random
import time
import os

app = Flask(__name__)
CORS(app)

# On Vercel serverless environment, the only writable directory is /tmp
if os.environ.get('VERCEL'):
    DATABASE = '/tmp/smartmeter.db'
else:
    BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    DATABASE = os.path.join(BASE_DIR, 'smartmeter.db')

def get_db_connection():
    conn = sqlite3.connect(DATABASE)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    try:
        with sqlite3.connect(DATABASE) as conn:
            cursor = conn.cursor()
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS users (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    username TEXT UNIQUE NOT NULL,
                    password TEXT NOT NULL,
                    meter_number TEXT UNIQUE NOT NULL,
                    unit_balance REAL DEFAULT 45.72,
                    last_updated REAL NOT NULL,
                    tariff_plan TEXT DEFAULT 'Domestic Prepaid (R1)',
                    address TEXT DEFAULT 'Harare, Zimbabwe',
                    phone TEXT DEFAULT '0771234567'
                )
            ''')
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS transactions (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    reference_id TEXT UNIQUE NOT NULL,
                    meter_number TEXT NOT NULL,
                    amount REAL NOT NULL,
                    currency TEXT NOT NULL,
                    units_credited REAL NOT NULL,
                    payment_method TEXT NOT NULL,
                    phone TEXT,
                    timestamp REAL NOT NULL,
                    status TEXT DEFAULT 'SUCCESS'
                )
            ''')
            cursor.execute("SELECT COUNT(*) FROM users")
            if cursor.fetchone()[0] == 0:
                now = time.time()
                cursor.execute(
                    "INSERT INTO users (username, password, meter_number, unit_balance, last_updated, address, phone) VALUES (?, ?, ?, ?, ?, ?, ?)",
                    ("admin", "1234", "1234567890", 45.72, now, "25 Samora Machel Ave, Harare", "0771234567")
                )
                cursor.execute(
                    "INSERT INTO users (username, password, meter_number, unit_balance, last_updated, address, phone) VALUES (?, ?, ?, ?, ?, ?, ?)",
                    ("user1", "password", "9876543210", 120.50, now, "12 Main St, Bulawayo", "0719876543")
                )
                conn.commit()
    except Exception as e:
        print("DB init error:", e)

init_db()

USD_RATE_PER_UNIT = 0.35
ZIG_RATE_PER_UNIT = 8.75

def get_user_by_meter(meter_number):
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM users WHERE meter_number = ?", (meter_number,))
        user = cursor.fetchone()
        conn.close()
        return dict(user) if user else None
    except Exception:
        return None

def get_user_by_request():
    meter_number = request.headers.get('X-Meter-Number') or request.args.get('meter_number')
    if meter_number:
        user = get_user_by_meter(meter_number)
        if user:
            return user
            
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM users ORDER BY last_updated DESC LIMIT 1")
        user = cursor.fetchone()
        conn.close()
        return dict(user) if user else None
    except Exception:
        return None

@app.route('/api/status', methods=['GET'])
def get_status():
    user = get_user_by_request()
    if not user:
        return jsonify({
            "username": "admin",
            "meter_number": "1234567890",
            "unit_balance": 45.72,
            "tariff_plan": "Domestic Prepaid (R1)",
            "address": "25 Samora Machel Ave, Harare",
            "status": "NORMAL"
        })

    balance = round(float(user["unit_balance"]), 2)
    return jsonify({
        "username": user["username"],
        "meter_number": user["meter_number"],
        "unit_balance": balance,
        "tariff_plan": user.get("tariff_plan", "Domestic Prepaid (R1)"),
        "address": user.get("address", "Harare, Zimbabwe"),
        "status": "LOW_BALANCE" if balance < 10 else "NORMAL"
    })

@app.route('/api/meter_info/<meter_number>', methods=['GET'])
def get_meter_info(meter_number):
    meter_number = meter_number.strip()
    user = get_user_by_meter(meter_number)
    if user:
        return jsonify({
            "success": True,
            "username": user["username"],
            "meter_number": user["meter_number"],
            "address": user.get("address", "Unknown"),
            "unit_balance": round(float(user["unit_balance"]), 2),
            "tariff_plan": user.get("tariff_plan", "Domestic Prepaid (R1)")
        })
    else:
        return jsonify({"success": False, "message": "Meter number not found"}), 404

@app.route('/api/purchase', methods=['POST'])
def direct_purchase():
    data = request.get_json() or {}
    meter_number = data.get('meter_number', '').strip()
    amount = float(data.get('amount', 0))
    currency = data.get('currency', 'USD').upper().strip()
    payment_method = data.get('payment_method', 'EcoCash').strip()
    phone = data.get('phone', '').strip()

    if not meter_number or amount <= 0:
        return jsonify({"success": False, "message": "Invalid meter number or amount"}), 400

    user = get_user_by_meter(meter_number)
    if not user:
        return jsonify({"success": False, "message": f"Meter number {meter_number} does not exist"}), 404

    rate = USD_RATE_PER_UNIT if currency == 'USD' else ZIG_RATE_PER_UNIT
    units_to_add = round(amount / rate, 2)
    new_balance = round(float(user['unit_balance']) + units_to_add, 2)
    ref_id = f"ZESA-{int(time.time())}-{random.randint(1000, 9999)}"

    conn = get_db_connection()
    with conn:
        conn.execute('''
            UPDATE users SET unit_balance = ?, last_updated = ? WHERE meter_number = ?
        ''', (new_balance, time.time(), meter_number))
        conn.execute('''
            INSERT INTO transactions (reference_id, meter_number, amount, currency, units_credited, payment_method, phone, timestamp, status)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (ref_id, meter_number, amount, currency, units_to_add, payment_method, phone, time.time(), 'SUCCESS'))
    conn.close()

    return jsonify({
        "success": True,
        "message": f"Successfully credited {units_to_add} Units directly to meter {meter_number}",
        "reference_id": ref_id,
        "meter_number": meter_number,
        "units_credited": units_to_add,
        "amount": amount,
        "currency": currency,
        "new_balance": new_balance,
        "timestamp": time.time()
    })

@app.route('/api/transactions/<meter_number>', methods=['GET'])
def get_transactions(meter_number):
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute('''
            SELECT reference_id, meter_number, amount, currency, units_credited, payment_method, phone, timestamp, status
            FROM transactions
            WHERE meter_number = ?
            ORDER BY timestamp DESC
            LIMIT 50
        ''', (meter_number,))
        rows = cursor.fetchall()
        conn.close()
        return jsonify({"success": True, "meter_number": meter_number, "transactions": [dict(r) for r in rows]})
    except Exception:
        return jsonify({"success": True, "meter_number": meter_number, "transactions": []})

@app.route('/api/history', methods=['GET'])
def get_history():
    history = [
        {"day": "Mon", "Units": 9.4},
        {"day": "Tue", "Units": 11.2},
        {"day": "Wed", "Units": 8.7},
        {"day": "Thu", "Units": 12.0},
        {"day": "Fri", "Units": 10.5},
        {"day": "Sat", "Units": 13.8},
        {"day": "Sun", "Units": 11.0}
    ]
    return jsonify({"history": history})

@app.after_request
def add_cors_headers(response):
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS, PUT, DELETE'
    response.headers['Access-Control-Allow-Headers'] = 'Content-Type, X-Meter-Number, Authorization'
    return response

# Vercel entry point
