#! /bin/sh

echo "starting update-ca-certificates systemd service, check output with 'journalctl _SYSTEMD_UNIT=update-ca-certificates.service'"
exec systemctl start update-ca-certificates.service
