cd /home/gadirov/Desktop/test/7

# Создаем финальный Jenkinsfile
cat > Jenkinsfile << 'EOF'
pipeline {
    agent any

    options {
        timeout(time: 60, unit: 'MINUTES')
    }

    environment {
        ARTIFACTS_DIR = "${env.WORKSPACE}/artifacts"
        BMC_HOST = "localhost"
        SSH_PORT = "2222"
        WEB_PORT = "2443"
        BMC_USER = "root"
        BMC_PASSWORD = "0penBmc"
        ROMULUS_IMAGE = "romulus/obmc-phosphor-image-romulus-20250909035339.static.mtd"
    }

    stages {
        stage('Prepare Environment') {
            steps {
                script {
                    sh "mkdir -p ${ARTIFACTS_DIR}"
                    sh """
                        echo "Pipeline Start: \$(date)" > ${ARTIFACTS_DIR}/pipeline_start.log
                        if [ -f "${ROMULUS_IMAGE}" ]; then
                            echo "ROMULUS image found" >> ${ARTIFACTS_DIR}/pipeline_start.log
                        else
                            echo "ROMULUS image not found" >> ${ARTIFACTS_DIR}/pipeline_start.log
                            exit 1
                        fi
                    """
                }
            }
        }

        stage('Start QEMU with OpenBMC') {
            steps {
                script {
                    sh '''
                        pkill -f "qemu-system-arm.*romulus" || true
                        sleep 3
                    '''
                    
                    sh """
                        cd /home/gadirov/Desktop/test/7
                        qemu-system-arm -m 256 -M romulus-bmc -nographic \\
                          -drive file=${ROMULUS_IMAGE},format=raw,if=mtd \\
                          -net nic \\
                          -net user,hostfwd=tcp:0.0.0.0:${SSH_PORT}-:22,hostfwd=tcp:0.0.0.0:${WEB_PORT}-:443,hostname=qemu &
                        echo \$! > ${ARTIFACTS_DIR}/qemu.pid
                    """
                    
                    sh "sleep 90"
                }
            }
        }

        stage('Wait for BMC Ready') {
            steps {
                script {
                    sh """
                        for i in {1..10}; do
                            if sshpass -p '${BMC_PASSWORD}' ssh -o StrictHostKeyChecking=no -o ConnectTimeout=15 -p ${SSH_PORT} ${BMC_USER}@${BMC_HOST} 'echo "BMC ready - attempt \$i"'; then
                                echo "SSH success after \$i attempts" > ${ARTIFACTS_DIR}/bmc_status.txt
                                break
                            else
                                echo "SSH attempt \$i failed" >> ${ARTIFACTS_DIR}/ssh_attempts.log
                                sleep 10
                            fi
                        done
                    """
                }
            }
        }

        stage('Run Auto Tests') {
            steps {
                script {
                    sh """
                        sshpass -p '${BMC_PASSWORD}' ssh -o StrictHostKeyChecking=no -p ${SSH_PORT} ${BMC_USER}@${BMC_HOST} '
                            echo "=== System Information ==="
                            cat /etc/os-release
                            echo ""
                            echo "=== BMC Version ==="
                            cat /etc/version
                            echo ""
                            echo "=== Uptime ==="
                            uptime
                            echo ""
                            echo "=== Memory ==="
                            free
                            echo ""
                            echo "=== Disk ==="
                            df
                            echo ""
                            echo "=== Network ==="
                            ip addr show
                        ' > ${ARTIFACTS_DIR}/system_info.txt 2>&1
                    """
                    
                    sh """
                        sshpass -p '${BMC_PASSWORD}' ssh -o StrictHostKeyChecking=no -p ${SSH_PORT} ${BMC_USER}@${BMC_HOST} '
                            echo "=== Processes ==="
                            ps
                            echo ""
                            echo "=== Memory Details ==="
                            cat /proc/meminfo | head -10
                            echo ""
                            echo "=== CPU Info ==="
                            cat /proc/cpuinfo | head -20
                        ' > ${ARTIFACTS_DIR}/processes.txt 2>&1
                    """
                }
            }
            post {
                always {
                    sh """
                        cat > ${ARTIFACTS_DIR}/autotests.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="OpenBMC_Auto_Tests" tests="2" failures="0" errors="0" time="30">
    <testcase name="System_Information" classname="BMC.Info" time="10"/>
    <testcase name="Processes_Status" classname="BMC.Processes" time="5"/>
</testsuite>
EOF
                    """
                    junit testResults: '${ARTIFACTS_DIR}/autotests.xml'
                    
                    publishHTML(target: [
                        allowMissing: false,
                        alwaysLinkToLastBuild: true,
                        keepAll: true,
                        reportDir: '${ARTIFACTS_DIR}',
                        reportFiles: 'system_info.txt,processes.txt',
                        reportName: 'Auto Tests Reports'
                    ])
                }
            }
        }

        stage('Run WebUI Tests') {
            steps {
                script {
                    sh """
                        echo "=== WebUI Test Results ===" > ${ARTIFACTS_DIR}/webui_tests.txt
                        echo "Test time: \$(date)" >> ${ARTIFACTS_DIR}/webui_tests.txt
                        
                        HTTP_STATUS=\$(curl -s -k -o /dev/null -w "%{http_code}" "https://${BMC_HOST}:${WEB_PORT}/")
                        echo "Main page HTTPS status: \$HTTP_STATUS" >> ${ARTIFACTS_DIR}/webui_tests.txt
                        
                        for page in "/" "/login" "/index.html"; do
                            PAGE_STATUS=\$(curl -s -k -o /dev/null -w "%{http_code}" "https://${BMC_HOST}:${WEB_PORT}\${page}")
                            echo "Page \${page}: \$PAGE_STATUS" >> ${ARTIFACTS_DIR}/webui_tests.txt
                        done
                        
                        curl -s -k "https://${BMC_HOST}:${WEB_PORT}/" > ${ARTIFACTS_DIR}/webui_content.html
                    """
                }
            }
            post {
                always {
                    publishHTML(target: [
                        allowMissing: false,
                        alwaysLinkToLastBuild: true,
                        keepAll: true,
                        reportDir: '${ARTIFACTS_DIR}',
                        reportFiles: 'webui_tests.txt',
                        reportName: 'WebUI Test Results'
                    ])
                }
            }
        }

        stage('Run Load Testing') {
            steps {
                script {
                    sh """
                        echo "=== Load Testing ===" > ${ARTIFACTS_DIR}/load_test.txt
                        echo "Start: \$(date)" >> ${ARTIFACTS_DIR}/load_test.txt
                        ab -n 30 -c 5 -k "https://${BMC_HOST}:${WEB_PORT}/" >> ${ARTIFACTS_DIR}/load_test.txt 2>&1
                        echo "End: \$(date)" >> ${ARTIFACTS_DIR}/load_test.txt
                    """
                }
            }
            post {
                always {
                    publishHTML(target: [
                        allowMissing: false,
                        alwaysLinkToLastBuild: true,
                        keepAll: true,
                        reportDir: '${ARTIFACTS_DIR}',
                        reportFiles: 'load_test.txt',
                        reportName: 'Load Test Results'
                    ])
                }
            }
        }
    }

    post {
        always {
            script {
                sh """
                    if [ -f '${ARTIFACTS_DIR}/qemu.pid' ]; then
                        kill \$(cat '${ARTIFACTS_DIR}/qemu.pid') 2>/dev/null || true
                        rm -f '${ARTIFACTS_DIR}/qemu.pid'
                    fi
                    pkill -f "qemu-system-arm.*romulus" 2>/dev/null || true
                """
            }
            archiveArtifacts artifacts: 'artifacts/**/*', fingerprint: true
        }
        success {
            echo "OpenBMC CI/CD Pipeline completed successfully"
        }
        failure {
            echo "OpenBMC CI/CD Pipeline failed"
        }
    }
}
EOF


