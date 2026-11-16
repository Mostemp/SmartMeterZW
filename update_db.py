import sqlite3

def main():
    conn = sqlite3.connect('smartmeter.db')
    try:
        conn.execute("ALTER TABLE users ADD COLUMN address TEXT DEFAULT 'Unknown'")
    except sqlite3.OperationalError:
        pass # Column might already exist
        
    conn.execute("UPDATE users SET address = '25 Samora Machel Ave, Harare' WHERE username = 'admin'")
    conn.execute("UPDATE users SET address = '123 Test Street' WHERE username = 'user1'")
    conn.commit()
    conn.close()
    print("Database updated.")

if __name__ == "__main__":
    main()
