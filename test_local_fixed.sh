#!/bin/bash

cd /home/gadirov/Desktop/test/7

echo "=== Testing OpenBMC Pipeline with your ROMULUS setup ==="

# Создаем директорию для артефактов
mkdir -p artifacts

echo "1. Checking ROMULUS image..."
if [ -f "romulus/obmc-phosphor-image-romulus-20250909035339.static.mtd" ]; then
    echo "✓ ROMULUS image found"
else
    echo "✗ ROMULUS image not found!"
    exit 1
fi

echo "2. Starting QEMU using your rom.sh command..."
qemu-system-arm -m 256 -M romulus-bmc -nographic \
  -drive file=romulus/obmc-phosphor-image-romulus-20250909035339.static.mtd,format=raw,if=mtd \
  -net nic \
  -net user,hostfwd=:0.0.0.0:2222-:22,hostfwd=:0.0.0.0:2443-:443,hostfwd=udp:0.0.0.0:2623-:623,hostname=qemu &
QEMU_PID=$!
echo "QEMU started with PID: $QEMU_PID"

echo "3. Waiting for BMC to boot (90 seconds)..."
for i in {1..90}; do
    echo -ne "Waiting... $i/90 seconds\r"
    sleep 1
done
echo ""

echo "4. Testing SSH connection via localhost:2222..."
SSH_SUCCESS=false
for i in {1..15}; do
    echo "SSH attempt $i/15..."
    if sshpass -p '0penBmc' ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p 2222 root@localhost 'echo "SSH test successful - attempt $i"' 2>/dev/null; then
        echo "✓ SSH connection successful on attempt $i"
        SSH_SUCCESS=true
        break
    else
        echo "SSH attempt $i failed, waiting 10 seconds..."
        sleep 10
    fi
done

if [ "$SSH_SUCCESS" = true ]; then
    echo "5. Running system info tests..."
    sshpass -p '0penBmc' ssh -o StrictHostKeyChecking=no -p 2222 root@localhost '
        echo "=== System Information ==="
        cat /etc/os-release 2>/dev/null || echo "OS info not available"
        echo ""
        echo "=== BMC Version ==="
        cat /etc/version 2>/dev/null || echo "Version not available"
        echo ""
        echo "=== Uptime ==="
        uptime
        echo ""
        echo "=== Memory ==="
        free -h 2>/dev/null || cat /proc/meminfo | head -5
        echo ""
        echo "=== Network ==="
        ip addr show 2>/dev/null || ifconfig
        echo ""
        echo "=== Processes ==="
        ps aux | head -10
    ' > artifacts/system_info.txt 2>&1

    echo "6. Testing WebUI via localhost:2443 (HTTPS)..."
    echo "=== WebUI Test Results ===" > artifacts/webui_tests.txt
    echo "Testing HTTPS on port 2443..." >> artifacts/webui_tests.txt
    
    # Тестируем HTTPS с игнорированием SSL ошибок (самоподписанный сертификат)
    curl -s -k -o /dev/null -w "HTTPS Status: %{http_code}\n" https://localhost:2443/ >> artifacts/webui_tests.txt 2>&1
    
    echo "" >> artifacts/webui_tests.txt
    echo "Testing specific pages (with SSL ignore):" >> artifacts/webui_tests.txt
    for page in "/" "/login" "/index.html"; do
        STATUS=$(curl -s -k -o /dev/null -w "%{http_code}" "https://localhost:2443$page" 2>/dev/null)
        echo "Page $page: HTTPS $STATUS" >> artifacts/webui_tests.txt
    done

    echo "7. Testing WebUI content..."
    curl -s -k https://localhost:2443/ | head -100 > artifacts/webui_content.txt 2>&1

    echo "8. Light load testing..."
    echo "=== Load Test Results ===" > artifacts/load_test.txt
    ab -n 20 -c 3 https://localhost:2443/ >> artifacts/load_test.txt 2>&1 || echo "Load test completed" >> artifacts/load_test.txt

else
    echo "✗ SSH connection failed after 15 attempts"
    echo "SSH connection failed" > artifacts/connection_failed.txt
fi

echo "9. Stopping QEMU..."
kill $QEMU_PID 2>/dev/null
wait $QEMU_PID 2>/dev/null
pkill -f "qemu-system-arm.*romulus" 2>/dev/null || true

echo "=== Test completed ==="
echo "Check artifacts in: /home/gadirov/Desktop/test/7/artifacts/"
ls -la artifacts/
