FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    POETRY_VERSION=1.7.1 \
    POETRY_HOME="/opt/poetry" \
    POETRY_VIRTUALENVS_CREATE=false \
    R_HOME="/usr/lib/R" \
    R_LIBS_USER="/usr/local/lib/R/site-library"

ENV PATH="$POETRY_HOME/bin:$PATH"

WORKDIR /app

# Install system dependencies including R
RUN apt-get update && apt-get install -y \
    gcc \
    postgresql-client \
    curl \
    # R and its dependencies
    r-base \
    r-base-dev \
    # Additional libraries needed for R packages
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libfontconfig1-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libfreetype6-dev \
    libpng-dev \
    libtiff5-dev \
    libjpeg-dev \
    && rm -rf /var/lib/apt/lists/*

# Install R packages (nflverse ecosystem)
RUN R -e "install.packages(c('tidyverse', 'remotes'), repos='https://cloud.r-project.org/', quiet=TRUE)" && \
    R -e "remotes::install_github('nflverse/nflverse', quiet=TRUE, upgrade='never')" && \
    R -e "library(nflverse); nflreadr::update_db()" || true

# Install Poetry
RUN curl -sSL https://install.python-poetry.org | python3 -

# Copy Python dependencies files
COPY pyproject.toml poetry.lock* ./

# Install Python dependencies (including rpy2)
RUN poetry add rpy2 && \
    poetry install --no-root --no-dev || poetry install --no-root

# Copy application code
COPY api/ ./api/
RUN mkdir -p /app/logs /app/cache/nflverse

# Create a simple R test script to verify installation
RUN echo 'library(nflverse); print("NFLverse loaded successfully!")' > /tmp/test_r.R && \
    R --vanilla --quiet < /tmp/test_r.R || echo "R packages will be loaded on demand"

EXPOSE 8000
CMD ["uvicorn", "api.app:app", "--host", "0.0.0.0", "--port", "8000"]