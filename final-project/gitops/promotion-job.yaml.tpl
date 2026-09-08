apiVersion: batch/v1
kind: Job
metadata:
  name: promote-__MODEL_VERSION__-__PIPELINE_ID__
  namespace: mlops-system
  labels:
    app.kubernetes.io/part-of: mlops-final-project
    operation: model-promotion
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 600
  template:
    spec:
      serviceAccountName: mlflow
      restartPolicy: Never
      containers:
        - name: promote
          image: __TRAINING_IMAGE__
          command: ["python", "-m", "src.promote", "promote", "--version", "__MODEL_VERSION__"]
          env:
            - {name: MLFLOW_TRACKING_URI, value: "http://mlflow.mlops-system.svc.cluster.local:5000"}
            - {name: ARTIFACT_BUCKET, value: "__ARTIFACT_BUCKET__"}
            - {name: GITLAB_USER_LOGIN, value: "__GITLAB_USER__"}
            - {name: CI_COMMIT_SHA, value: "__GIT_SHA__"}
          resources:
            requests: {cpu: 100m, memory: 256Mi}
            limits: {cpu: 500m, memory: 768Mi}
          securityContext:
            runAsNonRoot: true
            allowPrivilegeEscalation: false
            capabilities: {drop: ["ALL"]}
