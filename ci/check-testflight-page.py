"""Check rendered enrollment UI; no invitations or signup actions."""
import json
from pathlib import Path
from playwright.sync_api import sync_playwright

path = Path("build/artifacts/testflight-publication.json")
if not path.exists():
    print("Newest release is processing; public-page completion remains pending.")
    raise SystemExit(0)
state = json.loads(path.read_text())
with sync_playwright() as p:
    browser = p.chromium.launch()
    # Apple hides enrollment controls from unsupported Linux desktop clients.
    page = browser.new_page(**p.devices["iPhone 13"], locale="en-US")
    page.goto(state["publicLink"], wait_until="domcontentloaded", timeout=60000)
    page.get_by_role("link", name="View in TestFlight", exact=True).wait_for(timeout=30000)
    text = page.locator("body").inner_text()
    if "t." not in text or any(message in text.lower() for message in
            ("beta is full", "not accepting", "isn't accepting", "not available")):
        raise RuntimeError("Public TestFlight page is not accepting testers")
    browser.close()
state["renderedPublicJoinPageAcceptsTesters"] = True
state["publicationComplete"] = state["audiencesActive"]
path.write_text(json.dumps(state, indent=2) + "\n")
print("Rendered public TestFlight join page accepts testers.")
