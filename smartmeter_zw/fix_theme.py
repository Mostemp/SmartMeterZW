import re

def main():
    file_path = "lib/main.dart"
    
    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read()

    # Fix the kText70 mistake
    content = content.replace("kText70", "Colors.white70")

    # Remove `const` from common widgets to avoid invalid constant errors
    # (since many now take dynamic color parameters)
    widgets_to_unconst = [
        "Text", "Icon", "TextStyle", "Divider", 
        "CircularProgressIndicator", "BoxDecoration", "BorderSide",
        "SizedBox", "Padding", "Container", "Row", "Column", "Expanded"
    ]
    
    for widget in widgets_to_unconst:
        content = content.replace(f"const {widget}(", f"{widget}(")

    with open(file_path, "w", encoding="utf-8") as f:
        f.write(content)
        
    print("Fixes applied.")

if __name__ == "__main__":
    main()
