# Mender Monitor check: reTerminal F3 button press
SERVICE_NAME="button_f3"
LOG_PATTERN="\\(KEY_D\\), value 1"
LOG_FILE="/var/log/button-events.log"
LOG_PATTERN_EXPIRATION=10
DESCRIPTION="reTerminal F3 button pressed"
