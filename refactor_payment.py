import re

with open('smartmeter_zw/lib/main.dart', 'r', encoding='utf-8') as f:
    code = f.read()

# 1. Update Controllers
old_controllers = """  final TextEditingController _phoneController = TextEditingController(
    text: '077',
  );
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _meterController = TextEditingController();
  final TextEditingController _paypalEmailController = TextEditingController();"""

new_controllers = """  final TextEditingController _phoneController = TextEditingController(text: '077');
  final TextEditingController _oneMoneyController = TextEditingController(text: '071');
  final TextEditingController _innbucksController = TextEditingController();
  final TextEditingController _cardNumberController = TextEditingController();
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _meterController = TextEditingController();"""

code = code.replace(old_controllers, new_controllers)

# 2. Update Payment Methods Subtitle
code = code.replace("'EcoCash · PayPal · ZESA Token',", "'Local Payments · ZESA Token',")

# 3. Replace the Payment Method Tabs
old_tabs = """            // ── Payment Method Tabs ──────────────────
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _paymentMethod = 'ecocash'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _paymentMethod == 'ecocash' ? kEcoGreen : kCard,
                        borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
                      ),
                      child: Center(
                        child: Text('EcoCash', style: TextStyle(
                          color: _paymentMethod == 'ecocash' ? Colors.white : Colors.grey,
                          fontWeight: FontWeight.bold, fontSize: 12,
                        )),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _paymentMethod = 'paypal'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _paymentMethod == 'paypal' ? const Color(0xFF003087) : kCard,
                      ),
                      child: Center(
                        child: Text('PayPal', style: TextStyle(
                          color: _paymentMethod == 'paypal' ? Colors.white : Colors.grey,
                          fontWeight: FontWeight.bold, fontSize: 12,
                        )),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _paymentMethod = 'token'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _paymentMethod == 'token' ? kGreen : kCard,
                        borderRadius: const BorderRadius.horizontal(right: Radius.circular(10)),
                      ),
                      child: Center(
                        child: Text('ZESA Token', style: TextStyle(
                          color: _paymentMethod == 'token' ? Colors.white : Colors.grey,
                          fontWeight: FontWeight.bold, fontSize: 12,
                        )),
                      ),
                    ),
                  ),
                ),
              ],
            ),"""

new_tabs = """            // ── Payment Method Tabs ──────────────────
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _paymentTab('ecocash', 'EcoCash', kEcoGreen),
                _paymentTab('onemoney', 'OneMoney', Colors.orange),
                _paymentTab('innbucks', 'InnBucks', Colors.blue),
                _paymentTab('paynow', 'Paynow', Colors.purple),
                _paymentTab('card', 'Card', Colors.indigo),
                _paymentTab('token', 'ZESA Token', kGreen),
              ],
            ),"""
code = code.replace(old_tabs, new_tabs)

# 4. Insert _paymentTab helper method
payment_tab_helper = """  Widget _paymentTab(String id, String label, Color color) {
    bool isSelected = _paymentMethod == id;
    return GestureDetector(
      onTap: () => setState(() => _paymentMethod = id),
      child: Container(
        width: (MediaQuery.of(context).size.width - 40 - 16) / 3, // 3 columns
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color : kCard,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(label, style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey,
            fontWeight: FontWeight.bold, fontSize: 12,
          )),
        ),
      ),
    );
  }"""
  
# Insert helper method right before the end of _TopUpPageState
# Let's find: Widget _confirmRow(String label, String value) =>
code = code.replace("  Widget _confirmRow(String label, String value) =>", payment_tab_helper + "\n\n  Widget _confirmRow(String label, String value) =>")


# 5. Remove PayPal body and replace with generic ones
paypal_body_pattern = r"\} else if \(_paymentMethod == 'paypal'\) \.\.\.\[(.*?)\}\s+\] else if \(_paymentMethod == 'token'\)"
new_body = """} else if (['onemoney', 'innbucks', 'paynow', 'card'].contains(_paymentMethod)) ...[
              SizedBox(height: 16),
              if (_paymentMethod == 'onemoney')
                _customTextField('NetOne Mobile Number', Icons.phone_android, _oneMoneyController)
              else if (_paymentMethod == 'innbucks')
                _customTextField('InnBucks Registered Number', Icons.phone_android, _innbucksController)
              else if (_paymentMethod == 'card')
                _customTextField('Card Number', Icons.credit_card, _cardNumberController)
              else if (_paymentMethod == 'paynow')
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text('Paynow gateway will open in your browser to complete the transaction securely.', style: TextStyle(color: Colors.grey)),
                ),
            ] else if (_paymentMethod == 'token')"""

code = re.sub(paypal_body_pattern, new_body, code, flags=re.DOTALL)

# 6. Change "Proceed to Pay" button routing
old_proceed = """                onPressed: _loading
                    ? null
                    : () {
                        if (_paymentMethod == 'ecocash') {
                          _initiatePayment();
                        } else if (_paymentMethod == 'paypal') {
                          _initiatePayPal();
                        } else if (_paymentMethod == 'token') {
                          _redeemToken();
                        }
                      },"""

