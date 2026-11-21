pipeline {
    agent any

    parameters {
        booleanParam(name: 'INJECT_FAILURE', defaultValue: false, description: 'Inject failure into deployment health check')
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }
        stage('Build & Test') {
            steps {
                sh 'mvn -f app/pom.xml test'
            }
        }
        stage('Docker Build') {
            steps {
                sh "docker build -t resqcd:${BUILD_NUMBER} ./app"
            }
        }
        stage('Trivy') {
            steps {
                sh "docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:latest image --severity HIGH,CRITICAL --exit-code 0 resqcd:${BUILD_NUMBER}"
            }
        }
        stage('Deploy') {
            steps {
                script {
                    def deployScript = fileExists('/deploy/deploy.sh') ? '/deploy/deploy.sh' : 'deploy/deploy.sh'
                    if (params.INJECT_FAILURE) {
                        sh "BREAK_HEALTH=true bash ${deployScript} ${BUILD_NUMBER}"
                    } else {
                        sh "bash ${deployScript} ${BUILD_NUMBER}"
                    }
                }
            }
        }
    }

    post {
        always {
            sh "if [ -f /deploy/state/history.json ]; then mkdir -p deploy/state && cp /deploy/state/history.json deploy/state/history.json; fi"
            archiveArtifacts artifacts: 'deploy/state/history.json', allowEmptyArchive: true
        }
    }
}
