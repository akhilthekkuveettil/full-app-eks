import os

# app.main reads DATABASE_URL at import time; tests mock psycopg, so any value works
os.environ.setdefault("DATABASE_URL", "postgresql://test:test@localhost:5432/test")
