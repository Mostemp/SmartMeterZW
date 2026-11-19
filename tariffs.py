import math

# Official ZETDC Tariff Schedule
# All prices in USD base; ZiG conversion applies standard peg (e.g. 1 USD = 25 ZiG)
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
        "rea_levy": 0.06,  # 6% Rural Electrification Levy
        "vat": 0.00        # Domestic is zero-rated for VAT (SI 168 of 2012)
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
        "description": "Retail shops, schools, clinics, small commercial premises",
        "rea_levy": 0.06,
        "vat": 0.15        # 15% VAT applies
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
    """
    Computes units credited, effective tariff breakdown, and taxes according to ZETDC SI rules.
    """
    cat = TARIFF_CATEGORIES.get(category_key, TARIFF_CATEGORIES["DOMESTIC_STEPPED"])
    
    # Normalize amount to USD for tariff calculation
    usd_amount = amount_paid if currency.upper() == "USD" else (amount_paid / ZIG_EXCHANGE_RATE)
    
    # Factor out taxes: Total Paid = Energy Cost * (1 + rea_levy + vat)
    tax_multiplier = 1.0 + cat["rea_levy"] + cat["vat"]
    net_energy_funds = usd_amount / tax_multiplier
    tax_amount = usd_amount - net_energy_funds
    
    units_credited = 0.0
    tier_breakdown = []
    
    if cat["type"] == "stepped":
        remaining_funds = net_energy_funds
        current_cumulative = monthly_purchased_so_far
        
        # Tier 1: 0 - 50 kWh @ $0.05
        # Tier 2: 51 - 300 kWh (next 250 kWh) @ $0.19
        # Tier 3: > 300 kWh @ $0.25
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
                
        # Tier 2 (up to 300 cumulative)
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
                
        # Tier 3 (Balance excess @ $0.25)
        if remaining_funds > 0:
            t3_rate = 0.25
            u = remaining_funds / t3_rate
            units_credited += u
            tier_breakdown.append({"tier": "> 300 kWh (Balance)", "units": round(u, 2), "rate": t3_rate})
            
    else:
        # Flat tariff
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
