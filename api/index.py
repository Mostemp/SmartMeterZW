from flask import Flask, jsonify, request
from flask_cors import CORS
import sqlite3
import random
import time
import os
import math

app = Flask(__name__)
CORS(app)

if os.environ.get('VERCEL'):
    DATABASE = '/tmp/smartmeter.db'
else:
    BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    DATABASE = os.path.join(BASE_DIR, 'smartmeter.db')

ZIG_EXCHANGE_RATE = 25.0

TARIFF_CATEGORIES = {
    "DOMESTIC_STEPPED": {
        "name": "Domestic Prepayment Stepped (E1.2.2)",
        "type": "stepped",
        "description": "Standard residential stepped tariff (Lifeline block + Standard + Premium)",
        "tiers": [
            {"limit": 50, "rate": 0.05, "desc": "1st 50 kWh (Lifeline)"},
            {"limit": 250, "rate": 0.19, "desc": "51 to 300 kWh (Standard)"},
            {"limit": math.inf, "rate": 0.25, "desc": "> 300 kWh (Balance/Excess)"}
        ],
        "rea_levy": 0.06,
        "vat": 0.00
    },
    "DOMESTIC_STANDARD": {
        "name": "Domestic Flat Prepayment (E1.2.1)",
        "type": "flat",
        "rate": 0.19,
        "description": "Flat residential tariff without stepping",
        "rea_levy": 0.06,
        "vat": 0.00
    },
    "COMMERCIAL_PREPAID": {
        "name": "Commercial & Institutional Low Voltage (E4.3)",
        "type": "flat",
        "rate": 0.20,
        "description": "Retail shops, schools, clinics, commercial premises",
        "rea_levy": 0.06,
        "vat": 0.15
    },
    "INDUSTRIAL_MINING": {
        "name": "Mining & Industrial Prepayment (E3.1 / E4.1)",
        "type": "flat",
        "rate": 0.20,
        "description": "Industrial workshops, manufacturing, mining low voltage",
        "rea_levy": 0.06,
        "vat": 0.15
    },
    "AGRICULTURAL": {
        "name": "Agricultural & Farming Prepayment (E5.1)",
        "type": "flat",
        "rate": 0.20,
        "description": "Farms, irrigation pumps, agribusiness facilities",
        "rea_levy": 0.06,
        "vat": 0.15
    },
    "PUBLIC_LIGHTING": {
        "name": "Public Lighting Prepayment (E2.1)",
        "type": "flat",
        "rate": 0.19,
        "description": "Municipal streets, communal lighting",
        "rea_levy": 0.06,
        "vat": 0.00
    }
}

