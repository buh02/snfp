pipeline {
    agent { label 'windows' }

    stages {
        stage('Despliegue IIS') {
            steps {
                bat 'powershell -ExecutionPolicy Bypass -File snfp\\Deploy-Infotep.SNFP.ps1'
            }
        }
    }

    post {
        success {
            echo '✅ Despliegue exitoso.'
        }
        failure {
            echo '❌ Error durante el despliegue. Revisar logs y salida del script.'
        }
    }
}

