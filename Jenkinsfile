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
            steps {
                // Run inside the image: the workspace path is not visible to the
                // host Docker daemon, so bind mounts would resolve to nothing.
                // Coverage gate: fail the build under 80%.
                sh 'docker run --rm -e APP_ENV=test localiq-backend:${BUILD_NUMBER} python -m pytest -q --cov=app --cov=main --cov-fail-under=80'
            }
        }

        stage('Backend: API smoke') {
            steps {
                sh 'docker run --rm -e APP_ENV=test localiq-backend:${BUILD_NUMBER} bash tests/api_smoke.sh'
            }
        }

        stage('Frontend: build image') {
            when { expression { fileExists('frontend_flutter/Dockerfile') } }
            steps {
                sh 'docker build -t localiq-frontend:${BUILD_NUMBER} frontend_flutter/'
            }
        }
    }

    post {
        always {
            sh 'docker image prune -f >/dev/null 2>&1 || true'
        }
    }
}
