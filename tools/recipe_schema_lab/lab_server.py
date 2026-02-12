from __future__ import annotations

from http.server import ThreadingHTTPServer

from lab_config import ARTIFACT_MODEL, HOST, LOCAL_CASES_DIR, LOCAL_TMP_DIR, PORT, REPO_ROOT
from lab_handler import LabHandler


def main() -> None:
    LOCAL_CASES_DIR.mkdir(parents=True, exist_ok=True)
    LOCAL_TMP_DIR.mkdir(parents=True, exist_ok=True)

    print("Cauldron Model Lab")
    print(f"Repo root: {REPO_ROOT}")
    print(f"Model: {ARTIFACT_MODEL}")
    print(f"Local cases: {LOCAL_CASES_DIR}")
    print(f"Open: http://{HOST}:{PORT}")

    server = ThreadingHTTPServer((HOST, PORT), LabHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
