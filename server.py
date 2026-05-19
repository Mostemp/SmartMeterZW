from flask import Flask, jsonify
from flask_cors import CORS
import random
import time

app = Flask(__name__)
CORS(app)

# Simulated meter state
meter_state = {
    "unit_balance": 45.72,
    "last_updated": time.time(),
    "tamper_triggered_time": 0,
    "usage_history": [12.4, 10.1, 13.8, 9.5, 11.2, 14.0, 10.8]
}

def get_simulated_consumption():
    hour = time.localtime().tm_hour
    base = 0.8
    if 6 <= hour < 9:     base = 2.4
    elif 17 <= hour < 21: base = 3.1
    elif 0 <= hour < 5:   base = 0.3
    return round(base + random.uniform(-0.2, 0.3), 2)

def drain_balance():
    now = time.time()
    elapsed_hours = (now - meter_state["last_updated"]) / 3600
    consumption_kw = get_simulated_consumption()
    units_used = consumption_kw * elapsed_hours
    meter_state["unit_balance"] = max(0, round(meter_state["unit_balance"] - units_used, 2))
    meter_state["last_updated"] = now

@app.route('/api/status', methods=['GET'])
def get_status():
    drain_balance()
    consumption = get_simulated_consumption()

    # Check if tamper was triggered within the last 8 seconds
    # This ensures both the mobile app and meter UI (polling every 5s) catch the alert
    tamper_time = meter_state.get('tamper_triggered_time', 0)
    tamper = (time.time() - tamper_time) < 8

    return jsonify({
        "unit_balance": meter_state["unit_balance"],
        "consumption_kw": consumption,
        "tamper_alert": tamper,
        "voltage": round(220 + random.uniform(-5, 5), 1),
        "status": "LOW_BALANCE" if meter_state["unit_balance"] < 5 else "NORMAL"
    })

@app.route('/api/tamper', methods=['POST'])
def trigger_tamper():
    meter_state['tamper_triggered_time'] = time.time()
    print("TAMPER ALERT triggered from simulator!")
    return jsonify({"success": True})

@app.route('/api/history', methods=['GET'])
def get_history():
    base = meter_state["usage_history"]
    history = []
    days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    for i, day in enumerate(days):
        history.append({
            "day": day,
            "Units": round(base[i] + random.uniform(-0.5, 0.5), 1)
        })
    return jsonify({"history": history})

@app.route('/api/topup/<int:amount>', methods=['POST'])
def topup(amount):
    units = round(amount / 0.35, 2)
    meter_state["unit_balance"] = round(meter_state["unit_balance"] + units, 2)
    return jsonify({
        "success": True,
        "units_added": units,
        "new_balance": meter_state["unit_balance"]
    })

@app.route('/api/topup_zig/<int:amount>', methods=['POST'])
def topup_zig(amount):
    # 1 Unit = 0.35 USD. At 1 USD = 25 ZiG, 1 Unit = 8.75 ZiG
    units = round(amount / 8.75, 2)
    meter_state["unit_balance"] = round(meter_state["unit_balance"] + units, 2)
    return jsonify({
        "success": True,
        "units_added": units,
        "new_balance": meter_state["unit_balance"]
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)