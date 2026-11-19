from flask import Flask, jsonify, request
from flask_cors import CORS
import sqlite3
import random
import time
import os
import tariffs

app = Flask(__name__)
CORS(app)

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DATABASE = os.path.join(BASE_DIR, 'smartmeter.db')

def get_db_connection():
    conn = sqlite3.connect(DATABASE)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    print("Initializing SQLite database with official ZETDC multi-tariff categories...")
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
                tariff_category TEXT DEFAULT 'DOMESTIC_STEPPED',
                monthly_purchased_units REAL DEFAULT 0.0,
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
                tariff_category TEXT NOT NULL,
                payment_method TEXT NOT NULL,
                phone TEXT,
                timestamp REAL NOT NULL,
                status TEXT DEFAULT 'SUCCESS'
            )
        ''')

        cursor.execute("PRAGMA table_info(users)")
        columns = [row[1] for row in cursor.fetchall()]
        if 'tariff_category' not in columns:
            cursor.execute("ALTER TABLE users ADD COLUMN tariff_category TEXT DEFAULT 'DOMESTIC_STEPPED'")
        if 'monthly_purchased_units' not in columns:
            cursor.execute("ALTER TABLE users ADD COLUMN monthly_purchased_units REAL DEFAULT 0.0")

        cursor.execute("SELECT COUNT(*) FROM users")
        if cursor.fetchone()[0] == 0:
            now = time.time()
            # Demo User 1: Domestic Stepped (Home consumer)
            cursor.execute(
                "INSERT INTO users (username, password, meter_number, unit_balance, last_updated, tariff_category, monthly_purchased_units, address, phone) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                ("admin", "1234", "1234567890", 45.72, now, "DOMESTIC_STEPPED", 0.0, "25 Samora Machel Ave, Harare", "0771234567")
            )
            # Demo User 2: Commercial Prepayment (Shop / Supermarket)
            cursor.execute(
                "INSERT INTO users (username, password, meter_number, unit_balance, last_updated, tariff_category, monthly_purchased_units, address, phone) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                ("simba_retail", "password", "9876543210", 120.50, now, "COMMERCIAL_PREPAID", 150.0, "Shop 4, Eastgate Mall, Harare", "0719876543")
            )
            # Demo User 3: Industrial & Mining
            cursor.execute(
                "INSERT INTO users (username, password, meter_number, unit_balance, last_updated, tariff_category, monthly_purchased_units, address, phone) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                ("graniteside_works", "password", "1122334455", 350.00, now, "INDUSTRIAL_MINING", 400.0, "Factory 12, Graniteside Industrial, Harare", "0785551234")
            )
            # Demo User 4: Agricultural (Farm / Irrigation)
            cursor.execute(
                "INSERT INTO users (username, password, meter_number, unit_balance, last_updated, tariff_category, monthly_purchased_units, address, phone) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                ("mazowe_citrus", "password", "5566778899", 210.00, now, "AGRICULTURAL", 100.0, "Plot 7, Mazowe Valley Farm", "0774321987")
            )
            conn.commit()

init_db()

def get_user_by_meter(meter_number):
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM users WHERE meter_number = ?", (meter_number,))
    user = cursor.fetchone()
    conn.close()
    return dict(user) if user else None

def get_user_by_request():
    meter_number = request.headers.get('X-Meter-Number') or request.args.get('meter_number')
    if meter_number:
        user = get_user_by_meter(meter_number)
        if user:
            return user
            
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM users ORDER BY last_updated DESC LIMIT 1")
    user = cursor.fetchone()
    conn.close()
    return dict(user) if user else None

@app.route('/api/tariffs', methods=['GET'])
def get_tariffs_catalog():
    """Returns official ZETDC tariff schedules and definitions."""
    return jsonify({
        "success": True,
        "effective_date": "1 December 2023 (Current Official ZERA Gazetted)",
        "categories": tariffs.TARIFF_CATEGORIES,
        "zig_exchange_rate": tariffs.ZIG_EXCHANGE_RATE
    })

@app.route('/api/calculate_quote', methods=['POST'])
def calculate_quote():
    data = request.get_json() or {}
    category_key = data.get('tariff_category', 'DOMESTIC_STEPPED')
    amount = float(data.get('amount', 10))
    currency = data.get('currency', 'USD')
    monthly_units = float(data.get('monthly_units', 0))

    quote = tariffs.calculate_energy_yield(category_key, amount, currency, monthly_units)
    return jsonify({"success": True, "quote": quote})

@app.route('/api/status', methods=['GET'])
def get_status():
    user = get_user_by_request()
    if not user:
        return jsonify({"error": "No users found in database"}), 404

    balance = round(float(user["unit_balance"]), 2)
    cat_key = user.get("tariff_category", "DOMESTIC_STEPPED")
    cat_info = tariffs.TARIFF_CATEGORIES.get(cat_key, tariffs.TARIFF_CATEGORIES["DOMESTIC_STEPPED"])

    return jsonify({
        "username": user["username"],
        "meter_number": user["meter_number"],
        "unit_balance": balance,
        "tariff_category": cat_key,
        "tariff_name": cat_info["name"],
        "monthly_purchased_units": user.get("monthly_purchased_units", 0.0),
        "address": user.get("address", "Harare, Zimbabwe"),
        "status": "LOW_BALANCE" if balance < 10 else "NORMAL"
    })

@app.route('/api/meter_info/<meter_number>', methods=['GET'])
def get_meter_info(meter_number):
    meter_number = meter_number.strip()
    user = get_user_by_meter(meter_number)
    if user:
        cat_key = user.get("tariff_category", "DOMESTIC_STEPPED")
        cat_info = tariffs.TARIFF_CATEGORIES.get(cat_key, tariffs.TARIFF_CATEGORIES["DOMESTIC_STEPPED"])
        return jsonify({
            "success": True,
            "username": user["username"],
            "meter_number": user["meter_number"],
            "address": user.get("address", "Unknown"),
            "unit_balance": round(float(user["unit_balance"]), 2),
            "tariff_category": cat_key,
            "tariff_name": cat_info["name"],
            "monthly_purchased_units": user.get("monthly_purchased_units", 0.0)
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

    cat_key = user.get('tariff_category', 'DOMESTIC_STEPPED')
    monthly_units = float(user.get('monthly_purchased_units', 0.0))

    # Calculate exact yield based on official ZETDC tariff & tax schedules
    calc = tariffs.calculate_energy_yield(cat_key, amount, currency, monthly_units)
    units_to_add = calc["units_credited"]
    new_balance = round(float(user['unit_balance']) + units_to_add, 2)
    new_monthly_cumulative = round(monthly_units + units_to_add, 2)

    ref_id = f"ZESA-{int(time.time())}-{random.randint(1000, 9999)}"

    conn = get_db_connection()
    with conn:
        conn.execute('''
            UPDATE users 
            SET unit_balance = ?, monthly_purchased_units = ?, last_updated = ? 
            WHERE meter_number = ?
        ''', (new_balance, new_monthly_cumulative, time.time(), meter_number))
        conn.execute('''
            INSERT INTO transactions (reference_id, meter_number, amount, currency, units_credited, tariff_category, payment_method, phone, timestamp, status)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (ref_id, meter_number, amount, currency, units_to_add, cat_key, payment_method, phone, time.time(), 'SUCCESS'))
    conn.close()

    return jsonify({
        "success": True,
        "message": f"Successfully credited {units_to_add} Units to meter {meter_number}",
        "reference_id": ref_id,
        "meter_number": meter_number,
        "units_credited": units_to_add,
        "amount": amount,
        "currency": currency,
        "new_balance": new_balance,
        "tariff_breakdown": calc,
        "timestamp": time.time()
    })

@app.route('/api/transactions/<meter_number>', methods=['GET'])
def get_transactions(meter_number):
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute('''
        SELECT reference_id, meter_number, amount, currency, units_credited, tariff_category, payment_method, phone, timestamp, status
        FROM transactions
        WHERE meter_number = ?
        ORDER BY timestamp DESC
        LIMIT 50
    ''', (meter_number,))
    rows = cursor.fetchall()
    conn.close()
    return jsonify({"success": True, "meter_number": meter_number, "transactions": [dict(r) for r in rows]})

@app.after_request
def add_cors_headers(response):
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS, PUT, DELETE'
    response.headers['Access-Control-Allow-Headers'] = 'Content-Type, X-Meter-Number, Authorization'
    return response

@app.route('/')
def serve_index():
    portal_path = os.path.join(os.path.dirname(__file__), 'index.html')
    if os.path.exists(portal_path):
        with open(portal_path, 'r', encoding='utf-8') as f:
            return f.read(), 200, {'Content-Type': 'text/html; charset=utf-8'}
    return "Web portal not found", 404

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
