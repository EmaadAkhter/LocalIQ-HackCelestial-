pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Backend: build image') {
            steps {
                sh 'docker build -t localiq-backend:${BUILD_NUMBER} backend/'
            }
        }

        stage('Backend: tests') {
            when { expression { fileExists('backend/tests') } }
            steps {
                sh 'docker run --rm -v "$PWD/backend":/app -w /app localiq-backend:${BUILD_NUMBER} python -m pytest -q'
            }
        }

        stage('Stack: smoke test') {
            steps {
                sh 'bash tests/smoke/smoke.sh'
            }
        }

        stage('Flutter: analyze') {
            when { expression { fileExists('frontend_flutter/pubspec.yaml') } }
            steps {
                sh '''
                    docker run --rm -v "$PWD/frontend_flutter":/app -w /app \
                      ghcr.io/cirruslabs/flutter:stable \
                      sh -c "flutter pub get && flutter analyze"
                '''
            }
        }
    }

    post {
        always {
            sh 'docker image prune -f >/dev/null 2>&1 || true'
        }
    }
}
