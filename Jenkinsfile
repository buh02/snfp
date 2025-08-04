pipeline {
    agent { label 'windows-deployer' }

    stages {
        stage('Checkout y Validación') {
            steps {
                // Clonamos el repositorio (Jenkins lo hace implícitamente si hay Jenkinsfile,
                // pero lo puedes forzar si necesitas control completo)
                git credentialsId: 'github-buh02-key',
                    url: 'git@github.com:buh02/snfp.git'

                // Validamos el workspace actual
                echo "Workspace actual: ${env.WORKSPACE}"

                // Confirmamos commit obtenido
                bat 'git rev-parse HEAD'
                bat 'git log -1 --oneline'
            }
        }

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
