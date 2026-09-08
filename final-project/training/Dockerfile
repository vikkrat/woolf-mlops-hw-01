FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1
WORKDIR /workspace
COPY requirements.txt .
RUN pip install --no-cache-dir --requirement requirements.txt \
    && addgroup --system --gid 10001 trainer \
    && adduser --system --uid 10001 --ingroup trainer trainer
COPY --chown=trainer:trainer src ./src
USER 10001:10001
CMD ["python", "-m", "src.train_register"]
