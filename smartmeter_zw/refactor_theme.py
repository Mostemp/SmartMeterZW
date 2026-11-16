import re
import sys

def main():
    file_path = "lib/main.dart"
    
    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read()

    # 1. Define global state and getters
    global_defs = """
final ValueNotifier<bool> globalDarkMode = ValueNotifier(true);

Color get kBg => globalDarkMode.value ? const Color(0xFF0A0E1A) : Colors.grey[100]!;
Color get kCard => globalDarkMode.value ? const Color(0xFF111827) : Colors.white;
Color get kText => globalDarkMode.value ? Colors.white : Colors.black87;
Color get kSubText => globalDarkMode.value ? Colors.grey[400]! : Colors.black54;
Color get kDivider => globalDarkMode.value ? Colors.white10 : Colors.black12;

// Original constants
const String BASE_URL = 'http://10.64.14.177:5000';
const Color kGreen = Color(0xFF00D4AA);
const Color kEcoGreen = Color(0xFF4CAF50);
"""

    # Remove the old constants block
    content = re.sub(
        r"const String BASE_URL.*?const Color kEcoGreen = Color\(0xFF4CAF50\);",
        global_defs.strip(),
        content,
        flags=re.DOTALL
    )

    # 2. Update SmartMeterApp to use ValueListenableBuilder
    old_app_build = """  Widget build(BuildContext context) => MaterialApp(
        title: 'SmartMeter ZW',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: kBg,
          colorScheme: const ColorScheme.dark(primary: kGreen),
        ),
        home: const LoginScreen(),
      );"""
      
    new_app_build = """  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: globalDarkMode,
        builder: (context, isDark, child) {
          return MaterialApp(
            title: 'SmartMeter ZW',
            debugShowCheckedModeBanner: false,
            theme: isDark
                ? ThemeData.dark().copyWith(
                    scaffoldBackgroundColor: kBg,
                    colorScheme: const ColorScheme.dark(primary: kGreen),
                  )
                : ThemeData.light().copyWith(
                    scaffoldBackgroundColor: kBg,
                    colorScheme: const ColorScheme.light(primary: kGreen),
                  ),
            home: const LoginScreen(),
          );
        },
      );"""
      
    content = content.replace(old_app_build, new_app_build)
    
    # 3. Update SettingsPage toggle
    # Look for the Dark Mode switch in SettingsPage
    #  _switchTile(
    #    'Dark Mode',
    #    'Use dark theme',
    #    Icons.dark_mode,
    #    kGreen,
    #    _darkMode,
    #    (v) => setState(() => _darkMode = v),
    #  ),
    
    content = re.sub(
        r"_switchTile\(\s*'Dark Mode',\s*'Use dark theme',\s*Icons\.dark_mode,\s*kGreen,\s*_darkMode,\s*\(v\) => setState\(\(\) => _darkMode = v\),\s*\),",
        r"""_switchTile(
              'Dark Mode',
              'Use dark theme',
              Icons.dark_mode,
              kGreen,
              globalDarkMode.value,
              (v) {
                setState(() => _darkMode = v);
                globalDarkMode.value = v;
              },
            ),""",
        content
    )

    # 4. Color Replacements
    # Colors.white.withOpacity -> (globalDarkMode.value ? Colors.white : Colors.black).withOpacity
    content = content.replace("Colors.white.withOpacity", "(globalDarkMode.value ? Colors.white : Colors.black).withOpacity")
    
    # Colors.white70 -> (globalDarkMode.value ? Colors.white70 : Colors.black87)
    content = content.replace("Colors.white70", "(globalDarkMode.value ? Colors.white70 : Colors.black87)")
    
    # Colors.white10 -> kDivider
    content = content.replace("Colors.white10", "kDivider")
    
    # Colors.white -> kText (only stand-alone)
    # Using regex to ensure we don't replace inside words
    content = re.sub(r"(?<!\.)Colors\.white(?!\.)", "kText", content)
    
    # Colors.grey[400] -> kSubText
    content = content.replace("Colors.grey[400]", "kSubText")
    
    # const Color(0xFF0D1117) -> kBg
    content = content.replace("const Color(0xFF0D1117)", "kBg")
    content = content.replace("Color(0xFF0D1117)", "kBg")

    # 5. Remove `const` keyword from widgets that now use dynamic colors
    # This is tricky, we'll find lines with `const` and `kBg|kCard|kText|kSubText|kDivider|globalDarkMode`
    # and strip the `const` from that line.
    
    def strip_const(match):
        line = match.group(0)
        # Check if line contains one of our dynamic keywords
        if re.search(r'\b(kBg|kCard|kText|kSubText|kDivider|globalDarkMode)\b', line):
            # Remove `const ` but not inside strings if possible. 
            # Safe enough for Dart since we format strictly.
            return re.sub(r'\bconst\s+', '', line)
        return line
        
    lines = content.split('\n')
    new_lines = []
    for line in lines:
        if 'const' in line and re.search(r'\b(kBg|kCard|kText|kSubText|kDivider|globalDarkMode)\b', line):
            line = re.sub(r'\bconst\s+', '', line)
        new_lines.append(line)
        
    content = '\n'.join(new_lines)
    
    # One specific problematic line in TopUpPage:
    # color: _selectedCurrency == 'USD' ? kText : Colors.grey,
    # if it had const, we already stripped it.
    
    with open(file_path, "w", encoding="utf-8") as f:
        f.write(content)
        
    print("Refactoring complete.")

if __name__ == "__main__":
    main()
