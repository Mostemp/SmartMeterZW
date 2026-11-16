import re

with open('smartmeter_zw/lib/main.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

new_lines = []
skip_paypal = False

for i, line in enumerate(lines):
    # 1. Replace the if condition
    if "if (_paymentMethod == 'ecocash') ...[" in line:
        new_lines.append(line.replace("if (_paymentMethod == 'ecocash') ...[", "if (['ecocash', 'onemoney', 'innbucks', 'paynow', 'card'].contains(_paymentMethod)) ...["))
        continue
    
    # 4. Skip paypal block
    if "] else if (_paymentMethod == 'paypal') ...[" in line:
        skip_paypal = True
        continue
    if skip_paypal and "] else ...[" in line:
        skip_paypal = False
        new_lines.append(line)
        continue
    if skip_paypal:
        continue
        
    new_lines.append(line)

code = "".join(new_lines)

# 2. Replace EcoCash Number TextField block
old_textfield = """              Text(
                'EcoCash Number',
                style: TextStyle(color: Colors.grey[300], fontSize: 13),
              ),
              SizedBox(height: 8),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                style: TextStyle(color: kText),
                decoration: InputDecoration(
                  hintText: '077XXXXXXX',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  prefixIcon: Icon(Icons.phone, color: kGreen),
                  filled: true,
                  fillColor: kCard,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.withOpacity(0.3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.withOpacity(0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: kGreen),
                  ),
                ),
              ),"""

new_textfield = """              if (_paymentMethod == 'ecocash') ...[
                Text('EcoCash Number', style: TextStyle(color: Colors.grey[300], fontSize: 13)),
                SizedBox(height: 8),
                TextField(controller: _phoneController, keyboardType: TextInputType.phone, style: TextStyle(color: kText), decoration: InputDecoration(hintText: '077XXXXXXX', hintStyle: TextStyle(color: Colors.grey[600]), prefixIcon: Icon(Icons.phone, color: kGreen), filled: true, fillColor: kCard, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.withOpacity(0.3))), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.withOpacity(0.3))), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: kGreen)))),
              ] else if (_paymentMethod == 'onemoney') ...[
                Text('OneMoney Number', style: TextStyle(color: Colors.grey[300], fontSize: 13)),
                SizedBox(height: 8),
                TextField(controller: _oneMoneyController, keyboardType: TextInputType.phone, style: TextStyle(color: kText), decoration: InputDecoration(hintText: '071XXXXXXX', hintStyle: TextStyle(color: Colors.grey[600]), prefixIcon: Icon(Icons.phone, color: Colors.orange), filled: true, fillColor: kCard, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.withOpacity(0.3))), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.withOpacity(0.3))), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.orange)))),
              ] else if (_paymentMethod == 'innbucks') ...[
                Text('InnBucks Registered Number', style: TextStyle(color: Colors.grey[300], fontSize: 13)),
                SizedBox(height: 8),
                TextField(controller: _innbucksController, keyboardType: TextInputType.phone, style: TextStyle(color: kText), decoration: InputDecoration(hintText: '07XXXXXXX', hintStyle: TextStyle(color: Colors.grey[600]), prefixIcon: Icon(Icons.phone, color: Colors.blue), filled: true, fillColor: kCard, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.withOpacity(0.3))), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.withOpacity(0.3))), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.blue)))),
              ] else if (_paymentMethod == 'card') ...[
                Text('Card Number', style: TextStyle(color: Colors.grey[300], fontSize: 13)),
                SizedBox(height: 8),
                TextField(controller: _cardNumberController, keyboardType: TextInputType.number, style: TextStyle(color: kText), decoration: InputDecoration(hintText: 'XXXX XXXX XXXX XXXX', hintStyle: TextStyle(color: Colors.grey[600]), prefixIcon: Icon(Icons.credit_card, color: Colors.indigo), filled: true, fillColor: kCard, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.withOpacity(0.3))), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.withOpacity(0.3))), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.indigo)))),
              ] else if (_paymentMethod == 'paynow') ...[
                Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.purple.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Text('Paynow gateway will open in your browser to complete the transaction securely.', style: TextStyle(color: Colors.purple, fontSize: 13))),
              ],"""

code = code.replace(old_textfield, new_textfield)

# 3. Replace the EcoCash Button Block
old_button = """              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _loading ? null : _initiatePayment,
                  icon: _loading
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: kText,
                          ),
                        )
                      : Icon(Icons.payment, color: kText),
                  label: Text(
                    'Pay with EcoCash ($_selectedCurrency)',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: kText,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kEcoGreen,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),"""

new_button = """              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _loading ? null : () {
                    if (_paymentMethod == 'ecocash') _initiatePayment();
                    else if (_paymentMethod == 'onemoney') _initiateOneMoney();
                    else if (_paymentMethod == 'innbucks') _initiateInnBucks();
                    else if (_paymentMethod == 'paynow') _initiatePaynow();
                    else if (_paymentMethod == 'card') _initiateCardPayment();
                  },
                  icon: _loading
                      ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: kText))
                      : Icon(Icons.payment, color: kText),
                  label: Text(
                    'Pay with ${_paymentMethod.toUpperCase()} ($_selectedCurrency)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kText),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _paymentMethod == 'onemoney' ? Colors.orange : 
                                     _paymentMethod == 'innbucks' ? Colors.blue : 
                                     _paymentMethod == 'paynow' ? Colors.purple : 
                                     _paymentMethod == 'card' ? Colors.indigo : kEcoGreen,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),"""

code = code.replace(old_button, new_button)

# Also fix the `_initiatePayPal` reference in `flutter analyze` that caused the error:
# It's at line 2948 in the original file, which is inside the paypal block. Since we skipped the paypal block, it should be gone!

with open('smartmeter_zw/lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(code)

print("UI Refactoring complete.")
