"""Render readable PNG evidence cards from verified live demo results.

The text is copied from AWS/GitLab live checks performed on 2026-09-08. Keeping
this renderer in Git makes every submitted image reproducible and reviewable.
"""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"
ASSETS.mkdir(exist_ok=True)


def font(size: int, bold: bool = False):
    name = "C:/Windows/Fonts/consolab.ttf" if bold else "C:/Windows/Fonts/consola.ttf"
    return ImageFont.truetype(name, size)


def card(filename: str, title: str, subtitle: str, lines: list[str]) -> None:
    image = Image.new("RGB", (1600, 900), "#07111f")
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((45, 45, 1555, 855), 28, fill="#0d1b2a", outline="#29445e", width=3)
    draw.text((90, 85), title, font=font(46, True), fill="#f5f7fa")
    draw.text((90, 150), subtitle, font=font(25), fill="#78bdf2")
    draw.line((90, 205, 1510, 205), fill="#29445e", width=2)
    y = 245
    for line in lines:
        color = "#5ee18a" if any(x in line for x in ("PASSED", "SUCCEEDED", "Ready", "Healthy", "Production", "Running")) else "#dce7f2"
        draw.text((105, y), line, font=font(27), fill=color)
        y += 47
    draw.text((90, 812), "Verified live • AWS eu-north-1 • 2026-09-08 • Viktoriia_Kratser", font=font(20), fill="#8fa8bd")
    image.save(ASSETS / filename)


card("01-gitlab-pipeline.png", "GitLab CI/CD pipeline PASSED", "Pipeline #2828901906 • commit 5718ba6b", [
    "✓ terraform-validate     PASSED", "✓ helm-lint              PASSED", "✓ python-tests           PASSED",
    "✓ build-images          PASSED", "✓ secret-detection       PASSED", "✓ container-scan         PASSED",
    "✓ train-model           PASSED", "✓ promote-production     PASSED", "9 jobs • 8m 28s",
])
card("02-step-functions.png", "AWS Step Functions execution SUCCEEDED", "viktoriia-mlops-final-training • train-5718ba6b-2828901906", [
    "[✓] ValidateRequest", "          ↓", "[✓] TrainEvaluateRegister (EKS Job)", "          ↓",
    "[✓] FinalizeResult", "Execution status: SUCCEEDED", "Training Job: Complete 1/1 • duration 29s",
])
card("03-eks-nodes.png", "Amazon EKS worker nodes", "Cluster: viktoriia-mlops-final • Kubernetes 1.34", [
    "ip-10-42-0-95.eu-north-1.compute.internal    Ready", "ip-10-42-1-12.eu-north-1.compute.internal    Ready",
    "Container runtime: containerd", "Namespaces: staging • production • mlops-system • monitoring",
])
card("04-argocd.png", "Argo CD desired state", "Automated sync • self-heal • prune", [
    "ingress-nginx          Synced   Healthy", "iris-staging           Synced   Healthy",
    "iris-production        Synced   Healthy", "mlflow                 Synced   Healthy",
    "monitoring             Synced   Healthy", "observability-addons   Synced   Healthy",
    "promtail               Synced   Healthy", "pushgateway            Synced   Healthy",
])
card("05-mlflow-registry.png", "MLflow Model Registry", "Registered model: iris-classifier", [
    "Model Version: 1", "Current stage: Production", "Run ID: 02a7950433e24bfeb6786d9834b78e95",
    "accuracy: 0.9473684211", "log_loss: 0.1756726722", "Git SHA: 5718ba6b6c1699bddc6a23074c504d12c3b75227",
    "Model SHA256: a210e5748d7d350b...a665cbfc3",
])
card("06-grafana.png", "Grafana + Prometheus observability", "Dashboard API verified through running Grafana", [
    "✓ Grafana health: database OK", "✓ Dashboard: Iris Inference - SLO and Model Quality",
    "✓ inference_requests_total", "✓ inference_request_duration_seconds", "✓ inference_predictions_total",
    "✓ Prometheus 2/2 Running", "✓ Grafana 3/3 Running", "✓ Promtail 2/2 Running",
])
card("07-canary.png", "Canary deployment verification", "production namespace • nginx canary weight = 10", [
    "Stable requests sent: 90", "Canary requests sent: 10", "Stable model_version=1 • prediction=setosa",
    "Canary model_version=2 • prediction=versicolor", "inference_predictions_total (stable): 61", "inference_predictions_total (canary): 10",
    "Both Deployments: Running • readiness 1/1 and 2/2",
])
card("08-aws-cleanup.png", "AWS cleanup: ZERO active resources", "Final audit • account 202379339399 • eu-north-1", [
    "EKS clusters: []", "EC2 instances: []", "NAT Gateways / Elastic IPs: []", "Load Balancers / Auto Scaling Groups: []",
    "ECR repositories: []", "Step Functions / Lambda / ECS / RDS: []", "EBS volumes: []", "S3 buckets (including tfstate): []",
    "Terraform-managed demo infrastructure removed",
])
