import sqlite3
import json

try:
    conn = sqlite3.connect("/Users/letzgo/.stash/stash-go.sqlite")
    conn.row_factory = sqlite3.Row
    for row in conn.execute("SELECT name, filter FROM saved_filters LIMIT 20"):
        print(f"Name: {row['name']}, Filter: {row['filter']}")
except Exception as e:
    print(e)