new_proceed = """                onPressed: _loading
                    ? null
                    : () {
                        if (_paymentMethod == 'ecocash') {
                          _initiatePayment();
                        } else if (_paymentMethod == 'onemoney') {
                          _initiateOneMoney();
                        } else if (_paymentMethod == 'innbucks') {
                          _initiateInnBucks();
                        } else if (_paymentMethod == 'paynow') {
                          _initiatePaynow();
                        } else if (_paymentMethod == 'card') {
                          _initiateCardPayment();
                        } else if (_paymentMethod == 'token') {
                          _redeemToken();
                        }
                      },"""

code = code.replace(old_proceed, new_proceed)

# 7. Delete PayPal Logic and add new methods
paypal_logic_pattern = r"  // ─── PayPal Flow ───────────────────────────────────────────.*?  Future<void> _redeemToken\(\) async \{"

new_methods = """  // ─── New Payment Flows ───────────────────────────────────────────
  Future<void> _initiateOneMoney() async {
    // Simulated OneMoney flow
    final targetMeter = _meterController.text.trim();
    if (targetMeter.isEmpty) {
      _showEconetPopup('Missing Meter', 'Please enter a target prepaid meter number.', success: false);
      return;
    }
    setState(() => _loading = true);
    await Future.delayed(const Duration(seconds: 1)); // simulate check
    setState(() => _loading = false);
    
    final pinEntered = await _showSimulatedPinDialog('OneMoney PIN', Colors.orange);
    if (pinEntered != true) return;

    _processSimulatedPayment('OneMoney', Colors.orange, targetMeter);
  }

  Future<void> _initiateInnBucks() async {
    final targetMeter = _meterController.text.trim();
    if (targetMeter.isEmpty) {
      _showEconetPopup('Missing Meter', 'Please enter a target prepaid meter number.', success: false);
      return;
    }
    setState(() => _loading = true);
    await Future.delayed(const Duration(seconds: 1));
    setState(() => _loading = false);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: Text('InnBucks Payment', style: TextStyle(color: Colors.blue)),
        content: Text('Open your InnBucks app to authorize \$$_selectedAmount USD.', style: TextStyle(color: kText)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.blue), child: Text('I have authorized')),
        ],
      )
    );
    if (confirmed != true) return;
    _processSimulatedPayment('InnBucks', Colors.blue, targetMeter);
  }

  Future<void> _initiatePaynow() async {
    final targetMeter = _meterController.text.trim();
    if (targetMeter.isEmpty) {
      _showEconetPopup('Missing Meter', 'Please enter a target prepaid meter number.', success: false);
      return;
    }
    setState(() => _loading = true);
    await Future.delayed(const Duration(seconds: 2)); // Simulate redirect
    setState(() => _loading = false);
    _processSimulatedPayment('Paynow', Colors.purple, targetMeter);
  }

  Future<void> _initiateCardPayment() async {
    final targetMeter = _meterController.text.trim();
    if (targetMeter.isEmpty) {
      _showEconetPopup('Missing Meter', 'Please enter a target prepaid meter number.', success: false);
      return;
    }
    setState(() => _loading = true);
    await Future.delayed(const Duration(seconds: 1));
    setState(() => _loading = false);

    final pinEntered = await _showSimulatedPinDialog('Card PIN / OTP', Colors.indigo);
    if (pinEntered != true) return;

    _processSimulatedPayment('Visa/Mastercard', Colors.indigo, targetMeter);
  }

  Future<bool?> _showSimulatedPinDialog(String title, Color color) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        content: TextField(
          obscureText: true,
          keyboardType: TextInputType.number,
          style: TextStyle(color: kText),
          decoration: InputDecoration(labelText: 'Enter PIN / OTP', labelStyle: TextStyle(color: Colors.grey)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: color), child: Text('Submit')),
        ],
      )
    );
  }

  Future<void> _processSimulatedPayment(String method, Color color, String targetMeter) async {
    setState(() => _loading = true);
    _showProcessingPopup();
    await Future.delayed(const Duration(seconds: 2));

    try {
      final endpoint = _selectedCurrency == 'USD' ? '/api/topup/$_selectedAmount' : '/api/topup_zig/$_selectedAmount';
      final res = await http.post(Uri.parse('$BASE_URL$endpoint'), headers: {'X-Meter-Number': targetMeter});
      Navigator.of(context).pop(); // pop processing
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final units = data['units_added'];
        final balance = data['new_balance'];

        _showEconetPopup(
          '$method Payment Successful',
          '${_selectedCurrency == 'USD' ? '\\$' : 'ZiG '}$_selectedAmount.00 paid via $method. Token: ${_generateToken()}. +${units.toStringAsFixed(2)} Units.',
          success: true,
        );
        globalNotifications.insert(0, AppNotification(
          title: '$method Top-up',
          body: '${_selectedCurrency == 'USD' ? '\\$' : 'ZiG '}$_selectedAmount paid. +${units.toStringAsFixed(2)} Units.',
          time: DateTime.now(),
          icon: Icons.payment,
          color: color,
        ));
      }
    } catch (_) {
      Navigator.of(context).pop();
      _showEconetPopup('Failed', 'Payment failed.', success: false);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _redeemToken() async {"""

code = re.sub(paypal_logic_pattern, new_methods, code, flags=re.DOTALL)

with open('smartmeter_zw/lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(code)

print("Refactoring complete.")
