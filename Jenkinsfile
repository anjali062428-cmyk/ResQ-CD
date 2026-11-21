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
        stage('Deploy') {
            steps {
                script {
                    if (params.INJECT_FAILURE) {
                        sh "BREAK_HEALTH=true bash deploy/deploy.sh ${BUILD_NUMBER}"
                    } else {
                        sh "bash deploy/deploy.sh ${BUILD_NUMBER}"
                    }
                }
            }
        }
    }

    post {
        always {
            archiveArtifacts artifacts: 'deploy/state/history.json', allowEmptyArchive: true
        }
    }
}
