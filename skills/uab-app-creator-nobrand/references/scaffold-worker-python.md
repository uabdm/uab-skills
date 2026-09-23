# Project Scaffold — Background worker (Python / FastAPI)

Used when Q4 (visual interface) = "No — it runs automatically" — see
`decision-matrix.md`. Generate a working Python FastAPI background worker. No
UI is generated. Use unversioned package names in `requirements.txt` (no
version pins unless a minimum version is required for a specific API used in
the scaffold).

## Folder structure

```
./                               ← repo root
├── app/
│   ├── __init__.py
│   ├── main.py                  ← entry point; FastAPI app with /health endpoint
│   ├── config.py                ← loads all env vars; raises on missing required vars
│   ├── routes/
│   │   ├── __init__.py
│   │   └── health.py            ← GET /health → {"status": "ok", "app": "<name>"}
│   └── services/
│       └── __init__.py          ← stub service files per integration
├── tests/
│   └── test_health.py
├── Dockerfile
├── .dockerignore                ← see data-layer.md
├── requirements.txt             ← unversioned package names
├── .gitignore                   ← see data-layer.md
├── .env.local                   ← generated whenever a data store or an external
│                                    integration was chosen — see decision-matrix.md
├── .env.template                ← see env-template.md
└── README.md                    ← see readme-template.md
```

## Dockerfile

```dockerfile
# TODO: Replace with the current stable python slim tag from hub.docker.com
FROM python:3.12-slim
WORKDIR /app
RUN adduser --disabled-password --gecos '' appuser
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
USER appuser
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```
