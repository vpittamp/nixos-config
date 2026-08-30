"""Constants for the Time To Pet integration."""

DOMAIN = "timetopet"

# Time To Pet client portal. The portal is a server-rendered app whose
# schedule page polls two JSON endpoints once the browser holds a session
# cookie: /portal/services/eventFeed (FullCalendar feed of scheduled and
# completed visits) and /portal/services/pendingEventFeed (awaiting company
# approval). Login is a CSRF-protected form POST that returns JSON.
BASE_URL = "https://www.timetopet.com"
LOGIN_PAGE_URL = f"{BASE_URL}/portal/login"
LOGIN_AJAX_URL = f"{BASE_URL}/portal/login/ajaxProcessLogin"
EVENT_FEED_URL = f"{BASE_URL}/portal/services/eventFeed"
PENDING_EVENT_FEED_URL = f"{BASE_URL}/portal/services/pendingEventFeed"

USER_AGENT = (
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/126.0 Safari/537.36"
)

# Poll interval and feed window: yesterday through two weeks out.
DEFAULT_SCAN_INTERVAL = 900
FEED_DAYS_BACK = 1
FEED_DAYS_AHEAD = 14
