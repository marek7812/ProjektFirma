#!/bin/bash
set -e

TAILSCALE_DOMAIN="${TAILSCALE_DOMAIN:-ubuntu.goblin-penny.ts.net}"
JWT_SECRET="${JWT_SECRET:-MojSekretnyKluczJWT2024!}"

echo ""
echo "==========================================="
echo "  Konfiguracja Nextcloud + OnlyOffice"
echo "==========================================="
echo ""

# --- Krok 1: Czekamy na MariaDB ---
echo "[1/6] Czekam na MariaDB..."
until docker exec firma-mariadb mariadb-admin ping -h localhost -u root -pzaq1@WSX --silent 2>/dev/null; do
    echo "      ...czekam 5s"
    sleep 5
done
echo "  ✓ MariaDB gotowa"

# --- Krok 2: Czekamy na Nextcloud ---
echo "[2/6] Czekam na Nextcloud (to może potrwać 1-2 minuty)..."
COUNTER=0
MAX_WAIT=60
until docker exec firma-nextcloud curl -sf http://localhost/status.php > /dev/null 2>&1; do
    COUNTER=$((COUNTER+1))
    if [ $COUNTER -ge $MAX_WAIT ]; then
        echo ""
        echo "  ✗ Nextcloud nie odpowiada po $((MAX_WAIT*10)) sekundach!"
        echo "    Sprawdź logi: docker compose logs nextcloud --tail=50"
        echo ""
        docker compose logs nextcloud --tail=20
        exit 1
    fi
    echo "      ...czekam 10s (próba $COUNTER/$MAX_WAIT)"
    sleep 10
done
echo "  ✓ Nextcloud gotowy"

# --- Krok 3: Czekamy na OnlyOffice ---
echo "[3/6] Czekam na OnlyOffice (ten startuje najdłużej ~2-3 min)..."
COUNTER=0
until docker exec firma-onlyoffice curl -sf http://localhost/healthcheck 2>/dev/null | grep -q "true"; do
    COUNTER=$((COUNTER+1))
    if [ $COUNTER -ge $MAX_WAIT ]; then
        echo ""
        echo "  ✗ OnlyOffice nie odpowiada!"
        echo "    Sprawdź logi: docker compose logs onlyoffice --tail=50"
        exit 1
    fi
    echo "      ...czekam 15s (próba $COUNTER/$MAX_WAIT)"
    sleep 15
done
echo "  ✓ OnlyOffice gotowy"

# --- Krok 4: Trusted domains ---
echo "[4/6] Konfiguruję trusted domains..."
docker exec -u www-data firma-nextcloud php occ config:system:set \
    trusted_domains 0 --value="localhost"
docker exec -u www-data firma-nextcloud php occ config:system:set \
    trusted_domains 1 --value="${TAILSCALE_DOMAIN}"
docker exec -u www-data firma-nextcloud php occ config:system:set \
    overwriteprotocol --value="http"
docker exec -u www-data firma-nextcloud php occ config:system:set \
    allow_local_remote_servers --value="true" --type=boolean
echo "  ✓ Trusted domains OK"

# --- Krok 5: Instalacja aplikacji OnlyOffice ---
echo "[5/6] Instaluję aplikację OnlyOffice w Nextcloud..."
docker exec -u www-data firma-nextcloud php occ app:install onlyoffice 2>/dev/null || \
docker exec -u www-data firma-nextcloud php occ app:enable onlyoffice 2>/dev/null || true
echo "  ✓ Aplikacja zainstalowana"

# --- Krok 6: Konfiguracja połączenia ---
echo "[6/6] Konfiguruję połączenie z serwerem dokumentów..."
docker exec -u www-data firma-nextcloud php occ config:app:set onlyoffice \
    DocumentServerUrl --value="http://${TAILSCALE_DOMAIN}:8443"
docker exec -u www-data firma-nextcloud php occ config:app:set onlyoffice \
    DocumentServerInternalUrl --value="http://onlyoffice/"
docker exec -u www-data firma-nextcloud php occ config:app:set onlyoffice \
    StorageUrl --value="http://nextcloud/"
docker exec -u www-data firma-nextcloud php occ config:app:set onlyoffice \
    jwt_secret --value="${JWT_SECRET}"
echo "  ✓ Połączenie skonfigurowane"

echo ""
echo "==========================================="
echo "  GOTOWE!"
echo "==========================================="
echo ""
echo "  Nextcloud:   http://${TAILSCALE_DOMAIN}:8080"
echo "  OnlyOffice:  http://${TAILSCALE_DOMAIN}:8443"
echo "  phpMyAdmin:  http://${TAILSCALE_DOMAIN}:8081"
echo ""
echo "  Login:  admin"
echo "  Hasło:  zaq1@WSX"
echo ""