def calculate_energy_yield(category_key, amount_paid, currency="USD", monthly_purchased_so_far=0.0):
    cat = TARIFF_CATEGORIES.get(category_key, TARIFF_CATEGORIES["DOMESTIC_STEPPED"])
    usd_amount = amount_paid if currency.upper() == "USD" else (amount_paid / ZIG_EXCHANGE_RATE)
    tax_multiplier = 1.0 + cat["rea_levy"] + cat["vat"]
    net_energy_funds = usd_amount / tax_multiplier
    tax_amount = usd_amount - net_energy_funds
    
    units_credited = 0.0
    tier_breakdown = []
    
    if cat["type"] == "stepped":
        remaining_funds = net_energy_funds
        current_cumulative = monthly_purchased_so_far
        t1_capacity = max(0.0, 50.0 - current_cumulative)
        if t1_capacity > 0 and remaining_funds > 0:
            t1_rate = 0.05
            t1_cost = t1_capacity * t1_rate
            if remaining_funds <= t1_cost:
                u = remaining_funds / t1_rate
                units_credited += u
                tier_breakdown.append({"tier": "1st 50 kWh (Lifeline)", "units": round(u, 2), "rate": t1_rate})
                remaining_funds = 0.0
            else:
                units_credited += t1_capacity
                remaining_funds -= t1_cost
                tier_breakdown.append({"tier": "1st 50 kWh (Lifeline)", "units": round(t1_capacity, 2), "rate": t1_rate})
                current_cumulative += t1_capacity
                
        t2_capacity = max(0.0, 300.0 - max(50.0, current_cumulative))
        if t2_capacity > 0 and remaining_funds > 0:
            t2_rate = 0.19
            t2_cost = t2_capacity * t2_rate
            if remaining_funds <= t2_cost:
                u = remaining_funds / t2_rate
                units_credited += u
                tier_breakdown.append({"tier": "51 to 300 kWh (Standard)", "units": round(u, 2), "rate": t2_rate})
                remaining_funds = 0.0
            else:
                units_credited += t2_capacity
                remaining_funds -= t2_cost
                tier_breakdown.append({"tier": "51 to 300 kWh (Standard)", "units": round(t2_capacity, 2), "rate": t2_rate})
                current_cumulative += t2_capacity
                
        if remaining_funds > 0:
            t3_rate = 0.25
            u = remaining_funds / t3_rate
            units_credited += u
            tier_breakdown.append({"tier": "> 300 kWh (Balance)", "units": round(u, 2), "rate": t3_rate})
            
    else:
        flat_rate = cat["rate"]
        units_credited = net_energy_funds / flat_rate
        tier_breakdown.append({"tier": "Flat Rate", "units": round(units_credited, 2), "rate": flat_rate})
        
    return {
        "category_key": category_key,
        "category_name": cat["name"],
        "currency": currency.upper(),
        "gross_amount": round(amount_paid, 2),
        "usd_equivalent": round(usd_amount, 2),
        "net_energy_funds": round(net_energy_funds, 2),
        "tax_amount": round(tax_amount, 2),
        "rea_levy_percent": int(cat["rea_levy"] * 100),
        "vat_percent": int(cat["vat"] * 100),
        "units_credited": round(units_credited, 2),
        "tier_breakdown": tier_breakdown
    }

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
            cursor.execute("SELECT COUNT(*) FROM users")
            if cursor.fetchone()[0] == 0:
                now = time.time()
                cursor.execute(
                    "INSERT INTO users (username, password, meter_number, unit_balance, last_updated, tariff_category, monthly_purchased_units, address, phone) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    ("admin", "1234", "1234567890", 45.72, now, "DOMESTIC_STEPPED", 0.0, "25 Samora Machel Ave, Harare", "0771234567")
                )
                cursor.execute(
                    "INSERT INTO users (username, password, meter_number, unit_balance, last_updated, tariff_category, monthly_purchased_units, address, phone) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    ("simba_retail", "password", "9876543210", 120.50, now, "COMMERCIAL_PREPAID", 150.0, "Shop 4, Eastgate Mall, Harare", "0719876543")
                )
                cursor.execute(
                    "INSERT INTO users (username, password, meter_number, unit_balance, last_updated, tariff_category, monthly_purchased_units, address, phone) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    ("graniteside_works", "password", "1122334455", 350.00, now, "INDUSTRIAL_MINING", 400.0, "Factory 12, Graniteside Industrial, Harare", "0785551234")
                )
                cursor.execute(
                    "INSERT INTO users (username, password, meter_number, unit_balance, last_updated, tariff_category, monthly_purchased_units, address, phone) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    ("mazowe_citrus", "password", "5566778899", 210.00, now, "AGRICULTURAL", 100.0, "Plot 7, Mazowe Valley Farm", "0774321987")
                )
                conn.commit()
    except Exception as e:
        print("DB init error:", e)

init_db()

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

@app.route('/api/tariffs', methods=['GET'])
def get_tariffs_catalog():
    return jsonify({
        "success": True,
        "effective_date": "1 December 2023 (Official ZERA Approved)",
        "categories": TARIFF_CATEGORIES,
        "zig_exchange_rate": ZIG_EXCHANGE_RATE
    })

@app.route('/api/calculate_quote', methods=['POST'])
def calculate_quote():
    data = request.get_json() or {}
    category_key = data.get('tariff_category', 'DOMESTIC_STEPPED')
    amount = float(data.get('amount', 10))
    currency = data.get('currency', 'USD')
    monthly_units = float(data.get('monthly_units', 0))

    quote = calculate_energy_yield(category_key, amount, currency, monthly_units)
    return jsonify({"success": True, "quote": quote})

@app.route('/api/status', methods=['GET'])
def get_status():
    user = get_user_by_request()
    if not user:
        return jsonify({
            "username": "admin",
            "meter_number": "1234567890",
            "unit_balance": 45.72,
            "tariff_category": "DOMESTIC_STEPPED",
            "tariff_name": TARIFF_CATEGORIES["DOMESTIC_STEPPED"]["name"],
            "monthly_purchased_units": 0.0,
            "address": "25 Samora Machel Ave, Harare",
            "status": "NORMAL"
        })

    balance = round(float(user["unit_balance"]), 2)
    cat_key = user.get("tariff_category", "DOMESTIC_STEPPED")
    cat_info = TARIFF_CATEGORIES.get(cat_key, TARIFF_CATEGORIES["DOMESTIC_STEPPED"])

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
        cat_info = TARIFF_CATEGORIES.get(cat_key, TARIFF_CATEGORIES["DOMESTIC_STEPPED"])
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

    calc = calculate_energy_yield(cat_key, amount, currency, monthly_units)
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
    try:
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
    except Exception:
        return jsonify({"success": True, "meter_number": meter_number, "transactions": []})

@app.after_request
def add_cors_headers(response):
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS, PUT, DELETE'
    response.headers['Access-Control-Allow-Headers'] = 'Content-Type, X-Meter-Number, Authorization'
    return response
