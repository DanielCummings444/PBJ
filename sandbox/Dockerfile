FROM python:3.12-slim

LABEL maintainer="PBJ Project"
LABEL description="PBIP Analyzer MCP Server — Power BI Project analysis tool"

ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

# Install dependencies first for better layer caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the application
COPY pyproject.toml .
COPY pbip_analyzer/ ./pbip_analyzer/

# Install the package itself
RUN pip install --no-cache-dir -e .

# Create directories for PBIP projects and output reports
RUN mkdir -p /data/projects /data/reports

# Entrypoint
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["entrypoint.sh"]
CMD ["python", "-m", "pbip_analyzer.server"]
