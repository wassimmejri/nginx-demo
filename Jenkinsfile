pipeline {
    agent any
    environment {
        DOCKER_IMAGE  = "${env.DOCKER_IMAGE  ?: 'wassimmejri/nginx-demo:latest'}"
        K8S_NAMESPACE = "${env.K8S_NAMESPACE ?: 'default'}"
        SERVICE_NAME  = "${env.SERVICE_NAME  ?: 'nginx-demo'}"
        REPLICAS      = "${env.REPLICAS      ?: '1'}"
        SERVICE_PORT  = "${env.SERVICE_PORT  ?: '80'}"
        KUBECTL       = '/var/jenkins_home/kubectl'
    }
    stages {

        stage('Install kubectl') {
            steps {
                sh '''
                    if ! /home/jenkins/kubectl version --client > /dev/null 2>&1; then
                        curl -LO https://dl.k8s.io/release/v1.30.0/bin/linux/amd64/kubectl
                        chmod +x kubectl
                        mv kubectl /var/jenkins_home/kubectl
                    fi
                    /var/jenkins_home/kubectl version --client
                '''
            }
        }

        stage('Verify Tools') {
            steps {
                sh '$KUBECTL version --client'
                sh '$KUBECTL get nodes'
            }
        }

        stage('Create Namespace') {
            steps {
                sh '$KUBECTL create namespace $K8S_NAMESPACE --dry-run=client -o yaml | $KUBECTL apply -f -'
            }
        }

        stage('Build & Push with Kaniko') {
            steps {
                script {
                    sh "$KUBECTL delete pod kaniko-${env.SERVICE_NAME}-${BUILD_NUMBER} -n jenkins --ignore-not-found=true --force --grace-period=0 || true"

                    def repoUrl = scm.getUserRemoteConfigs()[0].getUrl()
                    def branch  = scm.getBranches()[0].getName().replace('*/', '')

                    def podYaml = """
apiVersion: v1
kind: Pod
metadata:
  name: kaniko-${env.SERVICE_NAME}-${BUILD_NUMBER}
  namespace: jenkins
  labels:
    app: kaniko-${env.SERVICE_NAME}
spec:
  serviceAccountName: kaniko-sa
  restartPolicy: Never
  containers:
  - name: kaniko
    image: gcr.io/kaniko-project/executor:latest
    imagePullPolicy: IfNotPresent
    args:
      - --context=git://${repoUrl.replace('https://', '')}
      - --git=branch=${branch}
      - --dockerfile=Dockerfile
      - --destination=${env.DOCKER_IMAGE}
      - --cache=true
    volumeMounts:
    - name: docker-secret
      mountPath: /kaniko/.docker
  volumes:
  - name: docker-secret
    secret:
      secretName: dockerhub-secret
      items:
      - key: .dockerconfigjson
        path: config.json
"""
                    writeFile file: 'kaniko-pod.yaml', text: podYaml
                    sh '$KUBECTL apply -f kaniko-pod.yaml'
                }

                sh '''
                    echo "Attente du build Kaniko..."
                    for i in $(seq 1 60); do
                        STATUS=$($KUBECTL get pod kaniko-${SERVICE_NAME}-${BUILD_NUMBER} \
                          -n jenkins -o jsonpath='{.status.phase}' 2>/dev/null || echo 'Pending')
                        echo "Status: $STATUS"
                        if [ "$STATUS" = "Succeeded" ]; then
                            echo "Build Kaniko reussi !"
                            break
                        elif [ "$STATUS" = "Failed" ]; then
                            echo "Build Kaniko echoue !"
                            $KUBECTL logs kaniko-${SERVICE_NAME}-${BUILD_NUMBER} -n jenkins || true
                            exit 1
                        fi
                        sleep 10
                    done
                '''
                sh '$KUBECTL delete pod kaniko-${SERVICE_NAME}-${BUILD_NUMBER} -n jenkins --ignore-not-found=true'
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                sh '''
                    $KUBECTL create deployment $SERVICE_NAME \
                      --image=$DOCKER_IMAGE \
                      --replicas=$REPLICAS \
                      -n $K8S_NAMESPACE \
                      --dry-run=client -o yaml | $KUBECTL apply -f -
                '''
            }
        }

        stage('Expose Service') {
            steps {
                sh '''
                    $KUBECTL expose deployment $SERVICE_NAME \
                      --port=$SERVICE_PORT \
                      --target-port=$SERVICE_PORT \
                      -n $K8S_NAMESPACE \
                      --dry-run=client -o yaml | $KUBECTL apply -f -
                '''
            }
        }

        stage('Verify Deployment') {
            steps {
                sh '$KUBECTL rollout status deployment/$SERVICE_NAME -n $K8S_NAMESPACE --timeout=120s'
                sh '$KUBECTL get pods -n $K8S_NAMESPACE'
                sh '$KUBECTL get svc -n $K8S_NAMESPACE'
            }
        }
    }

    post {
        success {
            script {
                sh """
                    curl -s --connect-timeout 5 -X POST http://192.168.254.129:5000/api/jenkins/webhook \\
                      -H 'Content-Type: application/json' \\
                      -d '{"job_name": "${env.JOB_NAME}", "build_number": ${env.BUILD_NUMBER}, "result": "SUCCESS"}' || true
                """
            }
            echo 'Deploiement reussi !'
        }
        failure {
            script {
                sh """
                    curl -s --connect-timeout 5 -X POST http://192.168.254.129:5000/api/jenkins/webhook \\
                      -H 'Content-Type: application/json' \\
                      -d '{"job_name": "${env.JOB_NAME}", "build_number": ${env.BUILD_NUMBER}, "result": "FAILURE"}' || true
                """
            }
            sh '$KUBECTL describe deployment $SERVICE_NAME -n $K8S_NAMESPACE || true'
            echo 'Deploiement echoue !'
        }
    }
}
