# Mender Monitor check: reTerminal F2 button press
SERVICE_NAME="button_f2"
LOG_PATTERN="\\(KEY_S\\), value 1"
LOG_FILE="/var/log/button-events.log"
LOG_PATTERN_EXPIRATION=10
DESCRIPTION="reTerminal F2 button pressed"
