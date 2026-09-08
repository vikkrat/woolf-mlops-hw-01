FROM python:3.12-slim
ENV PIP_NO_CACHE_DIR=1 PYTHONUNBUFFERED=1
WORKDIR /mlflow
COPY requirements.txt .
RUN pip install --no-cache-dir --requirement requirements.txt \
    && addgroup --system --gid 10001 mlflow \
    && adduser --system --uid 10001 --ingroup mlflow mlflow
USER 10001:10001
EXPOSE 5000
ENTRYPOINT ["mlflow", "server"]
CMD ["--host", "0.0.0.0", "--port", "5000"]
